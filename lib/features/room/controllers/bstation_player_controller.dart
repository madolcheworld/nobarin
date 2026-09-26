import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../models/video_quality.dart';

/// Controller for Bstation / Bilibili player via WebViewController & HTML5 video bridge
class BstationPlayerController extends ChangeNotifier {
  final GlobalKey webViewKey = GlobalKey(debugLabel: 'BstationWebView');
  WebViewController? _webViewController;
  String _url = '';
  double _position = 0.0;
  double _duration = 0.0;
  bool _isPlaying = false;
  bool _isMuted = false;
  double _volume = 1.0;
  double _playbackSpeed = 1.0;
  bool _isDisposed = false;
  bool _isFullscreenTransition = false;

  void setFullscreenTransition(bool active) {
    _isFullscreenTransition = active;
  }

  // Video Quality state for Bstation (populated dynamically from page/API)
  List<VideoQuality> _availableQualities = [
    const VideoQuality.auto(
      label: 'Auto (Otomatis Bstation)',
      mode: QualityControlMode.webviewBridge,
    ),
  ];
  VideoQuality? _selectedQuality;
  int? _detectedHeight;
  int? _detectedWidth;

  BstationPlayerController() {
    _selectedQuality = _availableQualities.first;
  }

  void Function(double position)? onPositionChanged;
  void Function(double duration)? onDurationChanged;
  void Function(bool isPlaying)? onPlayingChanged;
  void Function()? onPlaybackEnded;
  void Function(String error)? onError;
  void Function(List<VideoQuality> qualities)? onQualitiesChanged;
  void Function(VideoQuality quality)? onQualitySelectedChanged;

  WebViewController? get webViewController => _webViewController;
  String get url => _url;
  double get position => _position;
  double get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get isMuted => _isMuted;
  double get volume => _volume;
  double get playbackSpeed => _playbackSpeed;
  List<VideoQuality> get availableQualities => List.unmodifiable(_availableQualities);
  VideoQuality? get selectedQuality => _selectedQuality;
  int? get detectedHeight => _detectedHeight;
  int? get detectedWidth => _detectedWidth;

  bool get _isSupportedMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Loads media URL and applies player styling and JS event hooks
  Future<void> loadUrl(
    String url, {
    bool autoPlay = false,
    double startSeconds = 0.0,
  }) async {
    _url = url;
    _position = startSeconds;
    _isPlaying = autoPlay;
    _availableQualities = [
      const VideoQuality.auto(
        label: 'Auto (Otomatis Bstation)',
        mode: QualityControlMode.webviewBridge,
      ),
    ];
    _selectedQuality = _availableQualities.first;
    _detectedHeight = null;
    _detectedWidth = null;
    notifyListeners();
    onQualitiesChanged?.call(List.unmodifiable(_availableQualities));

    if (!_isSupportedMobilePlatform) {
      if (!kIsWeb) {
        onError?.call('Bstation player hanya didukung pada platform Android & iOS. Silakan gunakan sumber YouTube atau Direct Video.');
      }
      return;
    }

    try {
      final targetUri = _resolveTargetUri(url, autoPlay: autoPlay);

      if (_webViewController == null) {
        late final PlatformWebViewControllerCreationParams params;
        if (WebViewPlatform.instance is WebKitWebViewPlatform) {
          params = WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          );
        } else if (WebViewPlatform.instance is AndroidWebViewPlatform) {
          params = AndroidWebViewControllerCreationParams();
        } else {
          params = const PlatformWebViewControllerCreationParams();
        }

        final controller = WebViewController.fromPlatformCreationParams(params)
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setUserAgent(
            'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          )
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageFinished: (finishedUrl) {
                _injectPlayerOptimizations(
                  autoPlay: autoPlay,
                  startSeconds: startSeconds,
                );
              },
              onNavigationRequest: (request) {
                final uri = Uri.tryParse(request.url);
                if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
                  return NavigationDecision.prevent;
                }
                return NavigationDecision.navigate;
              },
              onWebResourceError: (error) {
                onError?.call(error.description);
              },
            ),
          )
          ..addJavaScriptChannel(
            'NobarBstationPlayer',
            onMessageReceived: (message) {
              _handlePlayerBridgeMessage(message.message);
            },
          );

