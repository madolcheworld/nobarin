import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../models/video_quality.dart';

/// Controller for Dailymotion video player via WebViewController & HTML5 video bridge
class DailymotionPlayerController extends ChangeNotifier {
  WebViewController? _webViewController;
  String _url = '';
  String? _videoId;
  double _position = 0.0;
  double _duration = 0.0;
  bool _isPlaying = false;
  bool _isMuted = false;
  double _volume = 1.0;
  double _playbackSpeed = 1.0;
  bool _isDisposed = false;

  // Video Quality state for Dailymotion
  List<VideoQuality> _availableQualities = [
    const VideoQuality.auto(
      label: 'Auto (Otomatis Dailymotion)',
      mode: QualityControlMode.webviewBridge,
    ),
    VideoQuality.dailymotion('1080'),
    VideoQuality.dailymotion('720'),
    VideoQuality.dailymotion('480'),
    VideoQuality.dailymotion('360'),
    VideoQuality.dailymotion('240'),
  ];
  VideoQuality? _selectedQuality;
  int? _detectedHeight;
  int? _detectedWidth;

  DailymotionPlayerController() {
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
  String? get videoId => _videoId;
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

  /// Extracts Dailymotion video ID from various URL formats
  static String? extractVideoId(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final regex = RegExp(
      r'(?:dailymotion\.com/(?:video/|embed/video/)|dai\.ly/|player\.html\?video=)([a-zA-Z0-9]+)',
      caseSensitive: false,
    );
    final match = regex.firstMatch(trimmed);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }

    // Direct video ID string (e.g. x7tgad0, x84sh87)
    if (RegExp(r'^[a-zA-Z0-9]{4,12}$').hasMatch(trimmed)) {
      return trimmed;
    }

    return null;
  }

  /// Loads Dailymotion media URL and sets up webview & player hooks
  Future<void> loadUrl(
    String url, {
    bool autoPlay = false,
    double startSeconds = 0.0,
  }) async {
    _url = url;
    _videoId = extractVideoId(url);
    _position = startSeconds;
    _isPlaying = autoPlay;
    _selectedQuality = _availableQualities.first;
    _detectedHeight = null;
    _detectedWidth = null;
    notifyListeners();

    if (!_isSupportedMobilePlatform) {
      return;
    }

    try {
      final targetUri = _resolveTargetUri(url, autoPlay: autoPlay, startSeconds: startSeconds);

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
            'NobarDailymotionPlayer',
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
      onError?.call('Gagal menginisialisasi pemutar Dailymotion: $e');
    }
  }

  /// Converts raw URL or video ID to Dailymotion player embed URI
  Uri _resolveTargetUri(
    String rawUrl, {
    required bool autoPlay,
    required double startSeconds,
  }) {
    final vId = _videoId ?? extractVideoId(rawUrl);
    if (vId != null && vId.isNotEmpty) {
      final startTimeParam = startSeconds > 0 ? '&startTime=${startSeconds.round()}' : '';
      return Uri.parse(
        'https://geo.dailymotion.com/player.html?video=$vId&autoplay=${autoPlay ? 1 : 0}&mute=0$startTimeParam',
      );
    }
    return Uri.parse(rawUrl.trim());
  }

