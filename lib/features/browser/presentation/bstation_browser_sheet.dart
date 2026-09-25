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

  Future<void> _resolveTitleBackground(String url) async {
    try {
      final resolved = await VideoTitleResolver.resolveTitle(url, mediaType: 'bstation');
      final clean = VideoTitleResolver.cleanTitle(resolved);
      if (clean.isNotEmpty && mounted && _detectedVideoUrl == url) {
        if (_detectedTitle != clean) {
          setState(() {
            _detectedTitle = clean;
          });
        }
      }
    } catch (_) {}
  }

  /// Injects JavaScript to observe SPA navigation & video elements on Bstation
  Future<void> _injectSpaDetector() async {
    if (_webViewController == null) return;

    const script = '''
      (function() {
        function cleanTitleStr(str) {
          if (!str) return '';
          var s = str.trim();
          if (/^\\d+\$/.test(s)) return '';
          s = s.replace(/\\s*[-|_]\\s*(Bilibili|Bstation).*\$/i, '');
          s = s.replace(/\\s*\\|\\s*(Bilibili|Bstation).*\$/i, '');
          s = s.replace(/\\s*HD\\s*\\|\\s*bilibili.*\$/i, '');
          s = s.trim();
          if (/^\\d+\$/.test(s)) return '';
          if (s.toLowerCase() === 'bstation' || s.toLowerCase() === 'bilibili') return '';
          return s;
        }

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
              var thumbnail = '';

              // 1. Check window.__initialState (rich OGV anime & UGC metadata)
              try {
                if (window.__initialState && window.__initialState.ogv) {
                  var ogv = window.__initialState.ogv;
                  var sTitle = (ogv.season && ogv.season.title) || '';
                  var epTitle = '';
                  var epId = ogv.epId || '';
                  var epMatch = url.match(/\\/play\\/\\d+\\/(\\d+)/);
                  if (epMatch) epId = epMatch[1];

                  if (ogv.season && ogv.season.sectionsList) {
                    for (var i = 0; i < ogv.season.sectionsList.length; i++) {
                      var sec = ogv.season.sectionsList[i];
                      if (sec && sec.episodes) {
                        for (var j = 0; j < sec.episodes.length; j++) {
                          var ep = sec.episodes[j];
                          if (ep.episode_id == epId || (!epId && i === 0 && j === 0)) {
                            epTitle = ep.title_display || ep.long_title_display || ep.short_title_display || '';
                            if (ep.cover) thumbnail = ep.cover;
                            break;
                          }
                        }
                      }
                      if (epTitle) break;
                    }
                  }
                  if (sTitle && epTitle) {
                    title = sTitle + ' - ' + epTitle;
                  } else if (sTitle) {
                    title = sTitle;
                  } else if (epTitle) {
                    title = epTitle;
                  }
                }

                if (!title && window.__initialState && window.__initialState.ugc) {
                  var ugc = window.__initialState.ugc;
                  if (ugc.archive && ugc.archive.title) {
                    title = ugc.archive.title;
                    if (ugc.archive.cover) thumbnail = ugc.archive.cover;
                  }
                }
              } catch(e) {}

              // 2. Check document.title
              if (!title) {
                var docT = cleanTitleStr(document.title);
                if (docT) title = docT;
              }

              // 3. Check DOM elements
              if (!title) {
                var metaTitleEl = document.querySelector('.bstar-meta__title');
                var activeEpEl = document.querySelector('.ep-item--active, .ep-item.active, [class*="ep-item--active"]');
                if (metaTitleEl && metaTitleEl.textContent && activeEpEl) {
                  var sName = metaTitleEl.textContent.trim();
                  var eName = activeEpEl.getAttribute('title') || activeEpEl.textContent.trim();
                  if (sName && eName && !/^\\d+\$/.test(eName)) {
                    title = sName + ' - ' + eName;
                  } else if (sName) {
                    title = sName;
                  }
                }
              }

              if (!title) {
                var titleEl = document.querySelector('.video-info__title') ||
                              document.querySelector('.bstar-meta__title') ||
                              document.querySelector('.ep-info__title');
                if (titleEl && titleEl.textContent) {
                  var t = cleanTitleStr(titleEl.textContent);
                  if (t) title = t;
                }
              }

              if (!title) {
                var ogTitle = document.querySelector('meta[property="og:title"]');
                if (ogTitle && ogTitle.content) {
                  var t = cleanTitleStr(ogTitle.content);
                  if (t) title = t;
                }
              }

              title = cleanTitleStr(title);

              if (!thumbnail) {
                var ogImage = document.querySelector('meta[property="og:image"]');
                if (ogImage && ogImage.content) {
                  thumbnail = ogImage.content;
                }
                if (!thumbnail && v && v.getAttribute('poster')) {
                  thumbnail = v.getAttribute('poster');
                }
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

        if (!window.__nobarBstationDetectorInitialized) {
          window.__nobarBstationDetectorInitialized = true;

          var origPushState = history.pushState;
          history.pushState = function() {
            origPushState.apply(this, arguments);
            setTimeout(reportBstationState, 250);
            setTimeout(reportBstationState, 750);
            setTimeout(reportBstationState, 1500);
          };

          var origReplaceState = history.replaceState;
          history.replaceState = function() {
            origReplaceState.apply(this, arguments);
            setTimeout(reportBstationState, 250);
            setTimeout(reportBstationState, 750);
          };

          window.addEventListener('popstate', function() {
            setTimeout(reportBstationState, 250);
            setTimeout(reportBstationState, 750);
          });

          try {
            var observer = new MutationObserver(function() {
              reportBstationState();
            });
            if (document.head) {
              observer.observe(document.head, { subtree: true, characterData: true, childList: true });
            }
            if (document.body) {
              observer.observe(document.body, { childList: true, subtree: true });
            }
          } catch(e) {}

          setInterval(reportBstationState, 1200);
        }

        reportBstationState();
        setTimeout(reportBstationState, 300);
        setTimeout(reportBstationState, 800);
        setTimeout(reportBstationState, 1800);

        function injectClutterStyles() {
          try {
            if (document.getElementById('nobar-bstation-clutter-style')) return;
            var style = document.createElement('style');
            style.id = 'nobar-bstation-clutter-style';
            style.textContent = `
              html, body {
                overflow-y: auto !important;
                position: static !important;
                touch-action: pan-y !important;
                -webkit-overflow-scrolling: touch !important;
              }
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

            // Restore scroll capability if blocked by Bilibili dialog scripts
            if (document.body) {
              if (document.body.style.overflow === 'hidden') {
                document.body.style.overflow = 'auto';
              }
              if (document.body.style.position === 'fixed') {
                document.body.style.position = 'static';
              }
              document.body.classList.remove('dialog-open', 'modal-open', 'overflow-hidden', 'bstar-modal-open');
            }
            if (document.documentElement) {
              if (document.documentElement.style.overflow === 'hidden') {
                document.documentElement.style.overflow = 'auto';
              }
              document.documentElement.classList.remove('dialog-open', 'modal-open', 'overflow-hidden', 'bstar-modal-open');
            }
          } catch(e) {}
        }
        cleanBstationClutter();
        setInterval(cleanBstationClutter, 600);
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
      final cleanExtracted = VideoTitleResolver.cleanTitle(extractedTitle);

      String title = cleanExtracted;
      if (title.isEmpty) {
        if (_detectedTitle.isNotEmpty &&
            _detectedTitle != 'Video Bstation' &&
            _detectedTitle != 'Memuat judul video...') {
          title = _detectedTitle;
        } else {
          title = 'Memuat judul video...';
        }
        _resolveTitleBackground(url);
      }

      String? thumb = extractedThumbnail?.trim();
      if (thumb != null && thumb.isEmpty) thumb = null;

      if (mounted &&
          (_detectedVideoUrl != url ||
              (_detectedTitle != title && title != 'Memuat judul video...') ||
              (_detectedTitle == 'Memuat judul video...' && title != 'Memuat judul video...'))) {
        setState(() {
          _detectedVideoUrl = url;
          _detectedTitle = title;
          if (thumb != null) {
            _detectedThumbnail = thumb;
          }
        });
      } else if (mounted && _detectedVideoUrl != url) {
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

    final title = (_detectedTitle.isNotEmpty && _detectedTitle != 'Memuat judul video...')
        ? _detectedTitle
        : 'Video Bstation';

    await _pauseWebViewMedia();

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

    final title = (_detectedTitle.isNotEmpty && _detectedTitle != 'Memuat judul video...')
        ? _detectedTitle
        : 'Video Bstation';

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

  void _handleManualFallbackSubmit() async {
    final rawUrl = _fallbackUrlController.text.trim();
    if (rawUrl.isEmpty) return;

    final url = rawUrl.startsWith('http') ? rawUrl : 'https://$rawUrl';

    if (!_isValidBstationUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL Bstation / Bilibili tidak valid!'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    final resolved = await VideoTitleResolver.resolveTitle(url, mediaType: 'bstation');
    final clean = VideoTitleResolver.cleanTitle(resolved);

    setState(() {
      _detectedVideoUrl = url;
      _detectedTitle = clean.isNotEmpty ? clean : 'Video Bstation';
    });

    _applyWatchNow();
  }

  void _handleManualFallbackQueue() async {
    final rawUrl = _fallbackUrlController.text.trim();
    if (rawUrl.isEmpty) return;

    final url = rawUrl.startsWith('http') ? rawUrl : 'https://$rawUrl';

    if (!_isValidBstationUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL Bstation / Bilibili tidak valid!'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    final resolved = await VideoTitleResolver.resolveTitle(url, mediaType: 'bstation');
    final clean = VideoTitleResolver.cleanTitle(resolved);

    setState(() {
      _detectedVideoUrl = url;
      _detectedTitle = clean.isNotEmpty ? clean : 'Video Bstation';
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

              // Docked Detection Bar (Bottom Action Bar with smooth size animation)
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: _detectedVideoUrl != null
                    ? _buildDetectionBanner(context)
                    : const SizedBox.shrink(),
              ),
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
              color: AppColors.bstationBlue.withValues(alpha: 0.75),
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
                  color: AppColors.bstationBlue.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.tv_rounded,
                  color: AppColors.bstationBlue,
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
                    color: AppColors.bstationBlue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.bstationBlue.withValues(alpha: 0.65),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Pilih Video',
                        style: TextStyle(
                          color: AppColors.bstationBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 3),
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
            color: AppColors.bstationBlue.withValues(alpha: 0.85),
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
            color: AppColors.bstationBlue.withValues(alpha: 0.22),
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
                      color: AppColors.bstationBlue.withValues(alpha: 0.6),
                      width: 1.2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.5),
                    child: _detectedThumbnail != null &&
                            _detectedThumbnail!.isNotEmpty
                        ? Image.network(
                            _detectedThumbnail!,
                            width: 86,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              width: 86,
                              height: 52,
                              color:
                                  AppColors.bstationBlue.withValues(alpha: 0.2),
                              child: const Icon(Icons.tv_rounded,
                                  color: AppColors.bstationBlue, size: 24),
                            ),
                          )
                        : Container(
                            width: 86,
                            height: 52,
                            color:
                                AppColors.bstationBlue.withValues(alpha: 0.2),
                            child: const Icon(Icons.tv_rounded,
                                color: AppColors.bstationBlue, size: 24),
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
                              color: AppColors.bstationBlue
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.tv_rounded,
                                    color: AppColors.bstationBlue, size: 12),
                                SizedBox(width: 4),
                                Text(
                                  'Bstation',
                                  style: TextStyle(
                                    color: AppColors.bstationBlue,
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

            const SizedBox(height: 12),

            // Action Buttons per Mode
            if (widget.mode == BstationBrowserMode.queueOnly) ...[
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
            ] else if (widget.mode == BstationBrowserMode.createRoom) ...[
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
            ] else if (widget.mode == BstationBrowserMode.watchNow) ...[
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
              else if (widget.mode == BstationBrowserMode.createRoom)
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
                          widget.mode == BstationBrowserMode.watchNow
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
                    if (widget.queueController != null &&
                        widget.mode != BstationBrowserMode.watchNow) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: OutlinedButton.icon(
                          onPressed: _handleManualFallbackQueue,
                          icon: const Icon(Icons.playlist_add_rounded, size: 18),
                          label: const Text(
                            '+ Antrean',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
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
