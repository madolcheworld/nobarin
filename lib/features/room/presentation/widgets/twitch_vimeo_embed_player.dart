import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../../../core/constants/app_colors.dart';
import '../../controllers/unified_player_controller.dart';

/// Embedded player widget supporting Twitch and Vimeo media sources.
/// Utilizes [WebViewController] and [WebViewWidget] on Android/iOS,
/// with an informative placeholder/fallback on Desktop and Web.
class TwitchVimeoEmbedPlayer extends StatefulWidget {
  final UnifiedPlayerController player;
  final bool isPipMode;

  const TwitchVimeoEmbedPlayer({
    super.key,
    required this.player,
    this.isPipMode = false,
  });

  @override
  State<TwitchVimeoEmbedPlayer> createState() => _TwitchVimeoEmbedPlayerState();
}

class _TwitchVimeoEmbedPlayerState extends State<TwitchVimeoEmbedPlayer> {
  WebViewController? _webViewController;
  bool _isLoading = true;
  String _currentLoadedUrl = '';

  bool get _isTwitch => widget.player.mediaType == 'twitch';
  bool get _isVimeo => widget.player.mediaType == 'vimeo';
  bool get _isGoogleDrive => widget.player.mediaType == 'google_drive';
  bool get _isDailymotion => widget.player.mediaType == 'dailymotion';
  bool get _isBstation =>
      widget.player.mediaType == 'bstation' ||
      widget.player.mediaType == 'bilibili';