  /// Injects CSS and JavaScript to optimize player layout and hook into video events
  Future<void> _injectPlayerOptimizations({
    required bool autoPlay,
    required double startSeconds,
  }) async {
    if (_webViewController == null || _isDisposed) return;

    final script = '''
      (function() {
        // 1. Clean UI and ensure full-screen responsive presentation
        var existingStyle = document.getElementById('nobar-dailymotion-style');
        if (!existingStyle) {
          var style = document.createElement('style');
          style.id = 'nobar-dailymotion-style';
          style.textContent = `
            header, nav, footer, .dmp_Header, .dmp_EndScreen, .dmp_AdBreakBanner {
              display: none !important;
            }
            html, body {
              background-color: #000 !important;
              margin: 0 !important;
              padding: 0 !important;
              overflow: hidden !important;
              width: 100% !important;
              height: 100% !important;
            }
            #player, .player-container, .dmp_Container {
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

        // 2. Attach video bridge
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
              if (window.NobarDailymotionPlayer) {
                window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                  event: 'timeupdate',
                  currentTime: video.currentTime,
                  duration: video.duration || 0
                }));
              }
            });

            video.addEventListener('play', function() {
              if (window.NobarDailymotionPlayer) {
                window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                  event: 'play'
                }));
              }
            });

            video.addEventListener('pause', function() {
              if (window.NobarDailymotionPlayer) {
                window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                  event: 'pause'
                }));
              }
            });

            video.addEventListener('ended', function() {
              if (window.NobarDailymotionPlayer) {
                window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                  event: 'ended'
                }));
              }
            });

            video.addEventListener('durationchange', function() {
              if (window.NobarDailymotionPlayer) {
                window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                  event: 'durationchange',
                  duration: video.duration || 0
                }));
              }
            });

            // 3. Poll Dailymotion Player qualities
            function pollDailymotionQualities() {
              try {
                if (window.player && typeof window.player.getQualities === 'function') {
                  var list = window.player.getQualities();
                  if (Array.isArray(list) && list.length > 0) {
                    window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                      event: 'qualities',
                      qualities: list
                    }));
                  }
                } else if (window.player && window.player.getState) {
                  var state = window.player.getState();
                  if (state && Array.isArray(state.qualities) && state.qualities.length > 0) {
                    window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                      event: 'qualities',
                      qualities: state.qualities
                    }));
                  }
                }
              } catch(e) {}
            }
            // 4. Track video resolution
            function reportDailymotionResolution() {
              if (video && video.videoHeight > 0) {
                if (video.__nobarLastH !== video.videoHeight || video.__nobarLastW !== video.videoWidth) {
                  video.__nobarLastH = video.videoHeight;
                  video.__nobarLastW = video.videoWidth;
                  if (window.NobarDailymotionPlayer) {
                    window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                      event: 'resolution',
                      height: video.videoHeight,
                      width: video.videoWidth
                    }));
                  }
                }
              }
            }
            video.addEventListener('loadedmetadata', reportDailymotionResolution);
            video.addEventListener('resize', reportDailymotionResolution);
            setInterval(reportDailymotionResolution, 1000);
            reportDailymotionResolution();
          }
        }

        setInterval(setupVideoBridge, 600);
        setupVideoBridge();
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
            if (h != null && h > 0 && h != _detectedHeight) {
              _detectedHeight = h;
              _detectedWidth = w;
              notifyListeners();
            }
            break;
          case 'qualities':
            final rawList = data['qualities'];
            if (rawList is List) {
              _updateQualitiesFromBridge(rawList);
            }
            break;
          case 'qualitychange':
            final curQ = data['quality']?.toString();
            if (curQ != null) {
              _selectedQuality = _availableQualities.firstWhere(
                (q) => q.id == curQ,
                orElse: () => VideoQuality.dailymotion(curQ),
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

  void _updateQualitiesFromBridge(List<dynamic> list) {
    final List<VideoQuality> qualities = [
      const VideoQuality.auto(
        label: 'Auto (Otomatis Dailymotion)',
        mode: QualityControlMode.webviewBridge,
      ),
    ];
    final Set<String> seen = {'auto'};

    for (final item in list) {
      if (item is Map) {
        final id = item['id']?.toString() ?? item['quality']?.toString() ?? '';
        final str = id.trim().toLowerCase();
        if (str.isEmpty || seen.contains(str) || str == 'auto') continue;
        seen.add(str);
        qualities.add(VideoQuality.dailymotion(str));
      } else {
        final str = item.toString().trim().toLowerCase();
        if (str.isEmpty || seen.contains(str) || str == 'auto') continue;
        seen.add(str);
        qualities.add(VideoQuality.dailymotion(str));
      }
    }

    // Sort descending by height
    qualities.sort((a, b) {
      if (a.isAuto) return -1;
      if (b.isAuto) return 1;
      return (b.height ?? 0).compareTo(a.height ?? 0);
    });

    _availableQualities = qualities;
    notifyListeners();
    onQualitiesChanged?.call(_availableQualities);
  }

  @visibleForTesting
  void handleBridgeMessageForTesting(String rawJson) => _handlePlayerBridgeMessage(rawJson);

  /// Sets video quality for Dailymotion player
  Future<void> setQuality(String qualityId) async {
    _selectedQuality = _availableQualities.firstWhere(
      (q) => q.id == qualityId,
      orElse: () => VideoQuality.dailymotion(qualityId),
    );
    notifyListeners();
    onQualitySelectedChanged?.call(_selectedQuality!);

    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript('''
          (function(targetId) {
            try {
              // 1. Try Dailymotion Player API
              if (window.player) {
                if (typeof window.player.setQuality === 'function') {
                  window.player.setQuality(targetId);
                  return;
                }
                if (typeof window.player.setPlaybackQuality === 'function') {
                  window.player.setPlaybackQuality(targetId);
                  return;
                }
              }

              // 2. Try window.postMessage for embedded player
              window.postMessage(JSON.stringify({ command: 'setQuality', value: targetId }), '*');

              // 3. Check quality buttons in player DOM
              var selectors = [
                '.dmp_QualityItem',
                '[class*="quality-item"]',
                '[class*="quality_item"]',
                '[data-quality]'
              ];
              var items = document.querySelectorAll(selectors.join(','));
              for (var i = 0; i < items.length; i++) {
                var el = items[i];
                var val = (el.getAttribute('data-quality') || el.textContent || '').toLowerCase().trim();
                if (val === targetId || val.indexOf(targetId) !== -1) {
                  el.click();
                  return;
                }
              }
            } catch(e) {}
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
                    console.log('[Nobarin Dailymotion] play error:', e);
                    try {
                      if (window.player && typeof window.player.play === 'function') {
                        window.player.play();
                      }
                    } catch (_) {}
                  });
                }
              });
            } else {
              try {
                if (window.player && typeof window.player.play === 'function') {
                  window.player.play();
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
            videos.forEach(function(v) {
              v.pause();
            });
            try {
              if (window.player && typeof window.player.pause === 'function') {
                window.player.pause();
              }
            } catch (_) {}
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
