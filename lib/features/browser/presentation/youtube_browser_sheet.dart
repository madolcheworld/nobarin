import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/video_title_resolver.dart';
import '../../chat/controllers/chat_controller.dart';
import '../../room/controllers/queue_controller.dart';
import '../../room/controllers/sync_controller.dart';
import '../../room/controllers/unified_player_controller.dart';

/// Mode operasional untuk In-App Browser YouTube
enum YouTubeBrowserMode {
  /// Default: menampilkan tombol Tonton Sekarang & Tambah Antrean
  general,

  /// Khusus untuk Antrean: hanya aksi "+ Tambahkan ke Antrean",
  /// tidak mengganggu/mengubah pemutaran video aktif di room.
  queueOnly,

  /// Khusus untuk Buka / Buat Room: tombol "Buka Room dengan Video Ini"
  createRoom,

  /// Khusus untuk Ganti Video: tombol "Putar Sekarang di Room"
  watchNow,
}

/// In-App Browser sheet that enables users to browse YouTube (m.youtube.com),
/// automatically detects when a video is clicked or navigated to,
/// and provides instant actions to "Tonton Bareng Sekarang" or "Tambah ke Antrean".
class YouTubeBrowserSheet extends StatefulWidget {
  final SyncController? syncController;
  final QueueController? queueController;
  final ChatController? chatController;
  final void Function(String type, String url, String title)? onVideoSelected;
  final YouTubeBrowserMode mode;

  const YouTubeBrowserSheet({
    super.key,
    this.syncController,
    this.queueController,
    this.chatController,
    this.onVideoSelected,
    this.mode = YouTubeBrowserMode.general,
  });

  /// Displays [YouTubeBrowserSheet] as a full-height modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    SyncController? syncController,
    QueueController? queueController,
    ChatController? chatController,
    void Function(String type, String url, String title)? onVideoSelected,
    YouTubeBrowserMode mode = YouTubeBrowserMode.general,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      enableDrag: false,
      builder: (ctx) => YouTubeBrowserSheet(
        syncController: syncController,
        queueController: queueController,
        chatController: chatController,
        onVideoSelected: onVideoSelected,
        mode: mode,
      ),
    );
  }

  @override
  State<YouTubeBrowserSheet> createState() => _YouTubeBrowserSheetState();
}

class _YouTubeBrowserSheetState extends State<YouTubeBrowserSheet> {
  WebViewController? _webViewController;
  bool _isLoading = true;
  double _loadProgress = 0.0;
  String _currentUrl = 'https://m.youtube.com';
  String? _detectedVideoId;
  String _detectedTitle = '';
  bool _isBannerMinimized = false;
  String? _dismissedVideoId;
  bool _canPop = false;
  final TextEditingController _fallbackUrlController = TextEditingController();

  bool get _isSupportedMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (_isSupportedMobilePlatform) {
      _initWebViewController();
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _fallbackUrlController.dispose();
    super.dispose();
  }

