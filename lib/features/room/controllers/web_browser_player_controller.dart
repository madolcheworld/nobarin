import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../models/video_quality.dart';

/// Controller for general Web Browser video playback via WebViewController,
/// Universal HTML5 <video> bridge, Cinema Mode CSS isolation, and iframe postMessage bridge.
class WebBrowserPlayerController extends ChangeNotifier {
  final GlobalKey webViewKey = GlobalKey(debugLabel: 'WebBrowserPlayerWebView');
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

  List<VideoQuality> _availableQualities = [
    const VideoQuality.auto(
      label: 'Auto (Otomatis Web)',
      mode: QualityControlMode.webviewBridge,
    ),
  ];
  VideoQuality? _selectedQuality;
  int? _detectedHeight;
  int? _detectedWidth;

  WebBrowserPlayerController() {
    _selectedQuality = _availableQualities.first;
  }

  void Function(double position)? onPositionChanged;
  void Function(double duration)? onDurationChanged;
  void Function(bool isPlaying)? onPlayingChanged;
  void Function()? onPlaybackEnded;
  void Function(String error)? onError;
  void Function(List<VideoQuality> qualities)? onQualitiesChanged;
  void Function(VideoQuality quality)? onQualitySelectedChanged;
  void Function(String streamUrl)? onDirectStreamExtracted;

  WebViewController? get webViewController => _webViewController;
  String get url => _url;
  double get position => _position;
  double get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get isMuted => _isMuted;
  double get volume => _volume;
  double get playbackSpeed => _playbackSpeed;
  List<VideoQuality> get availableQualities =>
      List.unmodifiable(_availableQualities);
  VideoQuality? get selectedQuality => _selectedQuality;
  int? get detectedHeight => _detectedHeight;
  int? get detectedWidth => _detectedWidth;

