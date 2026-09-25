import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/video_title_resolver.dart';
import '../../chat/controllers/chat_controller.dart';
import '../../room/controllers/dailymotion_player_controller.dart';
import '../../room/controllers/queue_controller.dart';
import '../../room/controllers/sync_controller.dart';

/// Mode operasional untuk In-App Browser Dailymotion
enum DailymotionBrowserMode {
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

/// In-App Browser sheet that enables users to browse Dailymotion (dailymotion.com),
/// automatically detects when a video is clicked or navigated to,
/// and provides instant actions to "Tonton Sekarang" or "Tambah ke Antrean".
class DailymotionBrowserSheet extends StatefulWidget {
  final SyncController? syncController;
  final QueueController? queueController;
  final ChatController? chatController;
  final void Function(String type, String url, String title)? onVideoSelected;
  final DailymotionBrowserMode mode;

  const DailymotionBrowserSheet({
    super.key,
    this.syncController,
    this.queueController,
    this.chatController,
    this.onVideoSelected,
    this.mode = DailymotionBrowserMode.general,
  });

  /// Displays [DailymotionBrowserSheet] as a full-height modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    SyncController? syncController,
    QueueController? queueController,
    ChatController? chatController,
    void Function(String type, String url, String title)? onVideoSelected,
    DailymotionBrowserMode mode = DailymotionBrowserMode.general,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      enableDrag: false,
      builder: (ctx) => DailymotionBrowserSheet(
        syncController: syncController,
        queueController: queueController,
        chatController: chatController,
        onVideoSelected: onVideoSelected,
        mode: mode,
      ),
    );
  }

  @override
  State<DailymotionBrowserSheet> createState() => _DailymotionBrowserSheetState();
}

