import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../chat/controllers/chat_controller.dart';
import '../../room/controllers/queue_controller.dart';
import '../../room/controllers/sync_controller.dart';

/// Mode operasional untuk In-App Browser Bstation / Bilibili
enum BstationBrowserMode {
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

/// In-App Browser sheet that enables users to browse Bstation / Bilibili (bilibili.tv),
/// automatically detects when an anime/video episode is clicked or navigated to,
/// and provides instant actions to "Tonton Sekarang" or "Tambah ke Antrean".
class BstationBrowserSheet extends StatefulWidget {
  final SyncController? syncController;
  final QueueController? queueController;
  final ChatController? chatController;
  final void Function(String type, String url, String title)? onVideoSelected;
  final BstationBrowserMode mode;

  const BstationBrowserSheet({
    super.key,
    this.syncController,
    this.queueController,
    this.chatController,
    this.onVideoSelected,
    this.mode = BstationBrowserMode.general,
  });

  /// Displays [BstationBrowserSheet] as a full-height modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    SyncController? syncController,
    QueueController? queueController,
    ChatController? chatController,
    void Function(String type, String url, String title)? onVideoSelected,
    BstationBrowserMode mode = BstationBrowserMode.general,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      enableDrag: false,
      builder: (ctx) => BstationBrowserSheet(
        syncController: syncController,
        queueController: queueController,
        chatController: chatController,
        onVideoSelected: onVideoSelected,
        mode: mode,
      ),
    );
  }

  @override
  State<BstationBrowserSheet> createState() => _BstationBrowserSheetState();
}

