import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Controller for Bstation / Bilibili player via WebViewController & HTML5 video bridge
class BstationPlayerController extends ChangeNotifier {
  WebViewController? _webViewController;
  String _url = '';
  double _position = 0.0;
  double _duration = 0.0;
  bool _isPlaying = false;
  bool _isMuted = false;
  double _volume = 1.0;
  double _playbackSpeed = 1.0;
  bool _isDisposed = false;

  void Function(double position)? onPositionChanged;
  void Function(double duration)? onDurationChanged;
  void Function(bool isPlaying)? onPlayingChanged;
  void Function()? onPlaybackEnded;
  void Function(String error)? onError;

  WebViewController? get webViewController => _webViewController;
  String get url => _url;
  double get position => _position;
  double get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get isMuted => _isMuted;
  double get volume => _volume;
  double get playbackSpeed => _playbackSpeed;

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
    notifyListeners();

    if (!_isSupportedMobilePlatform) {
      return;
    }

    try {
      final targetUri = _resolveTargetUri(url, autoPlay: autoPlay);

      if (_webViewController == null) {
        final controller = WebViewController()
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

        await controller.loadRequest(targetUri);
        _webViewController = controller;
      } else {
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
          }
        }

        // 3. Continuously eliminate app-download modals, dialogs, and popups
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

  Future<void> play() async {
    _isPlaying = true;
    notifyListeners();
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript(
          "var v = document.querySelector('video'); if (v) v.play();",
        );
      } catch (_) {}
    }
  }

  Future<void> pause() async {
    _isPlaying = false;
    notifyListeners();
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript(
          "var v = document.querySelector('video'); if (v) v.pause();",
        );
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