class _DailymotionBrowserSheetState extends State<DailymotionBrowserSheet> {
  WebViewController? _webViewController;
  bool _isLoading = true;
  double _loadProgress = 0.0;
  String _currentUrl = 'https://www.dailymotion.com';
  String? _detectedVideoUrl;
  String _detectedTitle = '';
  String? _detectedThumbnail;
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
          'NobarDailymotionDetector',
          onMessageReceived: (message) {
            _handleDetectorMessage(message.message);
          },
        )
        ..loadRequest(Uri.parse('https://www.dailymotion.com'));

      _webViewController = controller;
    } catch (_) {
      _isLoading = false;
    }
  }

  Future<void> _resolveTitleBackground(String videoId) async {
    try {
      final resolved = await VideoTitleResolver.resolveTitle(
        'https://www.dailymotion.com/video/$videoId',
        mediaType: 'dailymotion',
      );
      final clean = VideoTitleResolver.cleanTitle(resolved);
      if (clean.isNotEmpty && mounted) {
        final currentId = _detectedVideoUrl != null
            ? DailymotionPlayerController.extractVideoId(_detectedVideoUrl!)
            : null;
        if (currentId == videoId && _detectedTitle != clean) {
          setState(() {
            _detectedTitle = clean;
          });
        }
      }
    } catch (_) {}
  }

  /// Injects JavaScript to observe SPA navigation & video elements on Dailymotion
  Future<void> _injectSpaDetector() async {
    if (_webViewController == null) return;

    const script = '''
      (function() {
        function cleanTitleStr(str) {
          if (!str) return '';
          var s = str.trim();
          if (/^\\d+\$/.test(s)) return '';
          s = s.replace(/\\s*[-|_]\\s*Dailymotion.*\$/i, '');
          s = s.replace(/\\s*\\|\\s*Dailymotion.*\$/i, '');
          s = s.trim();
          if (/^\\d+\$/.test(s)) return '';
          if (s.toLowerCase() === 'dailymotion') return '';
          return s;
        }

        function reportDailymotionState() {
          try {
            var url = window.location.href;
            var isVideoPage = /\\/video\\/|dai\\.ly\\/|player\\.html\\?video=/i.test(url);

            var v = document.querySelector('video');
            if (v && (v.src || v.currentSrc)) {
              isVideoPage = true;
            }

            if (isVideoPage) {
              var title = '';
              var ogTitle = document.querySelector('meta[property="og:title"]');
              if (ogTitle && ogTitle.content) {
                title = cleanTitleStr(ogTitle.content);
              }
              if (!title) {
                var twTitle = document.querySelector('meta[name="twitter:title"]');
                if (twTitle && twTitle.content) {
                  title = cleanTitleStr(twTitle.content);
                }
              }
              if (!title) {
                var h1 = document.querySelector('h1');
                if (h1 && h1.textContent && h1.textContent.trim().length > 0) {
                  title = cleanTitleStr(h1.textContent);
                }
              }
              if (!title) {
                title = cleanTitleStr(document.title);
              }

              title = cleanTitleStr(title);

              var thumbnail = '';
              var ogImage = document.querySelector('meta[property="og:image"]');
              if (ogImage && ogImage.content) {
                thumbnail = ogImage.content;
              }
              if (!thumbnail && v && v.getAttribute('poster')) {
                thumbnail = v.getAttribute('poster');
              }

              if (window.NobarDailymotionDetector) {
                window.NobarDailymotionDetector.postMessage(JSON.stringify({
                  url: url,
                  title: title,
                  thumbnail: thumbnail
                }));
              }
            }
          } catch (e) {}
        }

        if (!window.__nobarDailymotionDetectorInitialized) {
          window.__nobarDailymotionDetectorInitialized = true;

          var origPushState = history.pushState;
          history.pushState = function() {
            origPushState.apply(this, arguments);
            setTimeout(reportDailymotionState, 250);
            setTimeout(reportDailymotionState, 750);
          };

          var origReplaceState = history.replaceState;
          history.replaceState = function() {
            origReplaceState.apply(this, arguments);
            setTimeout(reportDailymotionState, 250);
            setTimeout(reportDailymotionState, 750);
          };

          window.addEventListener('popstate', function() {
            setTimeout(reportDailymotionState, 250);
          });

          try {
            var observer = new MutationObserver(function() {
              reportDailymotionState();
            });
            if (document.head) {
              observer.observe(document.head, { subtree: true, characterData: true, childList: true });
            }
            if (document.body) {
              observer.observe(document.body, { childList: true, subtree: true });
            }
          } catch(e) {}

          setInterval(reportDailymotionState, 1200);
        }

        setTimeout(reportDailymotionState, 300);
        setTimeout(reportDailymotionState, 800);
        setTimeout(reportDailymotionState, 1800);
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

    if (url == _dismissedVideoUrl) {
      return;
    }

    final videoId = DailymotionPlayerController.extractVideoId(url);
    final isDailymotionVideo = videoId != null && videoId.isNotEmpty;

    if (isDailymotionVideo) {
      final clean = VideoTitleResolver.cleanTitle(extractedTitle);
      String title = clean;
      if (title.isEmpty) {
        if (_detectedTitle.isNotEmpty &&
            _detectedTitle != 'Video Dailymotion' &&
            _detectedTitle != 'Memuat judul video...') {
          title = _detectedTitle;
        } else {
          title = 'Memuat judul video...';
        }
        _resolveTitleBackground(videoId);
      }

      final thumb = (extractedThumbnail != null && extractedThumbnail.isNotEmpty)
          ? extractedThumbnail
          : 'https://www.dailymotion.com/thumbnail/video/$videoId';

      if (mounted &&
          (_detectedVideoUrl != url ||
              (_detectedTitle != title && title != 'Memuat judul video...') ||
              (_detectedTitle == 'Memuat judul video...' && title != 'Memuat judul video...'))) {
        setState(() {
          _detectedVideoUrl = url;
          _detectedTitle = title;
          _detectedThumbnail = thumb;
        });
      } else if (mounted && _detectedVideoUrl != url) {
        setState(() {
          _detectedVideoUrl = url;
          _detectedTitle = title;
          _detectedThumbnail = thumb;
        });
      }
    } else {
      if (_detectedVideoUrl != null && mounted) {
        setState(() {
          _detectedVideoUrl = null;
          _detectedTitle = '';
          _detectedThumbnail = null;
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

  void _handleVideoSelection(String actionType) async {
    final url = _detectedVideoUrl;
    if (url == null || url.isEmpty) return;

    final title = (_detectedTitle.isNotEmpty && _detectedTitle != 'Memuat judul video...')
        ? _detectedTitle
        : 'Video Dailymotion';

    await _pauseWebViewMedia();
    if (!mounted) return;

    // 1. Create Room Mode
    if (widget.mode == DailymotionBrowserMode.createRoom) {
      widget.onVideoSelected?.call('dailymotion', url, title);
      setState(() => _canPop = true);
      Navigator.of(context).pop();
      return;
    }

    // 2. Queue-Only Mode
    if (widget.mode == DailymotionBrowserMode.queueOnly || actionType == 'queue') {
      if (widget.queueController != null) {
        widget.queueController!.addToQueue(
          mediaType: 'dailymotion',
          mediaUrl: url,
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
      setState(() => _canPop = true);
      Navigator.of(context).pop();
      return;
    }

    // 3. Watch Now Mode
    if (widget.syncController != null) {
      if (!widget.syncController!.canControl) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Hanya Host/Co-host yang dapat mengubah video saat kontrol dikunci.',
            ),
            backgroundColor: AppColors.accentRed,
          ),
        );
        return;
      }
      widget.syncController!.requestChangeMedia('dailymotion', url);
      widget.chatController?.sendSystemMessage(
        '${widget.syncController!.currentUser.username} memutar "$title" dari Dailymotion.',
      );
    }
    widget.onVideoSelected?.call('dailymotion', url, title);
    setState(() => _canPop = true);
    Navigator.of(context).pop();
  }

  Future<void> _handlePop() async {
    if (_webViewController != null && await _webViewController!.canGoBack()) {
      await _webViewController!.goBack();
      return;
    }
    await _pauseWebViewMedia();
    if (mounted) {
      setState(() => _canPop = true);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handlePop();
        }
      },
      child: Container(
        height: MediaQuery.of(context).size.height * 0.94,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: AppColors.border, width: 1.2)),
        ),
        clipBehavior: Clip.hardEdge,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              _buildTopBar(),
              if (_isLoading)
                LinearProgressIndicator(
                  value: _loadProgress > 0 ? _loadProgress : null,
                  backgroundColor: AppColors.surfaceHighlight,
                  color: AppColors.dailymotionBlue,
                  minHeight: 2.5,
                ),
              Expanded(
                child: Stack(
                  children: [
                    if (_isSupportedMobilePlatform && _webViewController != null)
                      WebViewWidget(
                        controller: _webViewController!,
                        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
                          Factory<OneSequenceGestureRecognizer>(
                            EagerGestureRecognizer.new,
                          ),
                        },
                      )
                    else
                      _buildDesktopFallback(),
                    if (_detectedVideoUrl != null)
                      Positioned(
                        bottom: 12,
                        left: 12,
                        right: 12,
                        child: _buildDetectedVideoFloatingBanner(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final String modeTitle;
    final String modeSubtitle;
    final IconData modeIcon;
    final Color modeColor;

    switch (widget.mode) {
      case DailymotionBrowserMode.createRoom:
        modeTitle = 'Pilih Video Dailymotion';
        modeSubtitle = 'Pilih video Dailymotion untuk buat room';
        modeIcon = Icons.meeting_room_rounded;
        modeColor = AppColors.dailymotionBlue;
        break;
      case DailymotionBrowserMode.queueOnly:
        modeTitle = 'Tambah ke Antrean';
        modeSubtitle = 'Pilih video Dailymotion untuk antrean';
        modeIcon = Icons.playlist_add_rounded;
        modeColor = AppColors.primaryNeon;
        break;
      case DailymotionBrowserMode.watchNow:
        modeTitle = 'Ganti Video Room';
        modeSubtitle = 'Pilih video Dailymotion untuk diputar';
        modeIcon = Icons.swap_horiz_rounded;
        modeColor = AppColors.dailymotionBlue;
        break;
      case DailymotionBrowserMode.general:
        modeTitle = 'Dailymotion';
        modeSubtitle = 'Jelajahi & tonton video bersama';
        modeIcon = Icons.play_circle_filled_rounded;
        modeColor = AppColors.dailymotionBlue;
        break;
    }

    return Container(
      color: AppColors.surfaceElevated,
      padding: const EdgeInsets.fromLTRB(6, 6, 8, 8),
      child: SafeArea(
        bottom: false,
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
                // Tombol Kembali (Back to previous screen/dialog)
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: AppColors.textPrimary, size: 22),
                  onPressed: () async {
                    await _pauseWebViewMedia();
                    if (mounted) {
                      setState(() => _canPop = true);
                      Navigator.of(context).pop();
                    }
                  },
                  tooltip: 'Kembali',
                ),
                Container(
                  padding: const EdgeInsets.all(6),
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
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              modeTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (widget.mode == DailymotionBrowserMode.queueOnly) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AppColors.primaryNeon.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'ANTREAN',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryNeon,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        _isSupportedMobilePlatform ? _currentUrl : modeSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Navigation Actions: Halaman Sebelumnya (Web Back) & Muat Ulang
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
                    onPressed: () => _webViewController?.reload(),
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textSecondary, size: 20),
                  tooltip: 'Tutup',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await _pauseWebViewMedia();
                    if (mounted) {
                      setState(() => _canPop = true);
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectedVideoFloatingBanner() {
    return Material(
      color: Colors.transparent,
      elevation: 14,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              AppColors.surfaceHighlight,
              AppColors.surfaceElevated,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.dailymotionBlue.withValues(alpha: 0.85),
            width: 1.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.75),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: AppColors.dailymotionBlue.withValues(alpha: 0.28),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.dailymotionBlue.withValues(alpha: 0.65),
                      width: 1.2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.5),
                    child: Container(
                      width: 86,
                      height: 52,
                      color: Colors.black45,
                      child: _detectedThumbnail != null &&
                              _detectedThumbnail!.isNotEmpty
                          ? Image.network(
                              _detectedThumbnail!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Center(
                                child: Icon(
                                  Icons.play_circle_filled_rounded,
                                  color: AppColors.dailymotionBlue,
                                  size: 26,
                                ),
                              ),
                            )
                          : const Center(
                              child: Icon(
                                Icons.play_circle_filled_rounded,
                                color: AppColors.dailymotionBlue,
                                size: 26,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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
                                    size: 12, color: AppColors.accentGreen),
                                SizedBox(width: 4),
                                Text(
                                  'SIAP DIPILIH',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.accentGreen,
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
                              color: AppColors.dailymotionBlue
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_circle_filled_rounded,
                                    size: 12, color: AppColors.dailymotionBlue),
                                SizedBox(width: 4),
                                Text(
                                  'Dailymotion',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.dailymotionBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _detectedTitle.isNotEmpty
                            ? _detectedTitle
                            : 'Video Dailymotion',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 20, color: AppColors.textSecondary),
                  onPressed: () {
                    setState(() {
                      _dismissedVideoUrl = _detectedVideoUrl;
                      _detectedVideoUrl = null;
                    });
                  },
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Pilih Video Lain',
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    if (widget.mode == DailymotionBrowserMode.createRoom) {
      return Container(
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
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => _handleVideoSelection('createRoom'),
          icon: const Icon(Icons.check_circle_rounded,
              size: 21, color: Colors.white),
          label: const Text(
            'Pilih Video Ini & Buat Room',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ),
      );
    }

    if (widget.mode == DailymotionBrowserMode.queueOnly) {
      return Container(
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
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () => _handleVideoSelection('queue'),
          icon: const Icon(Icons.playlist_add_rounded,
              size: 22, color: Colors.white),
          label: const Text(
            '+ Pilih & Tambah ke Antrean',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ),
      );
    }

    // Default / watchNow mode
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Container(
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => _handleVideoSelection('watchNow'),
              icon: const Icon(Icons.play_circle_fill_rounded,
                  size: 22, color: Colors.white),
              label: Text(
                widget.queueController != null
                    ? 'Pilih & Putar'
                    : 'Pilih & Putar Video Ini',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
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
              height: 48,
              child: OutlinedButton.icon(
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
                onPressed: () => _handleVideoSelection('queue'),
                icon: const Icon(Icons.playlist_add_rounded, size: 19),
                label: const Text(
                  '+ Antrean',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  bool _isValidDailymotionUrl(String url) {
    return DailymotionPlayerController.extractVideoId(url) != null;
  }

  void _handleManualFallbackSubmit() async {
    final url = _fallbackUrlController.text.trim();
    if (url.isEmpty) return;

    if (!_isValidDailymotionUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL Dailymotion tidak valid!'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    final videoId = DailymotionPlayerController.extractVideoId(url)!;
    final canonicalUrl = 'https://www.dailymotion.com/video/$videoId';
    final resolved = await VideoTitleResolver.resolveTitle(
      canonicalUrl,
      mediaType: 'dailymotion',
    );
    final clean = VideoTitleResolver.cleanTitle(resolved);

    setState(() {
      _detectedVideoUrl = canonicalUrl;
      _detectedTitle = clean.isNotEmpty ? clean : 'Video Dailymotion';
      _detectedThumbnail = 'https://www.dailymotion.com/thumbnail/video/$videoId';
    });

    _handleVideoSelection(widget.mode == DailymotionBrowserMode.watchNow ? 'watchNow' : 'play');
  }

  void _handleManualFallbackQueue() async {
    final url = _fallbackUrlController.text.trim();
    if (url.isEmpty) return;

    if (!_isValidDailymotionUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL Dailymotion tidak valid!'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    final videoId = DailymotionPlayerController.extractVideoId(url)!;
    final canonicalUrl = 'https://www.dailymotion.com/video/$videoId';
    final resolved = await VideoTitleResolver.resolveTitle(
      canonicalUrl,
      mediaType: 'dailymotion',
    );
    final clean = VideoTitleResolver.cleanTitle(resolved);

    setState(() {
      _detectedVideoUrl = canonicalUrl;
      _detectedTitle = clean.isNotEmpty ? clean : 'Video Dailymotion';
      _detectedThumbnail = 'https://www.dailymotion.com/thumbnail/video/$videoId';
    });

    _handleVideoSelection('queue');
  }

  Widget _buildDesktopFallback() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.dailymotionBlue.withValues(alpha: 0.15),
                  border: Border.all(color: AppColors.dailymotionBlue.withValues(alpha: 0.35)),
                ),
                child: const Icon(
                  Icons.play_circle_filled_rounded,
                  color: AppColors.dailymotionBlue,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Tempel Tautan Dailymotion',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Buka browser favorit Anda, salin tautan video Dailymotion, dan tempelkan di bawah ini:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _fallbackUrlController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'https://www.dailymotion.com/video/...',
                  prefixIcon: const Icon(Icons.link_rounded, color: AppColors.dailymotionBlue),
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
                onChanged: (val) {
                  final id = DailymotionPlayerController.extractVideoId(val);
                  if (id != null) {
                    _handleUrlInspection(val.trim());
                  }
                },
              ),
              const SizedBox(height: 16),
              if (widget.mode == DailymotionBrowserMode.queueOnly)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _handleManualFallbackQueue,
                    icon: const Icon(Icons.playlist_add_rounded, size: 20),
                    label: const Text(
                      '+ Tambahkan ke Antrean',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.primaryNeonDark,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                )
              else if (widget.mode == DailymotionBrowserMode.createRoom)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _handleManualFallbackSubmit,
                    icon: const Icon(Icons.meeting_room_rounded, size: 20),
                    label: const Text(
                      'Buka Room dengan Video Ini',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.primaryNeonDark,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: Text(
                          widget.mode == DailymotionBrowserMode.watchNow
                              ? 'Putar Sekarang di Room'
                              : 'Tonton Video Ini',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: AppColors.primaryNeonDark,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    if (widget.queueController != null) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: OutlinedButton.icon(
                          onPressed: _handleManualFallbackQueue,
                          icon: const Icon(Icons.playlist_add_rounded, size: 18),
                          label: const Text(
                            'Antrean',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
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