        final platform = controller.platform;
        if (platform is AndroidWebViewController) {
          await platform.setMediaPlaybackRequiresUserGesture(false);
        }

        await controller.loadRequest(targetUri);
        _webViewController = controller;
      } else {
        final platform = _webViewController!.platform;
        if (platform is AndroidWebViewController) {
          await platform.setMediaPlaybackRequiresUserGesture(false);
        }
        await _webViewController!.loadRequest(targetUri);
      }
      notifyListeners();
    } catch (e) {
      onError?.call('Gagal menginisialisasi pemutar Bstation: $e');
    }
  }

  /// Converts BV ID or raw URLs to appropriate embed or player URIs
  Uri _resolveTargetUri(String rawUrl, {required bool autoPlay}) {
    final trimmed = rawUrl.trim();

    // Check if it's a bilibili.com BV video (standard bilibili embed player)
    final bvMatch = RegExp(r'(BV[0-9a-zA-Z]{10})').firstMatch(trimmed);
    if (bvMatch != null && trimmed.contains('bilibili.com')) {
      final bvid = bvMatch.group(1)!;
      return Uri.parse(
        'https://player.bilibili.com/player.html?bvid=$bvid&autoplay=${autoPlay ? 1 : 0}&danmaku=0&high_quality=1',
      );
    }

    return Uri.parse(trimmed);
  }

  /// Injects CSS and JavaScript to remove browser UI clutter and attach video listeners
  Future<void> _injectPlayerOptimizations({
    required bool autoPlay,
    required double startSeconds,
  }) async {
    if (_webViewController == null || _isDisposed) return;

    final script = '''
      (function() {
        // 1. Inject custom styling to maximize video player and hide clutter
        var existingStyle = document.getElementById('nobar-player-style');
        if (!existingStyle) {
          var style = document.createElement('style');
          style.id = 'nobar-player-style';
          style.textContent = `
            header, nav, footer,
            .bstar-header, .bstar-footer, .bstar-open-app, .bstar-app-banner,
            .app-download, .open-app, .openapp,
            .bstar-comment, .bstar-recommend, .episode-list-wrap,
            .bstar-web-player__ad,
            .dialog, .dialog__wrap, .dialog__container, .video-toapp-dialog,
            .dialog--mobile, .video-toapp-content, .bstar-dialog,
            .bstar-dialog-mask, .bstar-dialog__wrapper, .bstar-modal,
            .bstar-mask, .bstar-openapp-dialog, .open-app-dialog,
            .bstar-pop, .bstar-pop-wrap, .bstar-popup,
            [class*="video-toapp"], [class*="toapp"], [class*="open-app"],
            [class*="openapp"], [class*="app-download"] {
              display: none !important;
              opacity: 0 !important;
              pointer-events: none !important;
              visibility: hidden !important;
              z-index: -9999 !important;
            }
            html, body {
              background-color: #000 !important;
              margin: 0 !important;
              padding: 0 !important;
              overflow: hidden !important;
              width: 100% !important;
              height: 100% !important;
            }
            .bstar-player, .player-container, .bstar-web-player, #player,
            .player, #bilibiliPlayer, .player-mobile, .player-mobile-area,
            .player-mobile-box, .player-mobile-video-wrap {
              width: 100vw !important;
              height: 100vh !important;
              position: fixed !important;
              top: 0 !important;
              left: 0 !important;
              z-index: 99999 !important;
            }
            video {
              width: 100% !important;
              height: 100% !important;
              object-fit: contain !important;
            }
          `;
          document.head.appendChild(style);
        }

        // 2. Attach video listeners
        function setupVideoBridge() {
          var video = document.querySelector('video');
          if (!video) return;

          if (!video.__nobarAttached) {
            video.__nobarAttached = true;

            ${startSeconds > 0 ? "video.currentTime = $startSeconds;" : ""}
            video.volume = $_volume;
            video.muted = ${_isMuted ? "true" : "false"};
            ${autoPlay ? "video.play().catch(function(){});" : ""}

            video.addEventListener('timeupdate', function() {
              if (window.NobarBstationPlayer) {
                window.NobarBstationPlayer.postMessage(JSON.stringify({
                  event: 'timeupdate',
                  currentTime: video.currentTime,
                  duration: video.duration || 0
                }));
              }
            });

            video.addEventListener('play', function() {
              if (window.NobarBstationPlayer) {
                window.NobarBstationPlayer.postMessage(JSON.stringify({
                  event: 'play'
                }));
              }
            });

            video.addEventListener('pause', function() {
              if (window.NobarBstationPlayer) {
                window.NobarBstationPlayer.postMessage(JSON.stringify({
                  event: 'pause'
                }));
              }
            });

            video.addEventListener('ended', function() {
              if (window.NobarBstationPlayer) {
                window.NobarBstationPlayer.postMessage(JSON.stringify({
                  event: 'ended'
                }));
              }
            });

            video.addEventListener('durationchange', function() {
              if (window.NobarBstationPlayer) {
                window.NobarBstationPlayer.postMessage(JSON.stringify({
                  event: 'durationchange',
                  duration: video.duration || 0
                }));
              }
            });

            // 3. Track actual video resolution
            function reportBstationResolution() {
              if (video && video.videoHeight > 0) {
                if (video.__nobarLastH !== video.videoHeight || video.__nobarLastW !== video.videoWidth) {
                  video.__nobarLastH = video.videoHeight;
                  video.__nobarLastW = video.videoWidth;
                  if (window.NobarBstationPlayer) {
                    window.NobarBstationPlayer.postMessage(JSON.stringify({
                      event: 'resolution',
                      height: video.videoHeight,
                      width: video.videoWidth
                    }));
                  }
                }
              }
            }
            video.addEventListener('loadedmetadata', reportBstationResolution);
            video.addEventListener('resize', reportBstationResolution);
            // 4. Track available qualities from page & network playurl responses
            function extractFromPlayInfoObj(pData, addQualityItem, qMap, hMap) {
              if (!pData || typeof pData !== 'object') return;
              var sfList = pData.support_formats || (pData.playurl && pData.playurl.support_formats) || (pData.video_resource && pData.video_resource.support_formats);
              if (Array.isArray(sfList)) {
                for (var i = 0; i < sfList.length; i++) {
                  var sf = sfList[i];
                  var qCode = sf.quality;
                  var hVal = sf.height || hMap[qCode];
                  var desc = sf.new_description || sf.display_desc || sf.description || qMap[qCode];
                  if (!hVal && desc) {
                    var m = String(desc).match(/(\\d{3,4})[pP]?/);
                    if (m) hVal = parseInt(m[1], 10);
                  }
                  if (hVal) {
                    addQualityItem(String(hVal), hVal, desc || (hVal + 'p'));
                  }
                }
              }
              var dashVideos = (pData.dash && pData.dash.video) || (pData.playurl && pData.playurl.video) || (pData.video_resource && pData.video_resource.dash && pData.video_resource.dash.video);
              if (Array.isArray(dashVideos)) {
                for (var k = 0; k < dashVideos.length; k++) {
                  var dv = dashVideos[k];
                  var dvObj = dv.video_resource || dv;
                  var qId = dvObj.id || dvObj.quality;
                  var dvH = dvObj.height || hMap[qId];
                  var dvDesc = dvObj.description || dvObj.new_description || qMap[qId];
                  if (dvH) {
                    addQualityItem(String(dvH), dvH, dvDesc || (dvH + 'p'));
                  }
                }
              }
              var acc = pData.accept_quality || (pData.playurl && pData.playurl.accept_quality);
              if (Array.isArray(acc)) {
                for (var j = 0; j < acc.length; j++) {
                  var code = acc[j];
                  if (hMap[code]) {
                    addQualityItem(String(hMap[code]), hMap[code], qMap[code] || (hMap[code] + 'p'));
                  }
                }
              }
            }

            if (!window.__nobarBstationHookInstalled) {
              window.__nobarBstationHookInstalled = true;
              window.__nobarBstationPayloads = [];
              try {
                var origFetch = window.fetch;
                if (typeof origFetch === 'function') {
                  window.fetch = function() {
                    var p = origFetch.apply(this, arguments);
                    try {
                      var reqUrl = arguments[0] ? String(arguments[0].url || arguments[0]) : '';
                      if (reqUrl.indexOf('playurl') !== -1 || reqUrl.indexOf('video') !== -1 || reqUrl.indexOf('play') !== -1) {
                        p.then(function(resp) {
                          try {
                            resp.clone().json().then(function(json) {
                              if (json && (json.data || json.result)) {
                                window.__nobarBstationPayloads.push(json.data || json.result);
                                reportBstationQualities();
                              }
                            }).catch(function(){});
                          } catch (_) {}
                        }).catch(function(){});
                      }
                    } catch (_) {}
                    return p;
                  };
                }
                var origOpen = XMLHttpRequest.prototype.open;
                var origSend = XMLHttpRequest.prototype.send;
                XMLHttpRequest.prototype.open = function(method, url) {
                  this.__nobarUrl = String(url || '');
                  return origOpen.apply(this, arguments);
                };
                XMLHttpRequest.prototype.send = function() {
                  var xhr = this;
                  if (xhr.__nobarUrl && (xhr.__nobarUrl.indexOf('playurl') !== -1 || xhr.__nobarUrl.indexOf('video') !== -1)) {
                    xhr.addEventListener('load', function() {
                      try {
                        var json = JSON.parse(xhr.responseText);
                        if (json && (json.data || json.result)) {
                          window.__nobarBstationPayloads.push(json.data || json.result);
                          reportBstationQualities();
                        }
                      } catch (_) {}
                    });
                  }
                  return origSend.apply(this, arguments);
                };
              } catch (_) {}
            }

            function reportBstationQualities() {
              try {
                var detected = [];
                var qMap = { 125: 'HDR', 120: '4K Ultra HD', 116: '1080p 60fps', 112: '1080p+ Tinggi', 80: '1080p HD', 74: '720p 60fps', 64: '720p HD', 32: '480p Standar', 16: '360p Hemat', 6: '240p Hemat' };
                var hMap = { 125: 2160, 120: 2160, 116: 1080, 112: 1080, 80: 1080, 74: 720, 64: 720, 32: 480, 16: 360, 6: 240 };

                function addQualityItem(idStr, heightNum, labelStr) {
                  if (!idStr || !heightNum || isNaN(heightNum) || heightNum <= 0) return;
                  for (var idx = 0; idx < detected.length; idx++) {
                    if (detected[idx].id === String(idStr)) return;
                  }
                  detected.push({ id: String(idStr), height: heightNum, label: labelStr || (heightNum + 'p') });
                }

                // Method 0: Intercepted network playurl responses
                if (Array.isArray(window.__nobarBstationPayloads)) {
                  for (var pIdx = 0; pIdx < window.__nobarBstationPayloads.length; pIdx++) {
                    extractFromPlayInfoObj(window.__nobarBstationPayloads[pIdx], addQualityItem, qMap, hMap);
                  }
                }

                // Method A: Bilibili __playinfo__ global (support_formats, accept_quality, dash.video)
                if (window.__playinfo__) {
                  extractFromPlayInfoObj(window.__playinfo__.data || window.__playinfo__.result || window.__playinfo__, addQualityItem, qMap, hMap);
                }

                // Method B: Bstation / Bilibili global player instance
                if (detected.length === 0 && window.player && typeof window.player.getSupportedQualityList === 'function') {
                  var qList = window.player.getSupportedQualityList();
                  if (Array.isArray(qList)) {
                    for (var qIdx = 0; qIdx < qList.length; qIdx++) {
                      var qVal = qList[qIdx];
                      var qH = hMap[qVal] || (qVal >= 144 && qVal <= 4320 ? qVal : null);
                      if (qH) {
                        addQualityItem(String(qH), qH, qMap[qVal] || (qH + 'p'));
                      }
                    }
                  }
                }

                // Method C: Bstation __initialState__ (bilibili.tv)
                if (detected.length === 0 && window.__initialState__) {
                  var initStr = '';
                  try { initStr = JSON.stringify(window.__initialState__); } catch (_) {}
                  if (initStr) {
                    var resMatches = initStr.match(/"(2160|1440|1080|720|480|360|240)[pP]?"/g);
                    if (resMatches) {
                      for (var rm = 0; rm < resMatches.length; rm++) {
                        var numMatch = resMatches[rm].match(/(\\d{3,4})/);
                        if (numMatch) {
                          var parsedH = parseInt(numMatch[1], 10);
                          addQualityItem(String(parsedH), parsedH, parsedH + 'p');
                        }
                      }
                    }
                  }
                }

                // Method D: Quality menu items in DOM
                if (detected.length === 0) {
                  var qItems = document.querySelectorAll('.bpx-player-ctrl-quality-menu-item, .bstar-web-player__quality-item, [class*="quality-item"], [class*="quality-menu"] li');
                  qItems.forEach(function(item) {
                    var text = (item.textContent || '').trim();
                    var val = (item.getAttribute('data-quality') || item.getAttribute('data-value') || '').trim();
                    var is4K = /4[kK]/.test(text);
                    var match = text.match(/(\\d{3,4})[pP]?/);
                    var h = is4K ? 2160 : (match ? parseInt(match[1], 10) : (hMap[parseInt(val, 10)] || parseInt(val, 10)));
                    if (h && !isNaN(h) && h >= 144) {
                      addQualityItem(String(h), h, text || (h + 'p'));
                    }
                  });
                }
                if (detected.length > 0 && window.NobarBstationPlayer) {
                  window.NobarBstationPlayer.postMessage(JSON.stringify({
                    event: 'qualities',
                    qualities: detected
                  }));
                }
              } catch (e) {}
            }
            setInterval(reportBstationQualities, 2000);
            reportBstationQualities();
          }
        }

        // 5. Continuously eliminate app-download modals, dialogs, and popups
        function cleanBstationClutter() {
          try {
            var unwanted = document.querySelectorAll(
              '.dialog, .video-toapp-dialog, .dialog__wrap, .dialog__container, ' +
              '[class*="toapp"], [class*="video-toapp"], .bstar-open-app, .bstar-app-banner, ' +
              '.open-app, .openapp, .app-download, [class*="open-app"], [class*="openapp"], ' +
              '.bstar-dialog, .bstar-dialog-mask, .bstar-modal, .bstar-mask, .bstar-popup'
            );
            unwanted.forEach(function(el) {
              if (!el.querySelector('video') && el.tagName !== 'VIDEO') {
                el.remove();
              }
            });
          } catch(e) {}
        }

        setInterval(setupVideoBridge, 600);
        setInterval(cleanBstationClutter, 400);
        setupVideoBridge();
        cleanBstationClutter();
      })();
    ''';

    try {
      await _webViewController!.runJavaScript(script);
    } catch (_) {}
  }

  void _handlePlayerBridgeMessage(String rawJson) {
    if (_isDisposed) return;
    try {
      final data = jsonDecode(rawJson);
      if (data is Map<String, dynamic>) {
        final event = data['event'] as String? ?? '';
        switch (event) {
          case 'timeupdate':
            final cur = (data['currentTime'] as num?)?.toDouble() ?? 0.0;
            final dur = (data['duration'] as num?)?.toDouble() ?? 0.0;
            if ((cur - _position).abs() >= 0.3) {
              _position = cur;
              notifyListeners();
              onPositionChanged?.call(_position);
            }
            if (dur > 0 && dur != _duration) {
              _duration = dur;
              notifyListeners();
              onDurationChanged?.call(_duration);
            }
            break;
          case 'durationchange':
            final dur = (data['duration'] as num?)?.toDouble() ?? 0.0;
            if (dur > 0 && dur != _duration) {
              _duration = dur;
              notifyListeners();
              onDurationChanged?.call(_duration);
            }
            break;
          case 'resolution':
            final h = (data['height'] as num?)?.toInt();
            final w = (data['width'] as num?)?.toInt();
            final normH = VideoQuality.normalizeResolutionHeight(width: w, height: h);
            if (normH != null && normH > 0 && normH != _detectedHeight) {
              _detectedHeight = normH;
              _detectedWidth = w;
              notifyListeners();
            }
            break;
          case 'qualities':
            final rawList = data['qualities'];
            if (rawList is List && rawList.isNotEmpty) {
              _updateQualitiesFromBridge(rawList);
            }
            break;
          case 'qualitychange':
            final curQ = data['quality']?.toString();
            if (curQ != null && curQ.isNotEmpty) {
              _selectedQuality = _availableQualities.firstWhere(
                (q) => q.id == curQ,
                orElse: () => VideoQuality.bstation(id: curQ, label: '${curQ}p'),
              );
              notifyListeners();
              onQualitySelectedChanged?.call(_selectedQuality!);
            }
            break;
          case 'play':
            if (!_isPlaying) {
              _isPlaying = true;
              notifyListeners();
              onPlayingChanged?.call(true);
            }
            break;
          case 'pause':
            if (_isFullscreenTransition && _isPlaying) {
              debugPrint('[BstationPlayer] Spurious OS pause ignored during fullscreen transition. Resuming...');
              play();
              break;
            }
            if (_isPlaying) {
              _isPlaying = false;
              notifyListeners();
              onPlayingChanged?.call(false);
            }
            break;
          case 'play_error':
            debugPrint('[BstationPlayer] Play error from JS: ${data['name']} - ${data['message']}');
            break;
          case 'ended':
            _isPlaying = false;
            notifyListeners();
            onPlaybackEnded?.call();
            break;
        }
      }
    } catch (_) {}
  }

  void _updateQualitiesFromBridge(List<dynamic> rawList) {
    final detected = <VideoQuality>[
      const VideoQuality.auto(
        label: 'Auto (Otomatis Bstation)',
        mode: QualityControlMode.webviewBridge,
      ),
    ];
    for (final item in rawList) {
      if (item is Map) {
        final id = item['id']?.toString();
        final label = item['label']?.toString() ?? '${id}p';
        final height = (item['height'] as num?)?.toInt();
        if (id != null && id.isNotEmpty && id != 'auto') {
          if (!detected.any((q) => q.id == id)) {
            detected.add(VideoQuality.bstation(
              id: id,
              label: label,
              height: height,
            ));
          }
        }
      } else if (item is String || item is num) {
        final id = item.toString();
        if (id != 'auto' && !detected.any((q) => q.id == id)) {
          final h = int.tryParse(id);
          detected.add(VideoQuality.bstation(
            id: id,
            label: h != null ? '${h}p' : id,
            height: h,
          ));
        }
      }
    }
    // Sort descending by height (excluding auto)
    detected.sort((a, b) {
      if (a.isAuto) return -1;
      if (b.isAuto) return 1;
      return (b.height ?? 0).compareTo(a.height ?? 0);
    });
    _availableQualities = detected;
    notifyListeners();
    onQualitiesChanged?.call(List.unmodifiable(_availableQualities));
  }

  @visibleForTesting
  void handleBridgeMessageForTesting(String rawJson) => _handlePlayerBridgeMessage(rawJson);

  /// Sets video quality for Bstation player
  Future<void> setQuality(String qualityId) async {
    _selectedQuality = _availableQualities.firstWhere(
      (q) => q.id == qualityId,
      orElse: () => VideoQuality.bstation(id: qualityId, label: '${qualityId}p'),
    );
    notifyListeners();
    onQualitySelectedChanged?.call(_selectedQuality!);

    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript('''
          (function(targetId) {
            try {
              var codeMap = {
                '2160': 120,
                '1080_60': 116,
                '1080+': 112,
                '1080': 80,
                '720_60': 74,
                '720': 64,
                '480': 32,
                '360': 16,
                '240': 6,
                'auto': -1
              };
              var qCode = codeMap[targetId] || parseInt(targetId, 10) || 0;

              // 1. Try to open quality menu if closed (for Bstation / Bilibili web)
              var menuTriggers = [
                '.bstar-web-player__quality-btn',
                '.bpx-player-ctrl-quality',
                '.player-mobile-control-quality',
                '[class*="quality-btn"]',
                '[class*="ctrl-quality"]'
              ];
              for (var m = 0; m < menuTriggers.length; m++) {
                var trigger = document.querySelector(menuTriggers[m]);
                if (trigger) {
                  trigger.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true }));
                }
              }

              // 2. Check quality buttons in Bstation web player
              var selectors = [
                '.bpx-player-ctrl-quality-menu-item',
                '.bstar-web-player__quality-item',
                '.player-mobile-control-quality-item',
                '[class*="quality-menu-item"]',
                '[class*="quality-item"]',
                '[class*="quality_item"]',
                '.quality-wrap li',
                '[data-quality]',
                '[data-value]'
              ];
              var items = document.querySelectorAll(selectors.join(','));
              for (var i = 0; i < items.length; i++) {
                var el = items[i];
                var text = (el.textContent || '').toLowerCase().trim();
                var val = (el.getAttribute('data-quality') || el.getAttribute('data-value') || '').trim();

                var isMatch = false;
                if (targetId === 'auto') {
                  if (val === 'auto' || val === '-1' || text.indexOf('auto') !== -1 || text.indexOf('otomatis') !== -1 || text.indexOf('自动') !== -1) {
                    isMatch = true;
                  }
                } else {
                  if (val === targetId || (qCode > 0 && val === String(qCode)) || text.indexOf(targetId) !== -1) {
                    isMatch = true;
                  }
                }

                if (isMatch) {
                  el.click();
                  return;
                }
              }

              // 3. Try bilibili / bstation player instance if available
              if (window.player) {
                if (qCode > 0) {
                  if (typeof window.player.requestQuality === 'function') {
                    window.player.requestQuality(qCode);
                    return;
                  }
                  if (typeof window.player.switchQuality === 'function') {
                    window.player.switchQuality(qCode);
                    return;
                  }
                }
                if (typeof window.player.switchQuality === 'function') {
                  window.player.switchQuality(parseInt(targetId, 10));
                }
              }
            } catch (e) {}
          })('$qualityId');
        ''');
      } catch (_) {}
    }
  }

  Future<void> play() async {
    _isPlaying = true;
    notifyListeners();
    if (_webViewController != null) {
      final platform = _webViewController!.platform;
      if (platform is AndroidWebViewController) {
        try {
          await platform.setMediaPlaybackRequiresUserGesture(false);
        } catch (_) {}
      }
      try {
        await _webViewController!.runJavaScript('''
          (function() {
            var videos = document.querySelectorAll('video');
            if (videos.length > 0) {
              videos.forEach(function(v) {
                var p = v.play();
                if (p !== undefined) {
                  p.catch(function(e) {
                    console.log('[Nobarin Bstation] play error: ' + (e.name || '') + ' - ' + (e.message || ''));
                    if (window.NobarBstationPlayer) {
                      window.NobarBstationPlayer.postMessage(JSON.stringify({
                        event: 'play_error',
                        name: e.name || 'Error',
                        message: e.message || String(e)
                      }));
                    }
                    var playBtn = document.querySelector('.player-mobile-play, .bstar-web-player__play-btn, [class*="play-btn"], [class*="play-icon"]');
                    if (playBtn) playBtn.click();
                  });
                }
              });
            } else {
              var playBtn = document.querySelector('.player-mobile-play, .bstar-web-player__play-btn, [class*="play-btn"], [class*="play-icon"]');
              if (playBtn) playBtn.click();
            }
          })();
        ''');
      } catch (_) {}
    }
  }

  Future<void> pause() async {
    _isPlaying = false;
    notifyListeners();
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript('''
          (function() {
            var videos = document.querySelectorAll('video');
            videos.forEach(function(v) {
              v.pause();
            });
          })();
        ''');
      } catch (_) {}
    }
  }

  Future<void> seekTo(double seconds) async {
    _position = seconds < 0 ? 0 : seconds;
    notifyListeners();
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript(
          "var v = document.querySelector('video'); if (v) v.currentTime = $seconds;",
        );
      } catch (_) {}
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    notifyListeners();
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript(
          "var v = document.querySelector('video'); if (v) v.playbackRate = $speed;",
        );
      } catch (_) {}
    }
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    _isMuted = _volume == 0;
    notifyListeners();
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript(
          "var v = document.querySelector('video'); if (v) { v.volume = $_volume; v.muted = ($_volume === 0); }",
        );
      } catch (_) {}
    }
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    notifyListeners();
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript(
          "var v = document.querySelector('video'); if (v) v.muted = !v.muted;",
        );
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    pause();
    _webViewController = null;
    super.dispose();
  }
}