  void _initWebViewController() {
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (progress) {
              if (mounted) {
                setState(() {
                  _loadProgress = progress / 100.0;
                  _isLoading = progress < 100;
                });
              }
            },
            onPageStarted: (url) {
              _handleUrlInspection(url);
            },
            onPageFinished: (url) {
              _handleUrlInspection(url);
              _injectSpaDetector();
            },
            onUrlChange: (change) {
              if (change.url != null) {
                _handleUrlInspection(change.url!);
              }
            },
            onNavigationRequest: (request) {
              final uri = Uri.tryParse(request.url);
              if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
                return NavigationDecision.prevent;
              }
              _handleUrlInspection(request.url);
              return NavigationDecision.navigate;
            },
          ),
        )
        ..addJavaScriptChannel(
          'NobarYtDetector',
          onMessageReceived: (message) {
            _handleDetectorMessage(message.message);
          },
        )
        ..loadRequest(Uri.parse('https://m.youtube.com'));

      _webViewController = controller;
    } catch (_) {
      _isLoading = false;
    }
  }

  Future<void> _resolveTitleBackground(String videoId) async {
    try {
      final resolved = await VideoTitleResolver.resolveTitle(
        'https://www.youtube.com/watch?v=$videoId',
        mediaType: 'youtube',
      );
      final clean = VideoTitleResolver.cleanTitle(resolved);
      if (clean.isNotEmpty && mounted && _detectedVideoId == videoId) {
        if (_detectedTitle != clean) {
          setState(() {
            _detectedTitle = clean;
          });
        }
      }
    } catch (_) {}
  }

  /// Injects JavaScript to listen to YouTube's client-side SPA navigation events
  Future<void> _injectSpaDetector() async {
    if (_webViewController == null) return;

    const script = '''
      (function() {
        function cleanTitleStr(str) {
          if (!str) return '';
          var s = str.trim();
          if (/^\\d+\$/.test(s)) return '';
          s = s.replace(/\\s*[-|_]\\s*YouTube.*\$/i, '');
          s = s.trim();
          if (/^\\d+\$/.test(s)) return '';
          if (s.toLowerCase() === 'youtube') return '';
          return s;
        }

        function reportState() {
          try {
            var url = window.location.href;
            var title = '';
            var titleEl = document.querySelector('h1.slim-video-information-title') ||
                          document.querySelector('ytm-slim-video-information-renderer h1') ||
                          document.querySelector('.ytm-slim-video-metadata-title') ||
                          document.querySelector('.slim-video-metadata-header') ||
                          document.querySelector('h1');
            if (titleEl && titleEl.textContent && titleEl.textContent.trim().length > 0) {
              title = cleanTitleStr(titleEl.textContent);
            }
            if (!title) {
              title = cleanTitleStr(document.title);
            }
            if (title && window.NobarYtDetector) {
              window.NobarYtDetector.postMessage(JSON.stringify({
                url: url,
                title: title
              }));
            }
          } catch (e) {}
        }

        if (!window.__nobarDetectorInitialized) {
          window.__nobarDetectorInitialized = true;

          window.addEventListener('yt-navigate-finish', function() {
            setTimeout(reportState, 350);
            setTimeout(reportState, 1000);
          });

          var origPushState = history.pushState;
          history.pushState = function() {
            origPushState.apply(this, arguments);
            setTimeout(reportState, 250);
            setTimeout(reportState, 750);
          };

          var origReplaceState = history.replaceState;
          history.replaceState = function() {
            origReplaceState.apply(this, arguments);
            setTimeout(reportState, 250);
          };

          window.addEventListener('popstate', function() {
            setTimeout(reportState, 250);
          });

          try {
            var observer = new MutationObserver(function() {
              reportState();
            });
            if (document.head) {
              observer.observe(document.head, { subtree: true, characterData: true, childList: true });
            }
            if (document.body) {
              observer.observe(document.body, { childList: true, subtree: true });
            }
          } catch(e) {}
        }

        setTimeout(reportState, 250);
        setTimeout(reportState, 750);
        setTimeout(reportState, 1800);
      })();
    ''';

    try {
      await _webViewController!.runJavaScript(script);
    } catch (_) {}
  }

  void _handleDetectorMessage(String messageText) {
    try {
      final decoded = jsonDecode(messageText);
      if (decoded is Map<String, dynamic>) {
        final url = decoded['url'] as String? ?? '';
        final title = decoded['title'] as String? ?? '';
        _handleUrlInspection(url, extractedTitle: title);
      }
    } catch (_) {}
  }

  void _handleUrlInspection(String url, {String? extractedTitle}) {
    if (url.isEmpty || (url == _currentUrl && extractedTitle == null)) return;
    _currentUrl = url;

    final videoId = UnifiedPlayerController.extractYoutubeId(url);
    if (videoId != null && videoId.isNotEmpty) {
      final clean = VideoTitleResolver.cleanTitle(extractedTitle);
      String title = clean;
      if (title.isEmpty) {
        if (_detectedTitle.isNotEmpty &&
            _detectedTitle != 'Video YouTube' &&
            _detectedTitle != 'Memuat judul video...') {
          title = _detectedTitle;
        } else {
          title = 'Memuat judul video...';
        }
        _resolveTitleBackground(videoId);
      }

      if (videoId == _dismissedVideoId) {
        return;
      }

      if (mounted &&
          (_detectedVideoId != videoId ||
              (_detectedTitle != title && title != 'Memuat judul video...') ||
              (_detectedTitle == 'Memuat judul video...' && title != 'Memuat judul video...'))) {
        setState(() {
          _detectedVideoId = videoId;
          _detectedTitle = title;
          _isBannerMinimized = false;
        });
      } else if (mounted && _detectedVideoId != videoId) {
        setState(() {
          _detectedVideoId = videoId;
          _detectedTitle = title;
          _isBannerMinimized = false;
        });
      }
    }
  }

  Future<void> _pauseWebViewMedia() async {
    if (_webViewController == null) return;
    try {
      await _webViewController!.runJavaScript(
        "document.querySelectorAll('video').forEach(function(v){ v.pause(); });",
      );
    } catch (_) {}
  }

  void _applyWatchNow() async {
    if (_detectedVideoId == null) return;

    final syncCtrl = widget.syncController;
    final onVideoSelectedCallback = widget.onVideoSelected;
    if (onVideoSelectedCallback == null && syncCtrl != null && !syncCtrl.canControl) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hanya Host atau Co-Host yang dapat mengganti video di room ini.'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    final mediaUrl = 'https://www.youtube.com/watch?v=$_detectedVideoId';
    final title = (_detectedTitle.isNotEmpty && _detectedTitle != 'Memuat judul video...')
        ? _detectedTitle
        : 'Video YouTube';

    await _pauseWebViewMedia();

    final chatCtrl = widget.chatController;

    _canPop = true;
    if (mounted) {
      Navigator.of(context).pop({
        'type': 'youtube',
        'url': mediaUrl,
        'title': title,
      });
    }

    if (onVideoSelectedCallback != null) {
      onVideoSelectedCallback('youtube', mediaUrl, title);
    } else if (syncCtrl != null) {
      syncCtrl.requestChangeMedia('youtube', mediaUrl);
      chatCtrl?.sendSystemMessage(
        '${syncCtrl.currentUser.username} memilih video YouTube: "$title"',
      );
    }
  }

  void _applyAddToQueue() {
    if (_detectedVideoId == null || widget.queueController == null) return;

    final mediaUrl = 'https://www.youtube.com/watch?v=$_detectedVideoId';
    final title = (_detectedTitle.isNotEmpty && _detectedTitle != 'Memuat judul video...')
        ? _detectedTitle
        : 'Video YouTube';

    widget.queueController!.addToQueue(
      mediaType: 'youtube',
      mediaUrl: mediaUrl,
      title: title,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.playlist_add_check_rounded, color: Colors.black),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '"$title" ditambahkan ke antrean!',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primaryNeon,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _handleManualFallbackSubmit() async {
    final url = _fallbackUrlController.text.trim();
    if (url.isEmpty) return;

    final videoId = UnifiedPlayerController.extractYoutubeId(url);
    if (videoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL YouTube tidak valid!'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    final resolved = await VideoTitleResolver.resolveTitle(
      'https://www.youtube.com/watch?v=$videoId',
      mediaType: 'youtube',
    );
    final clean = VideoTitleResolver.cleanTitle(resolved);

    setState(() {
      _detectedVideoId = videoId;
      _detectedTitle = clean.isNotEmpty ? clean : 'Video YouTube';
    });

    _applyWatchNow();
  }

  void _handleManualFallbackQueue() async {
    final url = _fallbackUrlController.text.trim();
    if (url.isEmpty) return;

    final videoId = UnifiedPlayerController.extractYoutubeId(url);
    if (videoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL YouTube tidak valid!'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    final resolved = await VideoTitleResolver.resolveTitle(
      'https://www.youtube.com/watch?v=$videoId',
      mediaType: 'youtube',
    );
    final clean = VideoTitleResolver.cleanTitle(resolved);

    setState(() {
      _detectedVideoId = videoId;
      _detectedTitle = clean.isNotEmpty ? clean : 'Video YouTube';
    });

    _applyAddToQueue();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSupportedMobilePlatform || _canPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_webViewController != null && await _webViewController!.canGoBack()) {
          await _webViewController!.goBack();
          return;
        }
        if (context.mounted) {
          setState(() => _canPop = true);
          _pauseWebViewMedia();
          Navigator.of(context).pop();
        }
      },
      child: Container(
        height: MediaQuery.of(context).size.height * 0.94,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Column(
            children: [
              // Top Drag Handle & Navigation Header
              _buildTopBar(context),

              // Progress bar
              if (_isLoading && _loadProgress > 0 && _loadProgress < 1)
                LinearProgressIndicator(
                  value: _loadProgress,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.youtubeRed,
                  ),
                  minHeight: 2.5,
                ),

              // Browser Body or Fallback
              Expanded(
                child: _isSupportedMobilePlatform && _webViewController != null
                    ? WebViewWidget(
                        controller: _webViewController!,
                        gestureRecognizers: {
                          Factory<OneSequenceGestureRecognizer>(
                            () => EagerGestureRecognizer(),
                          ),
                        },
                      )
                    : _buildUnsupportedPlatformFallback(),
              ),

              // Docked Detection Bar (Bottom Action Bar)
              if (_detectedVideoId != null)
                _buildDetectionBanner(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final String modeTitle;
    final String modeSubtitle;
    final IconData modeIcon;
    final Color modeColor;

    switch (widget.mode) {
      case YouTubeBrowserMode.createRoom:
        modeTitle = 'Pilih Video YouTube';
        modeSubtitle = 'Pilih video untuk mulai buat room';
        modeIcon = Icons.meeting_room_rounded;
        modeColor = AppColors.youtubeRed;
        break;
      case YouTubeBrowserMode.queueOnly:
        modeTitle = 'Tambah ke Antrean';
        modeSubtitle = 'Pilih video untuk tontonan berikutnya';
        modeIcon = Icons.playlist_add_rounded;
        modeColor = AppColors.primaryNeon;
        break;
      case YouTubeBrowserMode.watchNow:
        modeTitle = 'Ganti Video Room';
        modeSubtitle = 'Pilih video untuk langsung diputar';
        modeIcon = Icons.swap_horiz_rounded;
        modeColor = AppColors.secondaryNeon;
        break;
      case YouTubeBrowserMode.general:
        modeTitle = 'YouTube In-App';
        modeSubtitle = 'Jelajahi & pilih video bersama';
        modeIcon = Icons.smart_display_rounded;
        modeColor = AppColors.youtubeRed;
        break;
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Row(
            children: [
              // Close Button
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: AppColors.textPrimary, size: 22),
                tooltip: 'Tutup',
                onPressed: () {
                  setState(() => _canPop = true);
                  _pauseWebViewMedia();
                  Navigator.of(context).pop();
                },
              ),

              const SizedBox(width: 4),

              // Mode & Context Header
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: modeColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        modeIcon,
                        color: modeColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            modeTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            modeSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Navigation Actions: Back & Refresh
              if (_isSupportedMobilePlatform && _webViewController != null) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: AppColors.textSecondary, size: 17),
                  tooltip: 'Halaman Sebelumnya',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    if (await _webViewController!.canGoBack()) {
                      _webViewController!.goBack();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded,
                      color: AppColors.textSecondary, size: 19),
                  tooltip: 'Muat Ulang',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _webViewController!.reload(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionBanner(BuildContext context) {
    if (_isBannerMinimized) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          border: Border(
            top: BorderSide(
              color: AppColors.primaryNeon.withValues(alpha: 0.75),
              width: 1.5,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.youtubeRed.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.smart_display_rounded,
                  color: AppColors.youtubeRed,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _detectedTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _isBannerMinimized = false),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryNeon.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primaryNeonLight.withValues(alpha: 0.6),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Pilih Video',
                        style: TextStyle(
                          color: AppColors.primaryNeonLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 3),
                      Icon(
                        Icons.keyboard_arrow_up_rounded,
                        color: AppColors.primaryNeonLight,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    size: 18, color: AppColors.textSecondary),
                onPressed: () {
                  setState(() {
                    _dismissedVideoId = _detectedVideoId;
                    _detectedVideoId = null;
                  });
                },
                visualDensity: VisualDensity.compact,
                tooltip: 'Abaikan',
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.surfaceHighlight,
            AppColors.surfaceElevated,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          top: BorderSide(
            color: AppColors.primaryNeon.withValues(alpha: 0.85),
            width: 2.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.75),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
          BoxShadow(
            color: AppColors.primaryNeon.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Video Thumbnail with subtle frame
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.youtubeRed.withValues(alpha: 0.6),
                      width: 1.2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.5),
                    child: Image.network(
                      'https://img.youtube.com/vi/$_detectedVideoId/hqdefault.jpg',
                      width: 86,
                      height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 86,
                        height: 52,
                        color: Colors.black26,
                        child: const Icon(Icons.video_library_rounded,
                            color: AppColors.youtubeRed, size: 24),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Video Title & Detection Badges
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.accentGreen.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: AppColors.accentGreen
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_rounded,
                                    color: AppColors.accentGreen, size: 12),
                                SizedBox(width: 4),
                                Text(
                                  'SIAP DIPILIH',
                                  style: TextStyle(
                                    color: AppColors.accentGreen,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.youtubeRed.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.smart_display_rounded,
                                    color: AppColors.youtubeRed, size: 12),
                                SizedBox(width: 4),
                                Text(
                                  'YouTube',
                                  style: TextStyle(
                                    color: AppColors.youtubeRed,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _detectedTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),

                // Minimize Button
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textSecondary, size: 22),
                  onPressed: () {
                    setState(() {
                      _isBannerMinimized = true;
                    });
                  },
                  tooltip: 'Sembunyikan',
                  visualDensity: VisualDensity.compact,
                ),

                // Dismiss Button
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textSecondary, size: 20),
                  onPressed: () {
                    setState(() {
                      _dismissedVideoId = _detectedVideoId;
                      _detectedVideoId = null;
                    });
                  },
                  tooltip: 'Abaikan',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Action Buttons per Mode
            if (widget.mode == YouTubeBrowserMode.queueOnly) ...[
              Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryNeon.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: _applyAddToQueue,
                  icon: const Icon(Icons.playlist_add_rounded,
                      size: 22, color: Colors.white),
                  label: const Text(
                    '+ Pilih & Tambah ke Antrean',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ] else if (widget.mode == YouTubeBrowserMode.createRoom) ...[
              Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryNeon.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: _applyWatchNow,
                  icon: const Icon(Icons.check_circle_rounded,
                      size: 21, color: Colors.white),
                  label: const Text(
                    'Pilih Video Ini & Buat Room',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ] else if (widget.mode == YouTubeBrowserMode.watchNow) ...[
              Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryNeon.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: _applyWatchNow,
                  icon: const Icon(Icons.play_circle_fill_rounded,
                      size: 22, color: Colors.white),
                  label: const Text(
                    'Pilih & Putar Video Ini',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ] else ...[
              // General mode
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _applyWatchNow,
                        icon: const Icon(Icons.play_arrow_rounded,
                            size: 21, color: Colors.white),
                        label: const Text(
                          'Pilih & Tonton Sekarang',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.queueController != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton.icon(
                          onPressed: _applyAddToQueue,
                          icon: const Icon(Icons.playlist_add_rounded, size: 19),
                          label: const Text(
                            '+ Antrean',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryNeonLight,
                            side: const BorderSide(
                              color: AppColors.primaryNeonLight,
                              width: 1.4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUnsupportedPlatformFallback() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.youtubeRed.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.smart_display_rounded,
                    color: AppColors.youtubeRed,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'In-App Browser YouTube',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'In-App Browser interaktif dioptimalkan untuk perangkat Android dan iOS. '
                  'Pada desktop/web, Anda dapat memasukkan tautan video YouTube secara langsung di bawah ini:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _fallbackUrlController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'https://www.youtube.com/watch?v=...',
                    prefixIcon: const Icon(Icons.link_rounded,
                        color: AppColors.youtubeRed, size: 20),
                    filled: true,
                    fillColor: AppColors.surfaceElevated,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                  onSubmitted: (_) => widget.mode == YouTubeBrowserMode.queueOnly
                      ? _handleManualFallbackQueue()
                      : _handleManualFallbackSubmit(),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: widget.mode == YouTubeBrowserMode.queueOnly
                      ? _handleManualFallbackQueue
                      : _handleManualFallbackSubmit,
                  icon: Icon(
                    widget.mode == YouTubeBrowserMode.queueOnly
                        ? Icons.playlist_add_rounded
                        : (widget.mode == YouTubeBrowserMode.createRoom
                            ? Icons.meeting_room_rounded
                            : Icons.play_arrow_rounded),
                    size: 20,
                  ),
                  label: Text(
                    widget.mode == YouTubeBrowserMode.queueOnly
                        ? '+ Tambahkan ke Antrean'
                        : (widget.mode == YouTubeBrowserMode.createRoom
                            ? 'Buka Room dengan Video Ini'
                            : (widget.mode == YouTubeBrowserMode.watchNow
                                ? 'Putar Sekarang di Room'
                                : 'Tonton Video Ini')),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: AppColors.primaryNeonDark,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