class _BstationBrowserSheetState extends State<BstationBrowserSheet> {
  WebViewController? _webViewController;
  bool _isLoading = true;
  double _loadProgress = 0.0;
  String _currentUrl = 'https://www.bilibili.tv/id';
  String? _detectedVideoUrl;
  String _detectedTitle = '';
  String? _detectedThumbnail;
  bool _isBannerMinimized = false;
  String? _dismissedVideoUrl;
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
          'NobarBstationDetector',
          onMessageReceived: (message) {
            _handleDetectorMessage(message.message);
          },
        )
        ..loadRequest(Uri.parse('https://www.bilibili.tv/id'));

      _webViewController = controller;
    } catch (_) {
      _isLoading = false;
    }
  }

  /// Injects JavaScript to observe SPA navigation & video elements on Bstation
  Future<void> _injectSpaDetector() async {
    if (_webViewController == null) return;

    const script = '''
      (function() {
        if (window.__nobarBstationDetectorInitialized) return;
        window.__nobarBstationDetectorInitialized = true;

        function reportBstationState() {
          try {
            var url = window.location.href;
            var isVideoPage = /\\/play\\/\\d+|\\/video\\/|b23\\.tv/i.test(url);
            
            // Also check for active video element
            var v = document.querySelector('video');
            if (v && (v.src || v.currentSrc)) {
              isVideoPage = true;
            }

            if (isVideoPage) {
              var title = '';
              var ogTitle = document.querySelector('meta[property="og:title"]');
              if (ogTitle && ogTitle.content) {
                title = ogTitle.content;
              }
              if (!title) {
                var titleEl = document.querySelector('h1') ||
                              document.querySelector('.ep-info__title') ||
                              document.querySelector('.video-info__title') ||
                              document.querySelector('.bstar-meta__title');
                if (titleEl && titleEl.textContent && titleEl.textContent.trim().length > 0) {
                  title = titleEl.textContent.trim();
                }
              }
              if (!title) {
                title = document.title || '';
              }
              
              var thumbnail = '';
              var ogImage = document.querySelector('meta[property="og:image"]');
              if (ogImage && ogImage.content) {
                thumbnail = ogImage.content;
              }
              if (!thumbnail && v && v.getAttribute('poster')) {
                thumbnail = v.getAttribute('poster');
              }

              if (window.NobarBstationDetector) {
                window.NobarBstationDetector.postMessage(JSON.stringify({
                  url: url,
                  title: title,
                  thumbnail: thumbnail
                }));
              }
            }
          } catch (e) {}
        }

        var origPushState = history.pushState;
        history.pushState = function() {
          origPushState.apply(this, arguments);
          setTimeout(reportBstationState, 350);
        };

        var origReplaceState = history.replaceState;
        history.replaceState = function() {
          origReplaceState.apply(this, arguments);
          setTimeout(reportBstationState, 350);
        };

        window.addEventListener('popstate', function() {
          setTimeout(reportBstationState, 300);
        });

        function injectClutterStyles() {
          try {
            if (document.getElementById('nobar-bstation-clutter-style')) return;
            var style = document.createElement('style');
            style.id = 'nobar-bstation-clutter-style';
            style.textContent = `
              .dialog, .dialog__wrap, .dialog__container, .video-toapp-dialog,
              .dialog--mobile, .video-toapp-content, .bstar-dialog,
              .bstar-dialog-mask, .bstar-dialog__wrapper, .bstar-modal,
              .bstar-mask, .bstar-openapp-dialog, .open-app-dialog,
              .bstar-pop, .bstar-pop-wrap, .bstar-popup,
              .bstar-open-app, .bstar-app-banner, .open-app, .openapp,
              [class*="video-toapp"], [class*="toapp"], [class*="open-app"],
              [class*="openapp"], [class*="app-download"] {
                display: none !important;
                opacity: 0 !important;
                pointer-events: none !important;
                visibility: hidden !important;
              }
            `;
            document.head.appendChild(style);
          } catch(e) {}
        }
        injectClutterStyles();

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
        cleanBstationClutter();
        setInterval(cleanBstationClutter, 600);

        setInterval(reportBstationState, 1500);
        setTimeout(reportBstationState, 500);
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
        final thumbnail = decoded['thumbnail'] as String? ?? '';
        _handleUrlInspection(url, extractedTitle: title, extractedThumbnail: thumbnail);
      }
    } catch (_) {}
  }

  void _handleUrlInspection(
    String url, {
    String? extractedTitle,
    String? extractedThumbnail,
  }) {
    if (url.isEmpty || (url == _currentUrl && extractedTitle == null && extractedThumbnail == null)) {
      return;
    }
    _currentUrl = url;

    // Reset dismissed state if user navigates to a different URL
    if (_dismissedVideoUrl != null && _dismissedVideoUrl != url) {
      _dismissedVideoUrl = null;
    }

    // If this URL was dismissed by user, do not re-trigger banner
    if (url == _dismissedVideoUrl) {
      return;
    }

    // Check whether the URL points to a Bstation / Bilibili video page
    final lower = url.toLowerCase();
    final isBstationVideo = lower.contains('/play/') ||
        lower.contains('/video/') ||
        lower.contains('b23.tv');

    if (isBstationVideo) {
      String title = extractedTitle?.trim() ?? '';
      if (title.isEmpty ||
          title.toLowerCase() == 'bstation' ||
          title.toLowerCase() == 'bilibili') {
        // Extract id or segment
        final uri = Uri.tryParse(url);
        final segment = uri != null && uri.pathSegments.isNotEmpty
            ? uri.pathSegments.last
            : 'Bstation';
        title = 'Video Bstation ($segment)';
      } else {
        // Clean common platform suffix
        title = title.replaceAll(
          RegExp(r'\s*[-|_]\s*(Bilibili|Bstation).*$', caseSensitive: false),
          '',
        );
      }

      String? thumb = extractedThumbnail?.trim();
      if (thumb != null && thumb.isEmpty) thumb = null;

      if (mounted && (_detectedVideoUrl != url || _detectedTitle != title)) {
        setState(() {
          _detectedVideoUrl = url;
          _detectedTitle = title;
          if (thumb != null) {
            _detectedThumbnail = thumb;
          }
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
    final mediaUrl = _detectedVideoUrl;
    if (mediaUrl == null || mediaUrl.isEmpty) return;

    final title = _detectedTitle.isNotEmpty ? _detectedTitle : 'Video Bstation';

    await _pauseWebViewMedia();

    final onVideoSelectedCallback = widget.onVideoSelected;
    final syncCtrl = widget.syncController;
    final chatCtrl = widget.chatController;

    _canPop = true;
    if (mounted) {
      Navigator.of(context).pop({
        'type': 'bstation',
        'url': mediaUrl,
        'title': title,
      });
    }

    if (onVideoSelectedCallback != null) {
      onVideoSelectedCallback('bstation', mediaUrl, title);
    } else if (syncCtrl != null) {
      syncCtrl.requestChangeMedia('bstation', mediaUrl);
      chatCtrl?.sendSystemMessage(
        '${syncCtrl.currentUser.username} memilih video Bstation: "$title"',
      );
    }
  }

  void _applyAddToQueue() {
    final mediaUrl = _detectedVideoUrl;
    if (mediaUrl == null || mediaUrl.isEmpty || widget.queueController == null) {
      return;
    }

    final title = _detectedTitle.isNotEmpty ? _detectedTitle : 'Video Bstation';

    widget.queueController!.addToQueue(
      mediaType: 'bstation',
      mediaUrl: mediaUrl,
      title: title,
      thumbnailUrl: _detectedThumbnail,
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

  bool _isValidBstationUrl(String url) {
    final lower = url.trim().toLowerCase();
    return lower.contains('bilibili.tv') ||
        lower.contains('bilibili.com') ||
        lower.contains('b23.tv');
  }

  void _handleManualFallbackSubmit() {
    final url = _fallbackUrlController.text.trim();
    if (url.isEmpty) return;

    if (!_isValidBstationUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL Bstation / Bilibili tidak valid!'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    setState(() {
      _detectedVideoUrl = url;
      _detectedTitle = 'Video Bstation';
    });

    _applyWatchNow();
  }

  void _handleManualFallbackQueue() {
    final url = _fallbackUrlController.text.trim();
    if (url.isEmpty) return;

    if (!_isValidBstationUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL Bstation / Bilibili tidak valid!'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    setState(() {
      _detectedVideoUrl = url;
      _detectedTitle = 'Video Bstation';
    });

    _applyAddToQueue();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSupportedMobilePlatform || _canPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_webViewController != null && await _webViewController!.canGoBack()) {
          await _webViewController!.goBack();
          return;
        }
        if (context.mounted) {
          _pauseWebViewMedia();
          _canPop = true;
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
                    AppColors.bstationBlue,
                  ),
                  minHeight: 2.5,
                ),

              // Browser Body or Fallback (takes available vertical space)
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
              if (_detectedVideoUrl != null)
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
      case BstationBrowserMode.createRoom:
        modeTitle = 'Pilih Video Bstation';
        modeSubtitle = 'Pilih anime/video untuk buat room';
        modeIcon = Icons.meeting_room_rounded;
        modeColor = AppColors.bstationBlue;
        break;
      case BstationBrowserMode.queueOnly:
        modeTitle = 'Tambah ke Antrean';
        modeSubtitle = 'Pilih video Bstation untuk antrean';
        modeIcon = Icons.playlist_add_rounded;
        modeColor = AppColors.primaryNeon;
        break;
      case BstationBrowserMode.watchNow:
        modeTitle = 'Ganti Video Room';
        modeSubtitle = 'Pilih video Bstation untuk diputar';
        modeIcon = Icons.swap_horiz_rounded;
        modeColor = AppColors.bstationBlue;
        break;
      case BstationBrowserMode.general:
        modeTitle = 'Bstation In-App';
        modeSubtitle = 'Jelajahi & pilih video bersama';
        modeIcon = Icons.tv_rounded;
        modeColor = AppColors.bstationBlue;
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
                  color: AppColors.bstationBlue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.tv_rounded,
                  color: AppColors.bstationBlue,
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
                    color: AppColors.bstationBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.bstationBlue.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Buka Panel',
                        style: TextStyle(
                          color: AppColors.bstationBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_up_rounded,
                        color: AppColors.bstationBlue,
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
                    _dismissedVideoUrl = _detectedVideoUrl;
                    _detectedVideoUrl = null;
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
                  child: _detectedThumbnail != null && _detectedThumbnail!.isNotEmpty
                      ? Image.network(
                          _detectedThumbnail!,
                          width: 72,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 72,
                            height: 48,
                            color: AppColors.bstationBlue.withValues(alpha: 0.2),
                            child: const Icon(Icons.tv_rounded,
                                color: AppColors.bstationBlue),
                          ),
                        )
                      : Container(
                          width: 72,
                          height: 48,
                          color: AppColors.bstationBlue.withValues(alpha: 0.2),
                          child: const Icon(Icons.tv_rounded,
                              color: AppColors.bstationBlue),
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
                          color: AppColors.bstationBlue.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded,
                                color: AppColors.bstationBlue, size: 12),
                            SizedBox(width: 4),
                            Text(
                              'Video Bstation Terdeteksi',
                              style: TextStyle(
                                color: AppColors.bstationBlue,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _detectedTitle,
                        maxLines: 2,
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

                // Minimize & Dismiss Buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textSecondary, size: 22),
                      onPressed: () {
                        setState(() {
                          _isBannerMinimized = true;
                        });
                      },
                      tooltip: 'Kecilkan',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textSecondary, size: 20),
                      onPressed: () {
                        setState(() {
                          _dismissedVideoUrl = _detectedVideoUrl;
                          _detectedVideoUrl = null;
                        });
                      },
                      tooltip: 'Abaikan',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Action Buttons per Mode
            if (widget.mode == BstationBrowserMode.queueOnly) ...[
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
            ] else if (widget.mode == BstationBrowserMode.createRoom) ...[
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
            ] else if (widget.mode == BstationBrowserMode.watchNow) ...[
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.bstationBlue.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.tv_rounded,
                  color: AppColors.bstationBlue,
                  size: 48,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'In-App Browser Bstation',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Peramban web in-app aktif pada perangkat mobile. Di lingkungan ini, silakan tempel tautan video Bstation / Bilibili secara langsung:',
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
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'https://www.bilibili.tv/id/play/...',
                  prefixIcon: const Icon(
                    Icons.link_rounded,
                    color: AppColors.bstationBlue,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (widget.mode == BstationBrowserMode.queueOnly)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _handleManualFallbackQueue,
                    icon: const Icon(Icons.playlist_add_rounded, size: 18),
                    label: const Text('+ Tambahkan ke Antrean'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: AppColors.primaryNeon,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                )
              else if (widget.mode == BstationBrowserMode.createRoom)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _handleManualFallbackSubmit,
                    icon: const Icon(Icons.meeting_room_rounded, size: 18),
                    label: const Text('Buka Room dengan Video Ini'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: AppColors.primaryNeon,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        onPressed: _handleManualFallbackSubmit,
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Text(
                          widget.mode == BstationBrowserMode.watchNow
                              ? 'Putar Sekarang di Room'
                              : 'Tonton Video Ini',
                          style: const TextStyle(fontWeight: FontWeight.bold),
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
                    ),
                    if (widget.queueController != null &&
                        widget.mode != BstationBrowserMode.watchNow) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: OutlinedButton.icon(
                          onPressed: _handleManualFallbackQueue,
                          icon: const Icon(Icons.playlist_add_rounded, size: 17),
                          label: const Text('+ Antrean'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
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
          ),
        ),
      ),
    );
  }
}
