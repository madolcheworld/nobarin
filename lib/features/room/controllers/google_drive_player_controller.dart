import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../models/video_quality.dart';

/// Controller for Google Drive video player via WebViewController & HTML5 video bridge
class GoogleDrivePlayerController extends ChangeNotifier {
  final GlobalKey webViewKey = GlobalKey(debugLabel: 'GoogleDriveWebView');
  WebViewController? _webViewController;
  String _url = '';
  String? _fileId;
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

  // Video Quality state for Google Drive (populated dynamically from embedded player postMessage)
  List<VideoQuality> _availableQualities = [
    const VideoQuality.auto(
      label: 'Auto (Otomatis Google Drive)',
      mode: QualityControlMode.webviewBridge,
    ),
  ];
  VideoQuality? _selectedQuality;
  int? _detectedHeight;
  int? _detectedWidth;

  GoogleDrivePlayerController() {
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
  String? get fileId => _fileId;
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

  /// Extracts Google Drive File ID from various URL patterns
  static String? extractFileId(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    // Pattern 1: /file/d/{FILE_ID}
    final fileMatch = RegExp(
      r'drive\.google\.com/file/d/([a-zA-Z0-9_-]{20,})',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (fileMatch != null && fileMatch.groupCount >= 1) {
      return fileMatch.group(1);
    }

    // Pattern 2: [?&]id={FILE_ID} (e.g. uc?id=... or open?id=...)
    final idParamMatch = RegExp(
      r'[?&]id=([a-zA-Z0-9_-]{20,})',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (idParamMatch != null && idParamMatch.groupCount >= 1) {
      return idParamMatch.group(1);
    }

    // Pattern 3: [?&]preview={FILE_ID}
    final previewParamMatch = RegExp(
      r'[?&]preview=([a-zA-Z0-9_-]{20,})',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (previewParamMatch != null && previewParamMatch.groupCount >= 1) {
      return previewParamMatch.group(1);
    }

    // Pattern 4: /d/{FILE_ID}
    final dMatch = RegExp(
      r'/d/([a-zA-Z0-9_-]{20,})',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (dMatch != null && dMatch.groupCount >= 1) {
      return dMatch.group(1);
    }

    // Pattern 5: Raw File ID token (Google Drive IDs are usually 28-44 chars alphanumeric with _ or -)
    if (RegExp(r'^[a-zA-Z0-9_-]{25,50}$').hasMatch(trimmed)) {
      return trimmed;
    }

    return null;
  }

  /// Converts raw URL or File ID to Google Drive preview embed URI
  static Uri resolvePreviewUri(String rawUrl) {
    final fId = extractFileId(rawUrl);
    if (fId != null && fId.isNotEmpty) {
      return Uri.parse('https://drive.google.com/file/d/$fId/preview');
    }
    return Uri.parse(rawUrl.trim());
  }

  /// Loads Google Drive video URL and sets up webview & player hooks
  Future<void> loadUrl(
    String url, {
    bool autoPlay = false,
    double startSeconds = 0.0,
  }) async {
    _url = url;
    _fileId = extractFileId(url);
    _position = startSeconds;
    _isPlaying = autoPlay;
    _availableQualities = [
      const VideoQuality.auto(
        label: 'Auto (Otomatis Google Drive)',
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
          'Google Drive player hanya didukung pada platform Android & iOS. Silakan gunakan sumber YouTube atau Direct Video.',
        );
      }
      return;
    }

    try {
      final targetUri = resolvePreviewUri(url);

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
              onProgress: (progress) {
                if (progress >= 75) {
                  _injectPlayerOptimizations(
                    autoPlay: _isPlaying,
                    startSeconds: _position,
                  );
                }
              },
              onPageFinished: (finishedUrl) {
                _injectPlayerOptimizations(
                  autoPlay: _isPlaying,
                  startSeconds: _position,
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
                if (error.isForMainFrame ?? true) {
                  onError?.call(error.description);
                }
              },
            ),
          )
          ..addJavaScriptChannel(
            'NobarGdrivePlayer',
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
      onError?.call('Gagal menginisialisasi pemutar Google Drive: $e');
    }
  }

  /// Injects CSS and JavaScript to optimize player layout and hook into Google Drive's
  /// embedded YouTube iframe player, native slider/buttons, and fallback HTML5 video.
  Future<void> _injectPlayerOptimizations({
    required bool autoPlay,
    required double startSeconds,
  }) async {
    if (_webViewController == null || _isDisposed) return;

    final script = '''
      (function() {
        // 1. Hide extraneous Google Drive chrome & native controls so Nobarin controls take over cleanly
        var existingStyle = document.getElementById('nobar-gdrive-style');
        if (!existingStyle && document.head) {
          var style = document.createElement('style');
          style.id = 'nobar-gdrive-style';
          style.textContent = `
            header, nav, footer,
            .drive-viewer-toolstrip,
            .drive-viewer-popout-button,
            .drive-viewer-download-button,
            .ndfHFb-c4YZDc-Wrql6b,
            .ndfHFb-c4YZDc-to91Fb,
            .ndfHFb-c4YZDc-nJjxad,
            .ndfHFb-c4YZDc-J3e2ec,
            .drive-viewer-action-bar,
            [class*="drive-viewer-toolstrip"],
            [class*="popout-button"],
            [class*="download-button"],
            section[jsname="UczJL"],
            div[jsname="I28g6d"],
            button[jsname="dW8tsb"],
            .hPHUXe,
            .VUN2V,
            .E6snnb {
              opacity: 0 !important;
              pointer-events: none !important;
              visibility: hidden !important;
            }
            html, body {
              background-color: #000 !important;
              margin: 0 !important;
              padding: 0 !important;
              overflow: hidden !important;
              width: 100% !important;
              height: 100% !important;
            }
            .drive-viewer-video-player, #player, .player-container, .html5-video-player, .xpiQs, div[jsname="aTv5jf"] {
              width: 100vw !important;
              height: 100vh !important;
              position: fixed !important;
              top: 0 !important;
              left: 0 !important;
              z-index: 99999 !important;
              margin: 0 !important;
              padding: 0 !important;
              background: #000 !important;
            }
            iframe {
              width: 100vw !important;
              height: 100vh !important;
              border: none !important;
              display: block !important;
              pointer-events: none !important;
            }
            video {
              width: 100% !important;
              height: 100% !important;
              object-fit: contain !important;
            }
          `;
          document.head.appendChild(style);
        }

        // 2. Define unified command dispatcher for Google Drive's embedded iframe + HTML5 video
        window.__nobarGDControl = function(cmd, arg1) {
          var iframes = document.querySelectorAll('iframe');
          function sendToIframes(fn, args) {
            for (var i = 0; i < iframes.length; i++) {
              try {
                iframes[i].contentWindow.postMessage(JSON.stringify({
                  event: 'command',
                  func: fn,
                  args: args || []
                }), '*');
              } catch (_) {}
            }
          }

          var v = document.querySelector('video');

          if (cmd === 'play') {
            sendToIframes('playVideo', []);
            if (v) { v.play().catch(function(){}); }
          } else if (cmd === 'pause') {
            sendToIframes('pauseVideo', []);
            if (v) { v.pause(); }
          } else if (cmd === 'seekTo') {
            var sec = Number(arg1) || 0;
            sendToIframes('seekTo', [sec, true]);
            if (v) { v.currentTime = sec; }
          } else if (cmd === 'setVolume') {
            var vol = Math.max(0, Math.min(1, Number(arg1) || 0));
            sendToIframes('setVolume', [Math.round(vol * 100)]);
            if (v) { v.volume = vol; }
          } else if (cmd === 'mute') {
            sendToIframes('mute', []);
            if (v) { v.muted = true; }
          } else if (cmd === 'unMute') {
            sendToIframes('unMute', []);
            if (v) { v.muted = false; }
          } else if (cmd === 'setPlaybackRate') {
            var rate = Number(arg1) || 1.0;
            sendToIframes('setPlaybackRate', [rate]);
            if (v) { v.playbackRate = rate; }
          } else if (cmd === 'setQuality') {
            var qCode = String(arg1 || 'default');
            sendToIframes('setPlaybackQuality', [qCode]);
            sendToIframes('setPlaybackQualityRange', [qCode, qCode]);
          }
        };

        // 3. Store initial desired states only once per page load
        if (!window.__nobarStateInit) {
          window.__nobarStateInit = true;
          window.__nobarDesiredPlaying = ${autoPlay ? 'true' : 'false'};
          window.__nobarPlayRetries = ${autoPlay ? '24' : '0'};
          window.__nobarPendingStartSec = $startSeconds;
          window.__nobarActualPlaying = false;
          window.__nobarDuration = 0;
        }

        // 4. Listen to postMessage events emitted by Google Drive's embedded YouTube player
        if (!window.__nobarMsgListenerAttached) {
          window.__nobarMsgListenerAttached = true;
          window.addEventListener('message', function(e) {
            try {
              var data = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
              if (!data) return;

              if (data.event === 'infoDelivery' && data.info) {
                var info = data.info;
                var curTime = info.currentTime != null
                  ? info.currentTime
                  : (info.progressState && info.progressState.current);
                var dur = info.duration != null
                  ? info.duration
                  : (info.progressState && info.progressState.duration);
                var pState = info.playerState;

                if (dur != null && dur > 0) {
                  window.__nobarDuration = dur;
                }

                if (Array.isArray(info.availableQualityLevels) && info.availableQualityLevels.length > 0 && window.NobarGdrivePlayer) {
                  window.NobarGdrivePlayer.postMessage(JSON.stringify({
                    event: 'qualities',
                    qualities: info.availableQualityLevels
                  }));
                }

                if (info.playbackQuality && typeof info.playbackQuality === 'string' && window.NobarGdrivePlayer) {
                  window.NobarGdrivePlayer.postMessage(JSON.stringify({
                    event: 'qualitychange',
                    quality: info.playbackQuality
                  }));
                }

                if (curTime != null && window.NobarGdrivePlayer) {
                  window.NobarGdrivePlayer.postMessage(JSON.stringify({
                    event: 'timeupdate',
                    currentTime: curTime,
                    duration: window.__nobarDuration || 0
                  }));
                }

                if (pState != null && window.NobarGdrivePlayer) {
                  if (pState === 1) {
                    window.__nobarActualPlaying = true;
                    window.__nobarPlayRetries = 0;
                    window.NobarGdrivePlayer.postMessage(JSON.stringify({ event: 'play' }));
                  } else if (pState === 2) {
                    window.__nobarActualPlaying = false;
                    window.NobarGdrivePlayer.postMessage(JSON.stringify({ event: 'pause' }));
                  } else if (pState === 0) {
                    window.__nobarActualPlaying = false;
                    window.__nobarDesiredPlaying = false;
                    window.NobarGdrivePlayer.postMessage(JSON.stringify({ event: 'ended' }));
                  }
                }
              } else if (data.event === 'onPlaybackQualityChange' && typeof data.info === 'string') {
                if (window.NobarGdrivePlayer) {
                  window.NobarGdrivePlayer.postMessage(JSON.stringify({
                    event: 'qualitychange',
                    quality: data.info
                  }));
                }
              } else if (data.event === 'onVideoProgress' && typeof data.info === 'number') {
                if (window.NobarGdrivePlayer) {
                  window.NobarGdrivePlayer.postMessage(JSON.stringify({
                    event: 'timeupdate',
                    currentTime: data.info,
                    duration: window.__nobarDuration || 0
                  }));
                }
              } else if (data.event === 'onStateChange' && typeof data.info === 'number') {
                if (window.NobarGdrivePlayer) {
                  if (data.info === 1) {
                    window.__nobarActualPlaying = true;
                    window.__nobarPlayRetries = 0;
                    window.NobarGdrivePlayer.postMessage(JSON.stringify({ event: 'play' }));
                  } else if (data.info === 2) {
                    window.__nobarActualPlaying = false;
                    window.NobarGdrivePlayer.postMessage(JSON.stringify({ event: 'pause' }));
                  } else if (data.info === 0) {
                    window.__nobarActualPlaying = false;
                    window.__nobarDesiredPlaying = false;
                    window.NobarGdrivePlayer.postMessage(JSON.stringify({ event: 'ended' }));
                  }
                }
              }
            } catch (_) {}
          });
        }

        // 5. Attach direct HTML5 <video> listeners if a <video> element exists
        function setupVideoBridge() {
          var video = document.querySelector('video');
          if (!video || video.__nobarAttached) return;
          video.__nobarAttached = true;

          if (window.__nobarPendingStartSec > 0) {
            video.currentTime = window.__nobarPendingStartSec;
            window.__nobarPendingStartSec = 0;
          }
          video.volume = $_volume;
          video.muted = ${_isMuted ? 'true' : 'false'};
          if (window.__nobarDesiredPlaying) {
            video.play().catch(function(){});
          }

          function reportGdriveResolution() {
            if (video && video.videoHeight > 0 && window.NobarGdrivePlayer) {
              if (video.__nobarLastH !== video.videoHeight || video.__nobarLastW !== video.videoWidth) {
                video.__nobarLastH = video.videoHeight;
                video.__nobarLastW = video.videoWidth;
                window.NobarGdrivePlayer.postMessage(JSON.stringify({
                  event: 'resolution',
                  height: video.videoHeight,
                  width: video.videoWidth
                }));
              }
            }
          }
          video.addEventListener('loadedmetadata', reportGdriveResolution);
          video.addEventListener('resize', reportGdriveResolution);

          video.addEventListener('timeupdate', function() {
            if (window.NobarGdrivePlayer) {
              window.NobarGdrivePlayer.postMessage(JSON.stringify({
                event: 'timeupdate',
                currentTime: video.currentTime,
                duration: video.duration || 0
              }));
            }
          });
          video.addEventListener('play', function() {
            window.__nobarActualPlaying = true;
            if (window.NobarGdrivePlayer) {
              window.NobarGdrivePlayer.postMessage(JSON.stringify({ event: 'play' }));
            }
          });
          video.addEventListener('pause', function() {
            window.__nobarActualPlaying = false;
            if (window.NobarGdrivePlayer) {
              window.NobarGdrivePlayer.postMessage(JSON.stringify({ event: 'pause' }));
            }
          });
          video.addEventListener('ended', function() {
            window.__nobarActualPlaying = false;
            window.__nobarDesiredPlaying = false;
            if (window.NobarGdrivePlayer) {
              window.NobarGdrivePlayer.postMessage(JSON.stringify({ event: 'ended' }));
            }
          });
          video.addEventListener('durationchange', function() {
            if (window.NobarGdrivePlayer) {
              window.NobarGdrivePlayer.postMessage(JSON.stringify({
                event: 'durationchange',
                duration: video.duration || 0
              }));
            }
          });
        }

        function configureYoutubeIframe() {
          var ytIframe = document.querySelector('iframe#ucc-2, iframe[src*="youtube"]');
          if (!ytIframe || !ytIframe.src) return false;
          if (!ytIframe.src.includes('controls=0')) {
            ytIframe.src = ytIframe.src + '&controls=0&modestbranding=1&rel=0&showinfo=0&iv_load_policy=3';
            return false;
          }
          return true;
        }

        setupVideoBridge();
        configureYoutubeIframe();

        // 6. Periodic sync ticker (every 300ms) to poll Drive slider & handle deferred start/play
        if (!window.__nobarTickerAttached) {
          window.__nobarTickerAttached = true;
          setInterval(function() {
            setupVideoBridge();
            var iframeReady = configureYoutubeIframe();

            var slider = document.querySelector('input.EdShgc-YCNiv');
            if (slider) {
              var rawMax = parseFloat(slider.max) || 0;
              var rawVal = parseFloat(slider.value) || 0;
              var durSec = rawMax / 1000.0;
              var posSec = rawVal / 1000.0;

              if (durSec > 0 && Math.abs(durSec - (window.__nobarDuration || 0)) >= 0.5) {
                window.__nobarDuration = durSec;
                if (window.NobarGdrivePlayer) {
                  window.NobarGdrivePlayer.postMessage(JSON.stringify({
                    event: 'durationchange',
                    duration: durSec
                  }));
                }
              }

              // Apply deferred initial seek once player duration is ready
              if (durSec > 0 && window.__nobarPendingStartSec > 0) {
                var targetSec = window.__nobarPendingStartSec;
                window.__nobarPendingStartSec = 0;
                window.__nobarGDControl('seekTo', targetSec);
              }

              if (window.__nobarActualPlaying && durSec > 0 && window.NobarGdrivePlayer) {
                window.NobarGdrivePlayer.postMessage(JSON.stringify({
                  event: 'timeupdate',
                  currentTime: posSec,
                  duration: durSec
                }));
              }
            }

            // Retry play if requested before iframe player finished mounting
            if (window.__nobarDesiredPlaying && !window.__nobarActualPlaying && window.__nobarPlayRetries > 0) {
              if (iframeReady) {
                window.__nobarPlayRetries--;
                window.__nobarGDControl('play');
              }
            }
          }, 300);
        }
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
      if (data is! Map<String, dynamic>) return;

      final event = data['event'] as String?;
      switch (event) {
        case 'timeupdate':
          final pos = (data['currentTime'] as num?)?.toDouble() ?? 0.0;
          final dur = (data['duration'] as num?)?.toDouble() ?? 0.0;
          bool changed = false;
          if (dur > 0 && (dur - _duration).abs() >= 0.5) {
            _duration = dur;
            changed = true;
            onDurationChanged?.call(_duration);
          }
          if ((pos - _position).abs() >= 0.25) {
            _position = pos;
            changed = true;
            onPositionChanged?.call(_position);
          }
          if (changed) {
            notifyListeners();
          }
          break;

        case 'durationchange':
          final dur = (data['duration'] as num?)?.toDouble() ?? 0.0;
          if (dur > 0 && (dur - _duration).abs() >= 0.5) {
            _duration = dur;
            notifyListeners();
            onDurationChanged?.call(_duration);
          }
          break;

        case 'resolution':
          final rawH = (data['height'] as num?)?.toInt();
          final rawW = (data['width'] as num?)?.toInt();
          final normH = VideoQuality.normalizeResolutionHeight(
                width: rawW,
                height: rawH,
              ) ??
              rawH;
          if (normH != null && normH > 0 && normH != _detectedHeight) {
            _detectedHeight = normH;
            _detectedWidth = rawW;
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
          final curQ = data['quality']?.toString().trim();
          if (curQ != null && curQ.isNotEmpty) {
            final parsed = VideoQuality.youtube(curQ);
            if (parsed.height != null && parsed.height! > 0) {
              _detectedHeight = parsed.height;
              notifyListeners();
            }
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
            // Ignore temporary pauses triggered during fullscreen transition
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
          onPlayingChanged?.call(false);
          onPlaybackEnded?.call();
          break;
      }
    } catch (_) {}
  }

  void _updateQualitiesFromBridge(List<dynamic> rawList) {
    final List<VideoQuality> qualities = [
      const VideoQuality.auto(
        label: 'Auto (Otomatis Google Drive)',
        mode: QualityControlMode.webviewBridge,
      ),
    ];
    final Set<String> seen = {'auto'};

    for (final item in rawList) {
      final code = item.toString().trim().toLowerCase();
      if (code.isEmpty || code == 'auto' || seen.contains(code)) continue;
      final q = VideoQuality.youtube(code);
      if (q.height != null && q.height! > 0) {
        seen.add(q.id);
        qualities.add(
          VideoQuality(
            id: q.id,
            label: q.label,
            height: q.height,
            mode: QualityControlMode.webviewBridge,
          ),
        );
      }
    }

    qualities.sort((a, b) {
      if (a.isAuto) return -1;
      if (b.isAuto) return 1;
      return (b.height ?? 0).compareTo(a.height ?? 0);
    });

    _availableQualities = qualities;
    notifyListeners();
    onQualitiesChanged?.call(List.unmodifiable(_availableQualities));
  }

  @visibleForTesting
  void handleBridgeMessageForTesting(String rawJson) =>
      _handlePlayerBridgeMessage(rawJson);

  /// Sets video quality for Google Drive embedded player
  Future<void> setQuality(String qualityId) async {
    _selectedQuality = _availableQualities.firstWhere(
      (q) => q.id == qualityId,
      orElse: () {
        final yt = VideoQuality.youtube(qualityId);
        return VideoQuality(
          id: yt.id,
          label: yt.label,
          height: yt.height,
          mode: QualityControlMode.webviewBridge,
        );
      },
    );
    notifyListeners();
    onQualitySelectedChanged?.call(_selectedQuality!);

    if (_webViewController != null && !_isDisposed) {
      final qCode = (_selectedQuality?.isAuto ?? true) ? 'default' : qualityId;
      try {
        await _webViewController!.runJavaScript('''
          if (window.__nobarGDControl) {
            window.__nobarGDControl('setQuality', '$qCode');
          } else {
            var iframes = document.querySelectorAll('iframe');
            for (var i = 0; i < iframes.length; i++) {
              try {
                iframes[i].contentWindow.postMessage(JSON.stringify({event: 'command', func: 'setPlaybackQuality', args: ['$qCode']}), '*');
                iframes[i].contentWindow.postMessage(JSON.stringify({event: 'command', func: 'setPlaybackQualityRange', args: ['$qCode', '$qCode']}), '*');
              } catch (_) {}
            }
          }
        ''');
      } catch (_) {}
    }
  }

  /// Sends play command to the embedded Google Drive player
  Future<void> play() async {
    _isPlaying = true;
    notifyListeners();
    if (_webViewController != null && !_isDisposed) {
      await _webViewController!.runJavaScript('''
        window.__nobarDesiredPlaying = true;
        window.__nobarPlayRetries = 15;
        if (window.__nobarGDControl) {
          window.__nobarGDControl('play');
        } else {
          var iframes = document.querySelectorAll('iframe');
          for (var i = 0; i < iframes.length; i++) {
            try {
              iframes[i].contentWindow.postMessage(JSON.stringify({event: 'command', func: 'playVideo', args: []}), '*');
            } catch (_) {}
          }
          var v = document.querySelector('video');
          if (v) { v.play().catch(function(){}); }
        }
      ''');
    }
  }

  /// Sends pause command to the embedded Google Drive player
  Future<void> pause() async {
    _isPlaying = false;
    notifyListeners();
    if (_webViewController != null && !_isDisposed) {
      await _webViewController!.runJavaScript('''
        window.__nobarDesiredPlaying = false;
        window.__nobarPlayRetries = 0;
        if (window.__nobarGDControl) {
          window.__nobarGDControl('pause');
        } else {
          var iframes = document.querySelectorAll('iframe');
          for (var i = 0; i < iframes.length; i++) {
            try {
              iframes[i].contentWindow.postMessage(JSON.stringify({event: 'command', func: 'pauseVideo', args: []}), '*');
            } catch (_) {}
          }
          var v = document.querySelector('video');
          if (v) { v.pause(); }
        }
      ''');
    }
  }

  /// Seeks to specified position in seconds
  Future<void> seekTo(double seconds) async {
    _position = seconds;
    notifyListeners();
    if (_webViewController != null && !_isDisposed) {
      await _webViewController!.runJavaScript('''
        if (window.__nobarGDControl) {
          window.__nobarGDControl('seekTo', $seconds);
        } else {
          var iframes = document.querySelectorAll('iframe');
          for (var i = 0; i < iframes.length; i++) {
            try {
              iframes[i].contentWindow.postMessage(JSON.stringify({event: 'command', func: 'seekTo', args: [$seconds, true]}), '*');
            } catch (_) {}
          }
          var v = document.querySelector('video');
          if (v) { v.currentTime = $seconds; }
        }
      ''');
    }
  }

  /// Sets audio volume [0.0 - 1.0]
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    _isMuted = _volume == 0.0;
    notifyListeners();
    if (_webViewController != null && !_isDisposed) {
      final volPercent = (_volume * 100).round();
      await _webViewController!.runJavaScript('''
        if (window.__nobarGDControl) {
          window.__nobarGDControl('${_isMuted ? "mute" : "unMute"}');
          window.__nobarGDControl('setVolume', $_volume);
        } else {
          var iframes = document.querySelectorAll('iframe');
          for (var i = 0; i < iframes.length; i++) {
            try {
              iframes[i].contentWindow.postMessage(JSON.stringify({event: 'command', func: '${_isMuted ? "mute" : "unMute"}', args: []}), '*');
              iframes[i].contentWindow.postMessage(JSON.stringify({event: 'command', func: 'setVolume', args: [$volPercent]}), '*');
            } catch (_) {}
          }
          var v = document.querySelector('video');
          if (v) { v.volume = $_volume; v.muted = ${_isMuted ? "true" : "false"}; }
        }
      ''');
    }
  }

  /// Mutes audio
  Future<void> mute() async {
    _isMuted = true;
    notifyListeners();
    if (_webViewController != null && !_isDisposed) {
      await _webViewController!.runJavaScript('''
        if (window.__nobarGDControl) {
          window.__nobarGDControl('mute');
        } else {
          var iframes = document.querySelectorAll('iframe');
          for (var i = 0; i < iframes.length; i++) {
            try {
              iframes[i].contentWindow.postMessage(JSON.stringify({event: 'command', func: 'mute', args: []}), '*');
            } catch (_) {}
          }
          var v = document.querySelector('video');
          if (v) { v.muted = true; }
        }
      ''');
    }
  }

  /// Unmutes audio
  Future<void> unmute() async {
    _isMuted = false;
    notifyListeners();
    if (_webViewController != null && !_isDisposed) {
      final volPercent = (_volume * 100).round();
      await _webViewController!.runJavaScript('''
        if (window.__nobarGDControl) {
          window.__nobarGDControl('unMute');
          window.__nobarGDControl('setVolume', $_volume);
        } else {
          var iframes = document.querySelectorAll('iframe');
          for (var i = 0; i < iframes.length; i++) {
            try {
              iframes[i].contentWindow.postMessage(JSON.stringify({event: 'command', func: 'unMute', args: []}), '*');
              iframes[i].contentWindow.postMessage(JSON.stringify({event: 'command', func: 'setVolume', args: [$volPercent]}), '*');
            } catch (_) {}
          }
          var v = document.querySelector('video');
          if (v) { v.muted = false; v.volume = $_volume; }
        }
      ''');
    }
  }

  /// Sets playback speed rate
  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    notifyListeners();
    if (_webViewController != null && !_isDisposed) {
      await _webViewController!.runJavaScript('''
        if (window.__nobarGDControl) {
          window.__nobarGDControl('setPlaybackRate', $speed);
        } else {
          var iframes = document.querySelectorAll('iframe');
          for (var i = 0; i < iframes.length; i++) {
            try {
              iframes[i].contentWindow.postMessage(JSON.stringify({event: 'command', func: 'setPlaybackRate', args: [$speed]}), '*');
            } catch (_) {}
          }
          var v = document.querySelector('video');
          if (v) { v.playbackRate = $speed; }
        }
      ''');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _webViewController = null;
    super.dispose();
  }
}