  bool get _isSupportedMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Strips internal `webbrowser://` prefix if present and returns a valid HTTP(S) URL.
  static String normalizeWebUrl(String rawUrl) {
    var trimmed = rawUrl.trim();
    if (trimmed.startsWith('webbrowser://')) {
      trimmed = trimmed.substring('webbrowser://'.length);
    }
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }
    return trimmed;
  }

  /// Loads the target web page or embed URL and attaches the Universal Video Bridge.
  Future<void> loadUrl(
    String rawUrl, {
    bool autoPlay = false,
    double startSeconds = 0.0,
  }) async {
    final normalizedUrl = normalizeWebUrl(rawUrl);
    _url = normalizedUrl;
    _position = startSeconds;
    _isPlaying = autoPlay;
    _availableQualities = [
      const VideoQuality.auto(
        label: 'Auto (Otomatis Web)',
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
        onError?.call(
          'Pemutar Web Browser terintegrasi didukung penuh di Android & iOS. Gunakan Direct Stream (.m3u8/.mp4) untuk platform Desktop.',
        );
      }
      return;
    }

    try {
      final targetUri = Uri.parse(normalizedUrl);

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
            '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
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
                if (uri == null ||
                    (uri.scheme != 'http' && uri.scheme != 'https')) {
                  return NavigationDecision.prevent;
                }
                // Block known ad/popup redirect patterns on main frame once loaded
                final lowerHost = uri.host.toLowerCase();
                if (request.isMainFrame && _url.isNotEmpty) {
                  final initialHost =
                      Uri.tryParse(_url)?.host.toLowerCase() ?? '';
                  if (_isLikelyAdRedirect(lowerHost, uri.toString(), initialHost)) {
                    debugPrint(
                      '[WebBrowserPlayer] Blocked ad redirect to: ${request.url}',
                    );
                    return NavigationDecision.prevent;
                  }
                }
                return NavigationDecision.navigate;
              },
              onWebResourceError: (error) {
                if (error.isForMainFrame == true) {
                  onError?.call(error.description);
                }
              },
            ),
          )
          ..addJavaScriptChannel(
            'NobarinWebBridge',
            onMessageReceived: (message) {
              _handlePlayerBridgeMessage(message.message);
            },
          );

        final platform = controller.platform;
        if (platform is AndroidWebViewController) {
          await platform.setMediaPlaybackRequiresUserGesture(false);
        }

        await _loadTargetIntoController(controller, targetUri);
        _webViewController = controller;
      } else {
        final platform = _webViewController!.platform;
        if (platform is AndroidWebViewController) {
          await platform.setMediaPlaybackRequiresUserGesture(false);
        }
        await _loadTargetIntoController(_webViewController!, targetUri);
      }
      notifyListeners();
    } catch (e) {
      onError?.call('Gagal menginisialisasi pemutar Web Browser: $e');
    }
  }

  Future<void> _loadTargetIntoController(
    WebViewController controller,
    Uri targetUri,
  ) async {
    final lowerHost = targetUri.host.toLowerCase();
    final lowerPath = targetUri.path.toLowerCase();
    // Some embed gateways (e.g. videonode / playcdn / hydrax) enforce
    // `window.self !== window.top` and refuse to load if opened as top window.
    final requiresIframeWrapper =
        lowerPath.startsWith('/iframe') ||
        lowerHost.contains('videonode.') ||
        lowerHost.contains('playcdn.') ||
        lowerHost.contains('hydrax.');

    if (requiresIframeWrapper) {
      final safeSrc = const HtmlEscape().convert(targetUri.toString());
      final wrapperHtml = '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<style>
html, body { margin: 0; padding: 0; width: 100vw; height: 100vh; background: #000; overflow: hidden; }
iframe { position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; border: none; background: #000; }
</style>
</head>
<body>
<iframe id="main-player" class="__nobarin-active-iframe" src="$safeSrc" allowfullscreen="true" webkitallowfullscreen="true" mozallowfullscreen="true" allow="autoplay; fullscreen; encrypted-media; picture-in-picture"></iframe>
</body>
</html>
''';
      await controller.loadHtmlString(
        wrapperHtml,
        baseUrl: '${targetUri.scheme}://${targetUri.host}/',
      );
    } else {
      await controller.loadRequest(targetUri);
    }
  }

  bool _isLikelyAdRedirect(
    String targetHost,
    String fullUrl,
    String initialHost,
  ) {
    if (initialHost.isEmpty || targetHost == initialHost) return false;
    // Allow subdomains of the same root domain
    final initParts = initialHost.split('.');
    final targetParts = targetHost.split('.');
    if (initParts.length >= 2 && targetParts.length >= 2) {
      final initRoot =
          '${initParts[initParts.length - 2]}.${initParts.last}';
      final targetRoot =
          '${targetParts[targetParts.length - 2]}.${targetParts.last}';
      if (initRoot == targetRoot) return false;
    }

    final lowerUrl = fullUrl.toLowerCase();
    const adPatterns = [
      'doubleclick.net',
      'googlesyndication.com',
      'popads.net',
      'popcash.net',
      'propellerads',
      'adsterra',
      'exoclick',
      'juicyads',
      'clickadu',
      'hilltopads',
      'onclickalgo',
      'yellowishgather',
      'histats.com',
      'whos.amung.us',
      'lk21.de',
      'bet365',
      '1xbet',
    ];
    for (final pattern in adPatterns) {
      if (targetHost.contains(pattern) || lowerUrl.contains(pattern)) {
        return true;
      }
    }
    return false;
  }

  /// Injects Cinema Mode CSS and Universal HTML5 <video> / iframe synchronization bridge.
  Future<void> _injectPlayerOptimizations({
    required bool autoPlay,
    required double startSeconds,
  }) async {
    if (_webViewController == null || _isDisposed) return;

    final script = '''
      (function() {
        // Prevent popup window.open hijacks
        try {
          window.open = function() { return null; };
        } catch (_) {}

        // 1. Inject base dark cinema style
        if (!document.getElementById('nobarin-web-cinema-style')) {
          var style = document.createElement('style');
          style.id = 'nobarin-web-cinema-style';
          style.textContent = `
            html, body {
              background-color: #000 !important;
              margin: 0 !important;
              padding: 0 !important;
              overflow: hidden !important;
              width: 100vw !important;
              height: 100vh !important;
            }
            video.__nobarin-active-video {
              position: fixed !important;
              top: 0 !important;
              left: 0 !important;
              width: 100vw !important;
              height: 100vh !important;
              max-width: 100vw !important;
              max-height: 100vh !important;
              z-index: 2147483646 !important;
              background-color: #000 !important;
              object-fit: contain !important;
              transform: none !important;
            }
            iframe.__nobarin-active-iframe {
              position: fixed !important;
              top: 0 !important;
              left: 0 !important;
              width: 100vw !important;
              height: 100vh !important;
              max-width: 100vw !important;
              max-height: 100vh !important;
              z-index: 2147483646 !important;
              border: none !important;
              background-color: #000 !important;
            }
            #adContainer, #adsContainer, #skipAds, #videoAd, a#uyeouyeo {
              display: none !important;
              visibility: hidden !important;
              pointer-events: none !important;
            }
          `;
          if (document.head) {
            document.head.appendChild(style);
          }
        }

        function isAdVideoElement(v) {
          if (!v) return false;
          var idCls = ((v.id || '') + ' ' + (v.className || '') + ' ' + (v.getAttribute('name') || '')).toLowerCase();
          if (/\b(videoad|advideo|ad-video|ad_video|preroll|midroll|ima-ad|vjs-ad|jw-ad)\b/i.test(idCls)) {
            return true;
          }
          if (v.closest && v.closest('#adContainer, #adsContainer, .ad-container, .ads-container, .ima-ad-container, [id*="adContainer" i], [id*="videoAd" i]')) {
            return true;
          }
          return false;
        }

        // Helper: find all videos including open Shadow DOMs
        function collectAllVideos(root) {
          var list = [];
          try {
            var vids = (root || document).querySelectorAll('video');
            for (var i = 0; i < vids.length; i++) {
              list.push(vids[i]);
            }
            var allEls = (root || document).querySelectorAll('*');
            for (var j = 0; j < allEls.length; j++) {
              if (allEls[j].shadowRoot) {
                var sub = collectAllVideos(allEls[j].shadowRoot);
                for (var k = 0; k < sub.length; k++) list.push(sub[k]);
              }
            }
          } catch (_) {}
          return list;
        }

        // Select the primary content video (prefer playing or longest duration or largest area)
        function pickPrimaryVideo() {
          var videos = collectAllVideos(document);
          if (videos.length === 0) return null;
          var best = null;
          var bestScore = 0;
          for (var i = 0; i < videos.length; i++) {
            var v = videos[i];
            if (isAdVideoElement(v)) continue;
            var score = 0;
            var src = v.currentSrc || v.src || '';
            if (src) score += 20;
            if (!v.paused) score += 50;
            if (v.duration && isFinite(v.duration) && v.duration > 15) score += 40;
            var rect = v.getBoundingClientRect ? v.getBoundingClientRect() : { width: 0, height: 0 };
            var area = (v.videoWidth || rect.width || 0) * (v.videoHeight || rect.height || 0);
            if (area > 40000) score += 30;
            if (score > bestScore) {
              bestScore = score;
              best = v;
            }
          }
          return best;
        }

        function attachToPrimaryVideo() {
          // Immediately neutralize pre-roll ad containers and ad videos
          try {
            var adContainers = document.querySelectorAll('#adContainer, #adsContainer, #skipAds');
            for (var a = 0; a < adContainers.length; a++) {
              if (adContainers[a] && adContainers[a].parentNode) {
                adContainers[a].parentNode.removeChild(adContainers[a]);
              }
            }
            var allCheckVids = collectAllVideos(document);
            for (var av = 0; av < allCheckVids.length; av++) {
              if (isAdVideoElement(allCheckVids[av])) {
                try {
                  allCheckVids[av].pause();
                  allCheckVids[av].muted = true;
                  allCheckVids[av].removeAttribute('src');
                  allCheckVids[av].load();
                } catch (_) {}
              }
            }
          } catch (_) {}

          var video = pickPrimaryVideo();
          if (video) {
            // Apply cinema class to primary video
            var allVids = collectAllVideos(document);
            for (var i = 0; i < allVids.length; i++) {
              if (allVids[i] === video) {
                allVids[i].classList.add('__nobarin-active-video');
              } else {
                allVids[i].classList.remove('__nobarin-active-video');
              }
            }

            if (!video.__nobarinBridgeAttached) {
              video.__nobarinBridgeAttached = true;

              try {
                ${startSeconds > 0 ? "if (Math.abs((video.currentTime || 0) - $startSeconds) > 2) { video.currentTime = $startSeconds; }" : ""}
                video.volume = $_volume;
                video.muted = ${_isMuted ? "true" : "false"};
                video.playbackRate = $_playbackSpeed;
                ${autoPlay ? "video.play().catch(function(){});" : ""}
              } catch (_) {}

              video.addEventListener('timeupdate', function() {
                if (window.NobarinWebBridge) {
                  window.NobarinWebBridge.postMessage(JSON.stringify({
                    event: 'timeupdate',
                    currentTime: video.currentTime || 0,
                    duration: (video.duration && isFinite(video.duration)) ? video.duration : 0
                  }));
                }
              });

              video.addEventListener('play', function() {
                if (window.NobarinWebBridge) {
                  window.NobarinWebBridge.postMessage(JSON.stringify({
                    event: 'play'
                  }));
                }
              });

              video.addEventListener('playing', function() {
                if (window.NobarinWebBridge) {
                  window.NobarinWebBridge.postMessage(JSON.stringify({
                    event: 'play'
                  }));
                }
              });

              video.addEventListener('pause', function() {
                if (window.NobarinWebBridge) {
                  window.NobarinWebBridge.postMessage(JSON.stringify({
                    event: 'pause'
                  }));
                }
              });

              video.addEventListener('ended', function() {
                if (window.NobarinWebBridge) {
                  window.NobarinWebBridge.postMessage(JSON.stringify({
                    event: 'ended'
                  }));
                }
              });

              video.addEventListener('durationchange', function() {
                if (window.NobarinWebBridge && video.duration && isFinite(video.duration)) {
                  window.NobarinWebBridge.postMessage(JSON.stringify({
                    event: 'durationchange',
                    duration: video.duration
                  }));
                }
              });

              function reportResolution() {
                if (video && video.videoHeight > 0) {
                  if (video.__nobarLastH !== video.videoHeight || video.__nobarLastW !== video.videoWidth) {
                    video.__nobarLastH = video.videoHeight;
                    video.__nobarLastW = video.videoWidth;
                    if (window.NobarinWebBridge) {
                      window.NobarinWebBridge.postMessage(JSON.stringify({
                        event: 'resolution',
                        height: video.videoHeight,
                        width: video.videoWidth
                      }));
                    }
                  }
                }
              }

              video.addEventListener('loadedmetadata', reportResolution);
              video.addEventListener('resize', reportResolution);
              reportResolution();
              detectWebPlayerQualities();
            }
            return;
          }

          // Fallback: if no direct <video> in top document, check for prominent video <iframe>
          var iframes = document.querySelectorAll('iframe');
          var bestIframe = null;
          var bestArea = 0;
          for (var f = 0; f < iframes.length; f++) {
            var ifr = iframes[f];
            var src = (ifr.src || '').toLowerCase();
            if (!src || src.indexOf('ads') !== -1 || src.indexOf('doubleclick') !== -1 || src.indexOf('googlesyndication') !== -1) continue;
            var r = ifr.getBoundingClientRect();
            var area = r.width * r.height;
            var isNamedPlayer = (ifr.id || '').toLowerCase().indexOf('player') !== -1 ||
                                (ifr.name || '').toLowerCase().indexOf('player') !== -1;
            var hasAllowFs = ifr.hasAttribute('allowfullscreen') || (ifr.getAttribute('allow') || '').indexOf('fullscreen') !== -1;
            if ((area > 30000 || hasAllowFs || isNamedPlayer) && (area >= bestArea || isNamedPlayer)) {
              bestArea = Math.max(area, 1);
              bestIframe = ifr;
              if (isNamedPlayer) break;
            }
          }
          if (bestIframe) {
            bestIframe.classList.add('__nobarin-active-iframe');
            if (!bestIframe.__nobarinReported && bestIframe.src && window.NobarinWebBridge) {
              bestIframe.__nobarinReported = true;
              window.NobarinWebBridge.postMessage(JSON.stringify({
                event: 'iframe_detected',
                src: bestIframe.src
              }));
            }
          }
        }

        // Detect qualities from common web players (JWPlayer, Plyr, HLS.js, DOM menus)
        function detectWebPlayerQualities() {
          try {
            var detected = [];
            function addQ(idStr, hNum, labelStr) {
              if (!idStr || !hNum || isNaN(hNum) || hNum < 144) return;
              for (var i = 0; i < detected.length; i++) {
                if (detected[i].id === String(idStr)) return;
              }
              detected.push({ id: String(idStr), height: hNum, label: labelStr || (hNum + 'p') });
            }

            // JWPlayer API
            if (typeof window.jwplayer === 'function') {
              var jw = window.jwplayer();
              if (jw && typeof jw.getQualityLevels === 'function') {
                var levels = jw.getQualityLevels();
                if (Array.isArray(levels)) {
                  for (var j = 0; j < levels.length; j++) {
                    var lv = levels[j];
                    var h = lv.height || parseInt(String(lv.label || '').replace(/[^0-9]/g, ''), 10);
                    if (h >= 144) addQ(String(j), h, lv.label || (h + 'p'));
                  }
                }
              }
            }

            // DOM quality menu items
            if (detected.length === 0) {
              var items = document.querySelectorAll('[class*="quality"] li, [class*="quality-item"], [data-quality], [data-resolution]');
              items.forEach(function(el) {
                var txt = (el.textContent || el.getAttribute('data-quality') || el.getAttribute('data-resolution') || '').trim();
                var m = txt.match(/(\\d{3,4})[pP]?/);
                if (m) {
                  var h = parseInt(m[1], 10);
                  if (h >= 144 && h <= 4320) addQ(String(h), h, h + 'p');
                }
              });
            }

            if (detected.length > 0 && window.NobarinWebBridge) {
              window.NobarinWebBridge.postMessage(JSON.stringify({
                event: 'qualities',
                qualities: detected
              }));
            }
          } catch (_) {}
        }

        // Listen to cross-origin player postMessages (e.g., Player.js / Video.js / JW / Vimeo / embed bridges)
        if (!window.__nobarinMsgListenerAdded) {
          window.__nobarinMsgListenerAdded = true;
          window.addEventListener('message', function(e) {
            try {
              var d = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
              if (!d || typeof d !== 'object') return;
              var ev = d.event || d.type || '';
              if (ev === 'timeupdate' || ev === 'time') {
                var ct = d.currentTime ?? d.seconds ?? (d.data && d.data.seconds) ?? (d.value && d.value.seconds);
                var dur = d.duration ?? (d.data && d.data.duration) ?? (d.value && d.value.duration);
                if (typeof ct === 'number' && window.NobarinWebBridge) {
                  window.NobarinWebBridge.postMessage(JSON.stringify({
                    event: 'timeupdate',
                    currentTime: ct,
                    duration: typeof dur === 'number' ? dur : 0
                  }));
                }
              } else if (ev === 'play' || ev === 'playing') {
                if (window.NobarinWebBridge) {
                  window.NobarinWebBridge.postMessage(JSON.stringify({ event: 'play' }));
                }
              } else if (ev === 'pause' || ev === 'paused') {
                if (window.NobarinWebBridge) {
                  window.NobarinWebBridge.postMessage(JSON.stringify({ event: 'pause' }));
                }
              } else if (ev === 'ended' || ev === 'finish') {
                if (window.NobarinWebBridge) {
                  window.NobarinWebBridge.postMessage(JSON.stringify({ event: 'ended' }));
                }
              }
            } catch (_) {}
          });
        }

        setInterval(attachToPrimaryVideo, 700);
        attachToPrimaryVideo();
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
          case 'iframe_detected':
            final iframeSrc = (data['src'] as String?)?.trim() ?? '';
            if (iframeSrc.isNotEmpty) {
              _tryExtractStreamFromIframe(iframeSrc);
            }
            break;
          case 'embed_resolved':
            final embedUrl = (data['embedUrl'] as String?)?.trim() ?? '';
            if (embedUrl.isNotEmpty) {
              _tryExtractStreamFromVerify(embedUrl);
            }
            break;
          case 'direct_stream_resolved':
            final fileUrl = (data['fileUrl'] as String?)?.trim() ?? '';
            if (fileUrl.isNotEmpty) {
              onDirectStreamExtracted?.call(fileUrl);
            }
            break;
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
            final normH = VideoQuality.normalizeResolutionHeight(
              width: w,
              height: h,
            );
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
          case 'play':
            if (!_isPlaying) {
              _isPlaying = true;
              notifyListeners();
              onPlayingChanged?.call(true);
            }
            break;
          case 'pause':
            if (_isFullscreenTransition && _isPlaying) {
              debugPrint(
                '[WebBrowserPlayer] Spurious OS pause ignored during fullscreen transition. Resuming...',
              );
              play();
              break;
            }
            if (_isPlaying) {
              _isPlaying = false;
              notifyListeners();
              onPlayingChanged?.call(false);
            }
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

  Future<void> _tryExtractStreamFromIframe(String iframeSrc) async {
    if (_webViewController == null || _isDisposed) return;
    final gatewayMatch = RegExp(
      r'^(https?://[^/]+)/iframe\d*/([^/?#]+)/([^/?#]+)',
      caseSensitive: false,
    ).firstMatch(iframeSrc);

    if (gatewayMatch != null) {
      final serverHost = gatewayMatch.group(2)!;
      final videoId = gatewayMatch.group(3)!;
      final html = '''
<!DOCTYPE html><html><head><script>
(function() {
  fetch('/api.php', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: 'host=${Uri.encodeQueryComponent(serverHost)}&id=${Uri.encodeQueryComponent(videoId)}'
  })
  .then(function(r) { return r.json(); })
  .then(function(d) {
    if (d && d.embedUrl && window.NobarinWebBridge) {
      window.NobarinWebBridge.postMessage(JSON.stringify({
        event: 'embed_resolved',
        embedUrl: d.embedUrl
      }));
    }
  })
  .catch(function() {});
})();
</script></head><body></body></html>
''';
      await _webViewController!.loadHtmlString(html, baseUrl: iframeSrc);
    } else if (iframeSrc.contains('playcdn.')) {
      await _tryExtractStreamFromVerify(iframeSrc);
    }
  }

  Future<void> _tryExtractStreamFromVerify(String embedUrl) async {
    if (_webViewController == null || _isDisposed) return;
    final embedUri = Uri.tryParse(embedUrl);
    if (embedUri == null) return;
    final segments = embedUri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return;
    final slug = segments.last;
    final html = '''
<!DOCTYPE html><html><head><script>
(function() {
  fetch('/verify/${Uri.encodeComponent(slug)}')
  .then(function(r) { return r.json(); })
  .then(function(d) {
    if (d && d.fileUrl && window.NobarinWebBridge) {
      window.NobarinWebBridge.postMessage(JSON.stringify({
        event: 'direct_stream_resolved',
        fileUrl: d.fileUrl
      }));
    }
  })
  .catch(function() {});
})();
</script></head><body></body></html>
''';
    await _webViewController!.loadHtmlString(html, baseUrl: embedUrl);
  }

  void _updateQualitiesFromBridge(List<dynamic> rawList) {
    final detected = <VideoQuality>[
      const VideoQuality.auto(
        label: 'Auto (Otomatis Web)',
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
            detected.add(
              VideoQuality.webBrowser(
                id: id,
                label: label,
                height: height,
              ),
            );
          }
        }
      }
    }
    detected.sort((a, b) {
      if (a.isAuto) return -1;
      if (b.isAuto) return 1;
      return (b.height ?? 0).compareTo(a.height ?? 0);
    });
    _availableQualities = detected;
    notifyListeners();
    onQualitiesChanged?.call(List.unmodifiable(_availableQualities));
  }

  Future<void> setQuality(String qualityId) async {
    _selectedQuality = _availableQualities.firstWhere(
      (q) => q.id == qualityId,
      orElse: () => VideoQuality.webBrowser(
        id: qualityId,
        label: '${qualityId}p',
      ),
    );
    notifyListeners();
    onQualitySelectedChanged?.call(_selectedQuality!);

    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript('''
          (function(targetId) {
            try {
              if (typeof window.jwplayer === 'function') {
                var jw = window.jwplayer();
                if (jw && typeof jw.setCurrentQuality === 'function') {
                  var idx = targetId === 'auto' ? 0 : parseInt(targetId, 10);
                  if (!isNaN(idx)) {
                    jw.setCurrentQuality(idx);
                    return;
                  }
                }
              }
              var items = document.querySelectorAll('[class*="quality"] li, [class*="quality-item"], [data-quality], [data-resolution]');
              for (var i = 0; i < items.length; i++) {
                var el = items[i];
                var txt = (el.textContent || el.getAttribute('data-quality') || el.getAttribute('data-resolution') || '').toLowerCase();
                if ((targetId === 'auto' && txt.indexOf('auto') !== -1) || txt.indexOf(targetId) !== -1) {
                  el.click();
                  return;
                }
              }
            } catch (_) {}
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
            var v = document.querySelector('video.__nobarin-active-video') || document.querySelector('video');
            if (v) {
              v.play().catch(function() {
                var btn = document.querySelector('[class*="play-btn"], [class*="play-button"], .vjs-big-play-button, .jw-icon-playback, .plyr__control--overlaid');
                if (btn) btn.click();
              });
            } else {
              var btn = document.querySelector('[class*="play-btn"], [class*="play-button"], .vjs-big-play-button, .jw-icon-playback, .plyr__control--overlaid');
              if (btn) btn.click();
            }
            var iframes = document.querySelectorAll('iframe');
            for (var i = 0; i < iframes.length; i++) {
              var ifr = iframes[i];
              try {
                if (ifr.contentDocument) {
                  var iv = ifr.contentDocument.querySelector('video');
                  if (iv) iv.play().catch(function(){});
                }
              } catch (_) {}
              try {
                if (ifr.contentWindow) {
                  ifr.contentWindow.postMessage(JSON.stringify({ context: 'player.js', method: 'play' }), '*');
                  ifr.contentWindow.postMessage(JSON.stringify({ method: 'play' }), '*');
                  ifr.contentWindow.postMessage(JSON.stringify({ event: 'command', func: 'playVideo', args: [] }), '*');
                }
              } catch (_) {}
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
            videos.forEach(function(v) { v.pause(); });
            var iframes = document.querySelectorAll('iframe');
            for (var i = 0; i < iframes.length; i++) {
              var ifr = iframes[i];
              try {
                if (ifr.contentDocument) {
                  var ivs = ifr.contentDocument.querySelectorAll('video');
                  ivs.forEach(function(iv) { iv.pause(); });
                }
              } catch (_) {}
              try {
                if (ifr.contentWindow) {
                  ifr.contentWindow.postMessage(JSON.stringify({ context: 'player.js', method: 'pause' }), '*');
                  ifr.contentWindow.postMessage(JSON.stringify({ method: 'pause' }), '*');
                  ifr.contentWindow.postMessage(JSON.stringify({ event: 'command', func: 'pauseVideo', args: [] }), '*');
                }
              } catch (_) {}
            }
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
        await _webViewController!.runJavaScript('''
          (function() {
            var v = document.querySelector('video.__nobarin-active-video') || document.querySelector('video');
            if (v) v.currentTime = $seconds;
            var iframes = document.querySelectorAll('iframe');
            for (var i = 0; i < iframes.length; i++) {
              var ifr = iframes[i];
              try {
                if (ifr.contentDocument) {
                  var iv = ifr.contentDocument.querySelector('video');
                  if (iv) iv.currentTime = $seconds;
                }
              } catch (_) {}
              try {
                if (ifr.contentWindow) {
                  ifr.contentWindow.postMessage(JSON.stringify({ context: 'player.js', method: 'setCurrentTime', value: $seconds }), '*');
                  ifr.contentWindow.postMessage(JSON.stringify({ method: 'seekTo', value: $seconds }), '*');
                  ifr.contentWindow.postMessage(JSON.stringify({ event: 'command', func: 'seekTo', args: [$seconds, true] }), '*');
                }
              } catch (_) {}
            }
          })();
        ''');
      } catch (_) {}
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    notifyListeners();
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript('''
          (function() {
            var v = document.querySelector('video.__nobarin-active-video') || document.querySelector('video');
            if (v) v.playbackRate = $speed;
            var iframes = document.querySelectorAll('iframe');
            for (var i = 0; i < iframes.length; i++) {
              var ifr = iframes[i];
              try {
                if (ifr.contentDocument) {
                  var iv = ifr.contentDocument.querySelector('video');
                  if (iv) iv.playbackRate = $speed;
                }
              } catch (_) {}
            }
          })();
        ''');
      } catch (_) {}
    }
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    _isMuted = _volume == 0;
    notifyListeners();
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript('''
          (function() {
            var v = document.querySelector('video.__nobarin-active-video') || document.querySelector('video');
            if (v) {
              v.volume = $_volume;
              v.muted = ($_volume === 0);
            }
            var iframes = document.querySelectorAll('iframe');
            for (var i = 0; i < iframes.length; i++) {
              var ifr = iframes[i];
              try {
                if (ifr.contentDocument) {
                  var iv = ifr.contentDocument.querySelector('video');
                  if (iv) {
                    iv.volume = $_volume;
                    iv.muted = ($_volume === 0);
                  }
                }
              } catch (_) {}
            }
          })();
        ''');
      } catch (_) {}
    }
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    notifyListeners();
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript('''
          (function() {
            var v = document.querySelector('video.__nobarin-active-video') || document.querySelector('video');
            if (v) v.muted = !v.muted;
            var iframes = document.querySelectorAll('iframe');
            for (var i = 0; i < iframes.length; i++) {
              var ifr = iframes[i];
              try {
                if (ifr.contentDocument) {
                  var iv = ifr.contentDocument.querySelector('video');
                  if (iv) iv.muted = !iv.muted;
                }
              } catch (_) {}
            }
          })();
        ''');
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