  bool get _isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _setupControllerListeners();
    if (_isSupportedPlatform) {
      _initWebViewController();
    } else {
      _isLoading = false;
    }
  }

  @override
  void didUpdateWidget(TwitchVimeoEmbedPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      _setupControllerListeners();
    }
    if (widget.player.mediaUrl != _currentLoadedUrl) {
      _loadContent();
    }
  }

  @override
  void dispose() {
    widget.player.onEmbedPlayerCommand = null;
    super.dispose();
  }

  void _setupControllerListeners() {
    widget.player.onEmbedPlayerCommand = (action, arg) {
      if (!mounted || _webViewController == null) return;
      _handlePlayerCommand(action, arg);
    };
  }

  void _handlePlayerCommand(String action, dynamic arg) {
    if (_webViewController == null) return;

    try {
      if (_isVimeo) {
        switch (action) {
          case 'play':
            _webViewController!.runJavaScript(
              'try { const f = document.querySelector("iframe"); if(f) f.contentWindow.postMessage("{\\"method\\":\\"play\\"}", "*"); } catch(e){}',
            );
            break;
          case 'pause':
            _webViewController!.runJavaScript(
              'try { const f = document.querySelector("iframe"); if(f) f.contentWindow.postMessage("{\\"method\\":\\"pause\\"}", "*"); } catch(e){}',
            );
            break;
          case 'seek':
            if (arg is num) {
              _webViewController!.runJavaScript(
                'try { const f = document.querySelector("iframe"); if(f) f.contentWindow.postMessage(JSON.stringify({method:"setCurrentTime", value: $arg}), "*"); } catch(e){}',
              );
            }
            break;
          case 'setMuted':
            final bool muted = arg == true;
            _webViewController!.runJavaScript(
              'try { const f = document.querySelector("iframe"); if(f) f.contentWindow.postMessage(JSON.stringify({method:"setVolume", value: ${muted ? 0 : 1}}), "*"); } catch(e){}',
            );
            break;
        }
      } else if (_isTwitch) {
        switch (action) {
          case 'play':
            _webViewController!.runJavaScript(
              'try { const f = document.querySelector("iframe"); if(f) f.contentWindow.postMessage("{\\"event\\":\\"play\\"}", "*"); } catch(e){}',
            );
            break;
          case 'pause':
            _webViewController!.runJavaScript(
              'try { const f = document.querySelector("iframe"); if(f) f.contentWindow.postMessage("{\\"event\\":\\"pause\\"}", "*"); } catch(e){}',
            );
            break;
          case 'setMuted':
            final bool muted = arg == true;
            _webViewController!.runJavaScript(
              'try { const f = document.querySelector("iframe"); if(f) f.contentWindow.postMessage(JSON.stringify({event:"setMuted", value: $muted}), "*"); } catch(e){}',
            );
            break;
        }
      } else if (_isDailymotion) {
        switch (action) {
          case 'play':
            _webViewController!.runJavaScript(
              'try { const f = document.querySelector("iframe"); if(f) f.contentWindow.postMessage(JSON.stringify({command:"play"}), "*"); } catch(e){}',
            );
            break;
          case 'pause':
            _webViewController!.runJavaScript(
              'try { const f = document.querySelector("iframe"); if(f) f.contentWindow.postMessage(JSON.stringify({command:"pause"}), "*"); } catch(e){}',
            );
            break;
          case 'seek':
            if (arg is num) {
              _webViewController!.runJavaScript(
                'try { const f = document.querySelector("iframe"); if(f) f.contentWindow.postMessage(JSON.stringify({command:"seek", parameters: [$arg]}), "*"); } catch(e){}',
              );
            }
            break;
          case 'setMuted':
            final bool muted = arg == true;
            _webViewController!.runJavaScript(
              'try { const f = document.querySelector("iframe"); if(f) f.contentWindow.postMessage(JSON.stringify({command:"volume", parameters: [${muted ? 0 : 1}]}), "*"); } catch(e){}',
            );
            break;
          case 'setVolume':
            if (arg is num) {
              _webViewController!.runJavaScript(
                'try { const f = document.querySelector("iframe"); if(f) f.contentWindow.postMessage(JSON.stringify({command:"volume", parameters: [$arg]}), "*"); } catch(e){}',
              );
            }
            break;
        }
      } else if (_isBstation) {
        switch (action) {
          case 'play':
            _webViewController!.runJavaScript(
              'try { const v = document.querySelector("video"); if(v) v.play(); } catch(e){}',
            );
            break;
          case 'pause':
            _webViewController!.runJavaScript(
              'try { const v = document.querySelector("video"); if(v) v.pause(); } catch(e){}',
            );
            break;
          case 'seek':
            if (arg is num) {
              _webViewController!.runJavaScript(
                'try { const v = document.querySelector("video"); if(v) v.currentTime = $arg; } catch(e){}',
              );
            }
            break;
          case 'setMuted':
            final bool muted = arg == true;
            _webViewController!.runJavaScript(
              'try { const v = document.querySelector("video"); if(v) v.muted = $muted; } catch(e){}',
            );
            break;
        }
      }
    } catch (e) {
      debugPrint('[TwitchVimeoEmbedPlayer] Command $action error: $e');
    }
  }

  void _initWebViewController() {
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 13; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        )
        ..addJavaScriptChannel(
          'FlutterEmbedChannel',
          onMessageReceived: (JavaScriptMessage message) {
            try {
              final data = jsonDecode(message.message) as Map<String, dynamic>;
              final event = data['event'] as String?;
              if (event == 'timeupdate') {
                final pos = (data['currentTime'] as num?)?.toDouble() ?? 0.0;
                final dur = (data['duration'] as num?)?.toDouble() ?? 0.0;
                widget.player.updateEmbedPlaybackState(
                  isPlaying: true,
                  position: pos,
                  duration: dur,
                );
              } else if (event == 'play') {
                widget.player.updateEmbedPlaybackState(isPlaying: true);
              } else if (event == 'pause') {
                widget.player.updateEmbedPlaybackState(isPlaying: false);
              } else if (event == 'ended') {
                widget.player.onPlaybackEnded?.call();
              }
            } catch (_) {}
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (NavigationRequest request) {
              final uri = Uri.tryParse(request.url);
              if (uri != null) {
                final scheme = uri.scheme.toLowerCase();
                // Block external app schemes (intent:, bstar:, bilibili:, market:)
                if (scheme == 'intent' ||
                    scheme == 'bstar' ||
                    scheme == 'bilibili' ||
                    scheme == 'market') {
                  return NavigationDecision.prevent;
                }
              }
              return NavigationDecision.navigate;
            },
            onPageStarted: (_) {
              if (mounted) {
                setState(() => _isLoading = true);
              }
            },
            onPageFinished: (_) {
              if (mounted) {
                setState(() => _isLoading = false);
                widget.player.updateEmbedPlaybackState(isPlaying: true);
                if (_isBstation) {
                  _injectBstationPlayerStyles();
                }
              }
            },
            onWebResourceError: (error) {
              debugPrint(
                  '[TwitchVimeoEmbedPlayer] Web error: ${error.description} (${error.errorCode})');
            },
          ),
        );

      if (controller.platform is AndroidWebViewController) {
        (controller.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false);
      }

      _webViewController = controller;
      _loadContent();
    } catch (e) {
      debugPrint('[TwitchVimeoEmbedPlayer] Error initializing WebViewController: $e');
    }
  }

  void _injectBstationPlayerStyles() {
    _webViewController?.runJavaScript('''
      try {
        const styleId = 'watch-party-bstation-style';
        if (!document.getElementById(styleId)) {
          const style = document.createElement('style');
          style.id = styleId;
          style.innerHTML = `
            .bstar-header, header, .bstar-footer, footer,
            .open-app, .app-open, .bstar-app-download,
            .fixed-app-download, .guide-open-app, .bstar-ad,
            .video-play__meta, .ep-section, .interactive,
            .layout__header, .bstar-web__header, .bstar-web__banner,
            .player-mobile-play-mask,
            .player-mobile-play-h5-mask,
            .player-mobile-play-h5-mask-icon,
            .player-mobile-play-h5-mask-pause-icon,
            .player-mobile-play-h5-mask-play-icon,
            .player-mobile-ad-pause-container,
            .player-mobile-control-bar,
            .player-mobile-control-bar-top,
            .player-mobile-control-bar-bottom,
            .player-mobile-control-slider,
            .player-mobile-top-bar,
            .player-mobile-top-bar-h5,
            .player-mobile-top-bar-right,
            .player-mobile-top-bar-btn,
            .mute-notification,
            .ip-watermark,
            .player-mobile-load-layer,
            .player-mobile-video-tips,
            .player-mobile-buff-tips {
              display: none !important;
              opacity: 0 !important;
              visibility: hidden !important;
              pointer-events: none !important;
            }
            body, html {
              background-color: #000 !important;
              margin: 0 !important;
              padding: 0 !important;
              overflow: hidden !important;
            }
            .video-play__player, .ogv__player, .bstar-player, .bstar-player__main, #bilibiliPlayer {
              width: 100vw !important;
              height: 100vh !important;
              max-width: 100vw !important;
              max-height: 100vh !important;
              position: fixed !important;
              top: 0 !important;
              left: 0 !important;
              z-index: 99999 !important;
              margin: 0 !important;
              padding: 0 !important;
            }
            video {
              width: 100% !important;
              height: 100% !important;
              object-fit: contain !important;
            }
          `;
          document.head.appendChild(style);
        }

        function setupBridge() {
          const v = document.querySelector('video');
          if (!v) {
            setTimeout(setupBridge, 300);
            return;
          }
          if (v._bridgeAttached) return;
          v._bridgeAttached = true;

          if (v.muted) {
            v.muted = false;
          }
          if (v.paused) {
            v.play().catch(function(){});
          }

          let lastReport = 0;
          v.addEventListener('timeupdate', function() {
            const now = Date.now();
            if (now - lastReport >= 500) {
              lastReport = now;
              if (window.FlutterEmbedChannel) {
                window.FlutterEmbedChannel.postMessage(JSON.stringify({
                  event: 'timeupdate',
                  currentTime: v.currentTime,
                  duration: v.duration || 0
                }));
              }
            }
          });

          v.addEventListener('play', function() {
            if (window.FlutterEmbedChannel) {
              window.FlutterEmbedChannel.postMessage(JSON.stringify({ event: 'play' }));
            }
          });

          v.addEventListener('pause', function() {
            if (window.FlutterEmbedChannel) {
              window.FlutterEmbedChannel.postMessage(JSON.stringify({ event: 'pause' }));
            }
          });

          v.addEventListener('ended', function() {
            if (window.FlutterEmbedChannel) {
              window.FlutterEmbedChannel.postMessage(JSON.stringify({ event: 'ended' }));
            }
          });
        }
        setupBridge();
      } catch(e) {}
    ''');
  }

  void _loadContent() {
    final url = widget.player.mediaUrl.trim();
    if (url.isEmpty || _webViewController == null) return;
    _currentLoadedUrl = url;

    // Bstation (bilibili.tv) direct top-level load to bypass iframe XFO/CSP blocking
    if (_isBstation) {
      final bId = UnifiedPlayerController.extractBstationVideoId(url) ?? url;
      final bool isBv = bId.startsWith('BV') || bId.startsWith('bv');

      if (!isBv) {
        // Direct top-level navigation to Bstation anime/play URL (never iframe)
        final targetUrl = url.startsWith('http')
            ? url
            : 'https://www.bilibili.tv/id/play/$bId';
        _webViewController!.loadRequest(Uri.parse(targetUrl));
        return;
      }
    }

    String embedSrc = '';
    if (_isTwitch) {
      final twitchMedia = UnifiedPlayerController.extractTwitchMedia(url);
      if (twitchMedia != null) {
        if (twitchMedia.isChannel) {
          embedSrc =
              'https://player.twitch.tv/?channel=${twitchMedia.id}&parent=localhost&autoplay=true&muted=false';
        } else if (twitchMedia.isVideo) {
          embedSrc =
              'https://player.twitch.tv/?video=${twitchMedia.id}&parent=localhost&autoplay=true&muted=false';
        } else if (twitchMedia.isClip) {
          embedSrc =
              'https://clips.twitch.tv/embed?clip=${twitchMedia.id}&parent=localhost&autoplay=true&muted=false';
        }
      } else {
        embedSrc =
            'https://player.twitch.tv/?channel=$url&parent=localhost&autoplay=true&muted=false';
      }
    } else if (_isVimeo) {
      final vimeoId = UnifiedPlayerController.extractVimeoVideoId(url) ?? url;
      embedSrc =
          'https://player.vimeo.com/video/$vimeoId?autoplay=1&title=0&byline=0&portrait=0&badge=0';
    } else if (_isGoogleDrive) {
      final driveId = UnifiedPlayerController.extractGoogleDriveFileId(url) ?? url;
      embedSrc = 'https://drive.google.com/file/d/$driveId/preview';
    } else if (_isDailymotion) {
      final dmId = UnifiedPlayerController.extractDailymotionVideoId(url) ?? url;
      embedSrc =
          'https://www.dailymotion.com/embed/video/$dmId?autoplay=1&ui-logo=0&sharing-enable=0';
    } else if (_isBstation) {
      final bId = UnifiedPlayerController.extractBstationVideoId(url) ?? url;
      embedSrc =
          'https://player.bilibili.com/player.html?bvid=$bId&page=1&as_wide=1&high_quality=1&danmaku=0&autoplay=1';
    }

    if (embedSrc.isEmpty) return;

    final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <meta name="referrer" content="no-referrer">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 100%; height: 100%; overflow: hidden; background-color: #000; }
    iframe { width: 100%; height: 100%; border: none; }
  </style>
</head>
<body>
  <iframe
    id="embedFrame"
    src="$embedSrc"
    allow="autoplay; fullscreen; picture-in-picture; encrypted-media"
    allowfullscreen="true"
    referrerpolicy="no-referrer"
    scrolling="no">
  </iframe>
</body>
</html>
''';

    final baseUrl = _isBstation ? 'https://www.bilibili.com' : 'https://localhost';
    _webViewController!.loadHtmlString(htmlContent, baseUrl: baseUrl);
  }

  Color get _themeColor {
    if (_isTwitch) return const Color(0xFF9146FF);
    if (_isVimeo) return const Color(0xFF1AB7EA);
    if (_isGoogleDrive) return const Color(0xFF0F9D58);
    if (_isDailymotion) return const Color(0xFF0066DC);
    if (_isBstation) return const Color(0xFF00A1D6);
    return Colors.white;
  }

  String get _loadingText {
    if (_isTwitch) return 'Memuat Siaran Twitch...';
    if (_isVimeo) return 'Memuat Video Vimeo...';
    if (_isGoogleDrive) return 'Memuat Video Google Drive...';
    if (_isDailymotion) return 'Memuat Video Dailymotion...';
    if (_isBstation) return 'Memuat Video Bstation...';
    return 'Memuat Video...';
  }

  IconData get _sourceIcon {
    if (_isTwitch) return Icons.live_tv_rounded;
    if (_isVimeo) return Icons.video_collection_rounded;
    if (_isGoogleDrive) return Icons.cloud_queue_rounded;
    if (_isDailymotion) return Icons.play_circle_outline_rounded;
    if (_isBstation) return Icons.smart_display_rounded;
    return Icons.play_circle_rounded;
  }

  String get _sourceTitle {
    if (_isTwitch) return 'Twitch Live Stream';
    if (_isVimeo) return 'Vimeo Video Stream';
    if (_isGoogleDrive) return 'Google Drive Video Stream';
    if (_isDailymotion) return 'Dailymotion Video Stream';
    if (_isBstation) return 'Bstation Anime & Video';
    return 'Embedded Video Stream';
  }

  String get _connectedText {
    if (_isTwitch) return 'Tersambung ke Twitch';
    if (_isVimeo) return 'Tersambung ke Vimeo';
    if (_isGoogleDrive) return 'Tersambung ke Google Drive';
    if (_isDailymotion) return 'Tersambung ke Dailymotion';
    if (_isBstation) return 'Tersambung ke Bstation';
    return 'Tersambung ke Media';
  }

  @override
  Widget build(BuildContext context) {
    if (_isSupportedPlatform && _webViewController != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: _webViewController!),
          if (_isLoading && !widget.isPipMode)
            Container(
              color: Colors.black.withValues(alpha: 0.6),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(_themeColor),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _loadingText,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    // Fallback UI for unsupported platforms (e.g. Linux desktop headless or web)
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _themeColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _themeColor,
                  width: 1.5,
                ),
              ),
              child: Icon(
                _sourceIcon,
                color: _themeColor,
                size: 32,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _sourceTitle,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                widget.player.mediaUrl,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: _themeColor,
                    size: 13,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _connectedText,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
