import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../core/constants/app_colors.dart';
import '../../chat/controllers/chat_controller.dart';
import '../../room/controllers/queue_controller.dart';
import '../../room/controllers/sync_controller.dart';

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

  /// Injects JavaScript to listen to YouTube's client-side SPA navigation events
  Future<void> _injectSpaDetector() async {
    if (_webViewController == null) return;

    const script = '''
      (function() {
        if (window.__nobarDetectorInitialized) return;
        window.__nobarDetectorInitialized = true;

        function reportState() {
          try {
            var url = window.location.href;
            var title = document.title || '';
            var titleEl = document.querySelector('h1.slim-video-information-title') ||
                          document.querySelector('ytm-slim-video-information-renderer h1') ||
                          document.querySelector('.ytm-slim-video-metadata-title') ||
                          document.querySelector('.slim-video-metadata-header');
            if (titleEl && titleEl.textContent && titleEl.textContent.trim().length > 0) {
              title = titleEl.textContent.trim();
            }
            if (window.NobarYtDetector) {
              window.NobarYtDetector.postMessage(JSON.stringify({
                url: url,
                title: title
              }));
            }
          } catch (e) {}
        }

        window.addEventListener('yt-navigate-finish', function() {
          setTimeout(reportState, 350);
        });

        var origPushState = history.pushState;
        history.pushState = function() {
          origPushState.apply(this, arguments);
          setTimeout(reportState, 250);
        };

        var origReplaceState = history.replaceState;
        history.replaceState = function() {
          origReplaceState.apply(this, arguments);
          setTimeout(reportState, 250);
        };

        window.addEventListener('popstate', function() {
          setTimeout(reportState, 250);
        });

        setTimeout(reportState, 500);
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

    final videoId = YoutubePlayerController.convertUrlToId(url);
    if (videoId != null && videoId.isNotEmpty) {
      String title = extractedTitle?.trim() ?? '';
      if (title.isEmpty || title.toLowerCase() == 'youtube') {
        title = 'Video YouTube ($videoId)';
      } else {
        title = title.replaceAll(RegExp(r'\s*-\s*YouTube$', caseSensitive: false), '');
      }

      if (videoId == _dismissedVideoId) {
        return;
      }

      if (mounted && (_detectedVideoId != videoId || _detectedTitle != title)) {
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

    final mediaUrl = 'https://www.youtube.com/watch?v=$_detectedVideoId';
    final title = _detectedTitle.isNotEmpty ? _detectedTitle : 'Video YouTube';

    await _pauseWebViewMedia();

    final onVideoSelectedCallback = widget.onVideoSelected;
    final syncCtrl = widget.syncController;
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
    final title = _detectedTitle.isNotEmpty ? _detectedTitle : 'Video YouTube';

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

  void _handleManualFallbackSubmit() {
    final url = _fallbackUrlController.text.trim();
    if (url.isEmpty) return;

    final videoId = YoutubePlayerController.convertUrlToId(url);
    if (videoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL YouTube tidak valid!'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    setState(() {
      _detectedVideoId = videoId;
      _detectedTitle = 'Video YouTube ($videoId)';
    });

    _applyWatchNow();
  }

  void _handleManualFallbackQueue() {
    final url = _fallbackUrlController.text.trim();
    if (url.isEmpty) return;

    final videoId = YoutubePlayerController.convertUrlToId(url);
    if (videoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL YouTube tidak valid!'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    setState(() {
      _detectedVideoId = videoId;
      _detectedTitle = 'Video YouTube ($videoId)';
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: const BoxDecoration(
          color: AppColors.surfaceElevated,
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.youtubeRed.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.smart_display_rounded,
                  color: AppColors.youtubeRed,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _detectedTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _isBannerMinimized = false),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryNeon.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.primaryNeon.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Buka Panel',
                        style: TextStyle(
                          color: AppColors.primaryNeon,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_up_rounded,
                        color: AppColors.primaryNeon,
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
        color: AppColors.surfaceElevated,
        border: const Border(
          top: BorderSide(color: AppColors.border, width: 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Video Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    'https://img.youtube.com/vi/$_detectedVideoId/hqdefault.jpg',
                    width: 70,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 70,
                      height: 44,
                      color: Colors.black26,
                      child: const Icon(Icons.video_library_rounded,
                          color: AppColors.youtubeRed),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Video Title & Detection Badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.youtubeRed.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded,
                                color: AppColors.youtubeRed, size: 12),
                            SizedBox(width: 4),
                            Text(
                              'Video Terdeteksi',
                              style: TextStyle(
                                color: AppColors.youtubeRed,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _detectedTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
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

          const SizedBox(height: 10),

          // Action Buttons per Mode
          if (widget.mode == YouTubeBrowserMode.queueOnly) ...[
            ElevatedButton.icon(
              onPressed: _applyAddToQueue,
              icon: const Icon(Icons.playlist_add_rounded, size: 20),
              label: const Text(
                '+ Tambahkan ke Antrean',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: AppColors.primaryNeon,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ] else if (widget.mode == YouTubeBrowserMode.createRoom) ...[
            ElevatedButton.icon(
              onPressed: _applyWatchNow,
              icon: const Icon(Icons.meeting_room_rounded, size: 20),
              label: const Text(
                'Buka Room dengan Video Ini',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: AppColors.primaryNeon,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ] else if (widget.mode == YouTubeBrowserMode.watchNow) ...[
            ElevatedButton.icon(
              onPressed: _applyWatchNow,
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text(
                'Putar Sekarang di Room',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: AppColors.primaryNeon,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ] else ...[
            // General mode
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: _applyWatchNow,
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text(
                      'Tonton Sekarang',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      backgroundColor: AppColors.primaryNeon,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                if (widget.queueController != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: _applyAddToQueue,
                      icon: const Icon(Icons.playlist_add_rounded, size: 18),
                      label: const Text('+ Antrean'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        foregroundColor: AppColors.primaryNeon,
                        side: const BorderSide(color: AppColors.primaryNeon),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
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
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    backgroundColor: AppColors.primaryNeon,
                    foregroundColor: Colors.black,
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
