import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/video_title_resolver.dart';
import '../../chat/controllers/chat_controller.dart';
import '../../room/controllers/google_drive_player_controller.dart';
import '../../room/controllers/queue_controller.dart';
import '../../room/controllers/sync_controller.dart';

/// Mode operasional untuk In-App Browser Google Drive
enum GoogleDriveBrowserMode {
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

/// In-App Browser sheet that enables users to browse Google Drive,
/// automatically detects when a video file is clicked or previewed,
/// and provides instant actions to "Tonton Bareng Sekarang" or "Tambah ke Antrean".
class GoogleDriveBrowserSheet extends StatefulWidget {
  final SyncController? syncController;
  final QueueController? queueController;
  final ChatController? chatController;
  final void Function(String type, String url, String title)? onVideoSelected;
  final GoogleDriveBrowserMode mode;

  const GoogleDriveBrowserSheet({
    super.key,
    this.syncController,
    this.queueController,
    this.chatController,
    this.onVideoSelected,
    this.mode = GoogleDriveBrowserMode.general,
  });

  /// Displays [GoogleDriveBrowserSheet] as a full-height modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    SyncController? syncController,
    QueueController? queueController,
    ChatController? chatController,
    void Function(String type, String url, String title)? onVideoSelected,
    GoogleDriveBrowserMode mode = GoogleDriveBrowserMode.general,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      enableDrag: false,
      builder: (ctx) => GoogleDriveBrowserSheet(
        syncController: syncController,
        queueController: queueController,
        chatController: chatController,
        onVideoSelected: onVideoSelected,
        mode: mode,
      ),
    );
  }

  @override
  State<GoogleDriveBrowserSheet> createState() => _GoogleDriveBrowserSheetState();
}

class _GoogleDriveBrowserSheetState extends State<GoogleDriveBrowserSheet> {
  WebViewController? _webViewController;
  bool _isLoading = true;
  double _loadProgress = 0.0;
  String _currentUrl = 'https://drive.google.com/drive/u/0/my-drive';
  String? _detectedVideoUrl;
  String? _detectedFileId;
  String _detectedTitle = '';
  bool _isBannerMinimized = false;
  String? _dismissedFileId;
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
          'NobarGdriveDetector',
          onMessageReceived: (message) {
            _handleDetectorMessage(message.message);
          },
        )
        ..loadRequest(Uri.parse('https://drive.google.com/drive/u/0/my-drive'));

      _webViewController = controller;
    } catch (_) {
      _isLoading = false;
    }
  }

  Future<void> _resolveTitleBackground(String fileId) async {
    try {
      final resolved = await VideoTitleResolver.resolveTitle(
        'https://drive.google.com/file/d/$fileId/view',
        mediaType: 'google_drive',
      );
      final clean = VideoTitleResolver.cleanTitle(resolved);
      if (clean.isNotEmpty && mounted && _detectedFileId == fileId) {
        if (_detectedTitle != clean) {
          setState(() {
            _detectedTitle = clean;
          });
        }
      }
    } catch (_) {}
  }

  /// Injects JavaScript to observe SPA navigation & video preview dialogs in Google Drive
  Future<void> _injectSpaDetector() async {
    if (_webViewController == null) return;

    const script = '''
      (function() {
        function cleanTitleStr(str) {
          if (!str) return '';
          var s = str.trim();
          if (/^\\d+\$/.test(s)) return '';
          s = s.replace(/^Video\\s+/i, '');
          s = s.replace(/^Menampilkan\\s+/i, '');
          s = s.replace(/\\s*[-|_–—]\\s*(Google Drive|Google Dokumen).*\$/i, '');
          s = s.trim();
          if (/^\\d+\$/.test(s)) return '';
          if (s.toLowerCase() === 'google drive') return '';
          return s;
        }

        var videoExtensions = /\\.(mp4|mkv|webm|avi|mov|flv|wmv|m4v|ts|3gp|ogv|mpg|mpeg)(\\?.*)?\$/i;

        function postVideoDetected(fileId, title) {
          if (!fileId) return;
          var cleanT = cleanTitleStr(title) || 'Video Google Drive';
          if (window.NobarGdriveDetector) {
            window.NobarGdriveDetector.postMessage(JSON.stringify({
              url: 'https://drive.google.com/file/d/' + fileId + '/view',
              fileId: fileId,
              title: cleanT,
              isVideo: true
            }));
          }
        }

        function extractInfoFromCard(card) {
          if (!card) return null;
          var fileId = card.getAttribute('data-id') || card.getAttribute('data-item-id') || card.getAttribute('data-entry-id');
          if (!fileId) {
            var child = card.querySelector('[data-id]');
            if (child) fileId = child.getAttribute('data-id');
          }
          if (!fileId && card.parentElement) {
            var p = card.parentElement.closest('[data-id]');
            if (p) fileId = p.getAttribute('data-id');
          }
          if (!fileId) return null;

          var targetType = card.getAttribute('data-target');
          if (targetType === 'folder') return null;

          var linkEl = card.querySelector('[aria-label], [role="link"]') || card;
          var rawLabel = linkEl.getAttribute('aria-label') || card.getAttribute('aria-label') || '';
          var text = card.innerText || card.textContent || '';

          var isVideo = false;
          var title = rawLabel;

          if (/^Video\\s+/i.test(rawLabel)) {
            isVideo = true;
            title = rawLabel.replace(/^Video\\s+/i, '');
          }

          if (videoExtensions.test(rawLabel) || videoExtensions.test(text)) {
            isVideo = true;
            if (!title || !videoExtensions.test(title)) {
              title = text;
            }
          }

          if (!isVideo) return null;

          return { fileId: fileId, title: title.trim(), isVideo: true };
        }

        function handleUserInteraction(e) {
          try {
            var el = e.target;
            if (!el) return;

            // 1. Look for closest card or item with data-id
            var card = el.closest('[data-id], [data-target], [role="row"], [role="gridcell"], [role="option"], .a-N-Pf-Q, .a-N-Pf-q');
            if (card) {
              var info = extractInfoFromCard(card);
              if (info && info.fileId) {
                postVideoDetected(info.fileId, info.title);
                return;
              }
            }

            // 2. Check if clicked item is an anchor tag with /file/d/ or ?id=
            var anchor = el.closest('a[href]');
            if (anchor) {
              var href = anchor.getAttribute('href') || '';
              var m = href.match(/\\/file\\/d\\/([a-zA-Z0-9_-]{20,})/i) ||
                      href.match(/[?&]id=([a-zA-Z0-9_-]{20,})/i);
              if (m && m[1]) {
                var aTitle = anchor.getAttribute('aria-label') || anchor.title || anchor.innerText || '';
                postVideoDetected(m[1], aTitle);
                return;
              }
            }
          } catch(err) {}
        }

        function scanViewerIframe() {
          try {
            var vIfr = document.querySelector('iframe.h3t5Od, iframe[src*="viewer"]');
            if (!vIfr) return;
            var idoc = vIfr.contentWindow ? vIfr.contentWindow.document : null;
            if (!idoc) return;

            // Attach interaction listeners inside viewer iframe
            if (!vIfr.__nobarListenersAttached) {
              vIfr.__nobarListenersAttached = true;
              try {
                idoc.addEventListener('click', handleUserInteraction, true);
                idoc.addEventListener('touchend', handleUserInteraction, true);
              } catch(e) {}
            }

            var fileId = '';
            var title = '';

            // Check inner youtube or driveid iframe
            var innerIframe = idoc.querySelector('iframe[src*="youtube"], iframe[src*="driveid"]');
            if (innerIframe && innerIframe.src) {
              var m = innerIframe.src.match(/driveid[%=3D]+([a-zA-Z0-9_-]{20,})/i) ||
                      innerIframe.src.match(/doc_id[%=3D"']+([a-zA-Z0-9_-]{20,})/i);
              if (m && m[1]) fileId = m[1];
            }

            // Check entire viewer iframe HTML for driveid
            if (!fileId) {
              var m2 = idoc.documentElement.outerHTML.match(/driveid[%=3D]+([a-zA-Z0-9_-]{20,})/i);
              if (m2 && m2[1]) fileId = m2[1];
            }

            // Extract title from viewer
            var tEl = idoc.querySelector('[role="heading"], div[aria-label*="Putar"], div[aria-label*="Play"]');
            if (tEl) {
              var al = tEl.getAttribute('aria-label') || '';
              title = al.replace(/^(Putar|Play)\\s+/i, '');
            }
            if (!title && idoc.body) {
              var mMenampilkan = idoc.body.innerText.match(/Menampilkan\\s+([^.\\n]+)/i);
              if (mMenampilkan) title = mMenampilkan[1].trim();
            }

            if (fileId) {
              postVideoDetected(fileId, title);
            }
          } catch(e) {}
        }

        function reportGdriveState() {
          try {
            var url = window.location.href;
            var fileId = '';
            var title = '';

            // Check URL patterns
            var m = url.match(/\\/file\\/d\\/([a-zA-Z0-9_-]{20,})/i) ||
                    url.match(/[?&]id=([a-zA-Z0-9_-]{20,})/i) ||
                    url.match(/[?&]preview=([a-zA-Z0-9_-]{20,})/i);
            if (m && m[1]) {
              fileId = m[1];
            }

            // Check for HTML5 video element
            var v = document.querySelector('video');
            var isVideo = false;
            if (v && (v.src || v.currentSrc || v.duration > 0 || v.readyState > 0)) {
              isVideo = true;
            }

            // Check document title
            var docT = cleanTitleStr(document.title);
            if (videoExtensions.test(docT) || isVideo || fileId) {
              if (docT && docT.toLowerCase() !== 'google drive') {
                title = docT;
              }
            }

            // Check DOM dialog or heading element
            if (!title) {
              var headingEl = document.querySelector('[data-target="title"]') ||
                              document.querySelector('.drive-viewer-toolstrip-name') ||
                              document.querySelector('div[role="heading"]') ||
                              document.querySelector('.a-s-fa-Ha-pa');
              if (headingEl && headingEl.textContent) {
                var t = cleanTitleStr(headingEl.textContent);
                if (t && videoExtensions.test(t)) {
                  title = t;
                  isVideo = true;
                }
              }
            }

            // Check if title ends with video extension
            if (title && videoExtensions.test(title)) {
              isVideo = true;
            }

            if (fileId && (isVideo || title)) {
              postVideoDetected(fileId, title);
              return;
            }

            // Check active / selected item in list or grid
            var selectedEl = document.querySelector('[data-id][aria-selected="true"], [role="row"][aria-selected="true"], [role="gridcell"][aria-selected="true"]');
            if (selectedEl) {
              var selInfo = extractInfoFromCard(selectedEl);
              if (selInfo && selInfo.fileId) {
                postVideoDetected(selInfo.fileId, selInfo.title);
                return;
              }
            }

            // Scan viewer iframe if present
            scanViewerIframe();
          } catch (e) {}
        }

        // Attach global interaction listeners for instant detection on tap
        document.addEventListener('click', handleUserInteraction, true);
        document.addEventListener('touchend', handleUserInteraction, true);
        document.addEventListener('dblclick', handleUserInteraction, true);

        if (!window.__nobarGdriveDetectorInitialized) {
          window.__nobarGdriveDetectorInitialized = true;

          var origPushState = history.pushState;
          history.pushState = function() {
            origPushState.apply(this, arguments);
            setTimeout(reportGdriveState, 250);
            setTimeout(reportGdriveState, 750);
            setTimeout(reportGdriveState, 1500);
          };

          var origReplaceState = history.replaceState;
          history.replaceState = function() {
            origReplaceState.apply(this, arguments);
            setTimeout(reportGdriveState, 250);
            setTimeout(reportGdriveState, 750);
          };

          window.addEventListener('popstate', function() {
            setTimeout(reportGdriveState, 250);
            setTimeout(reportGdriveState, 750);
          });

          window.addEventListener('hashchange', function() {
            setTimeout(reportGdriveState, 250);
          });

          try {
            var observer = new MutationObserver(function() {
              reportGdriveState();
            });
            if (document.body) {
              observer.observe(document.body, { childList: true, subtree: true });
            }
          } catch(e) {}

          setInterval(reportGdriveState, 1200);
        }

        reportGdriveState();
        setTimeout(reportGdriveState, 300);
        setTimeout(reportGdriveState, 800);
        setTimeout(reportGdriveState, 1800);
      })();
    ''';

    try {
      await _webViewController!.runJavaScript(script);
    } catch (_) {}
  }

  void _handleUrlInspection(String url) {
    if (!mounted) return;
    setState(() {
      _currentUrl = url;
    });

    final fileId = GoogleDrivePlayerController.extractFileId(url);
    if (fileId != null && fileId.isNotEmpty) {
      final canonicalUrl = 'https://drive.google.com/file/d/$fileId/view';
      if (_detectedFileId != fileId) {
        setState(() {
          _detectedFileId = fileId;
          _detectedVideoUrl = canonicalUrl;
          if (_detectedTitle.isEmpty || _detectedTitle == 'Video Google Drive') {
            _detectedTitle = 'Video Google Drive';
          }
          if (_dismissedFileId != fileId) {
            _isBannerMinimized = false;
          }
        });
        _resolveTitleBackground(fileId);
      }
    }
  }

  void _handleDetectorMessage(String messageJson) {
    if (!mounted) return;
    try {
      final data = jsonDecode(messageJson);
      if (data is! Map<String, dynamic>) return;

      final fileId = data['fileId'] as String?;
      final reportedTitle = data['title'] as String?;
      final rawUrl = data['url'] as String?;

      if (fileId != null && fileId.isNotEmpty) {
        final canonicalUrl = rawUrl != null && rawUrl.isNotEmpty
            ? rawUrl
            : 'https://drive.google.com/file/d/$fileId/view';

        final clean = VideoTitleResolver.cleanTitle(reportedTitle);

        debugPrint('[GoogleDriveBrowser] Video detected: $fileId ($reportedTitle)');

        setState(() {
          _detectedFileId = fileId;
          _detectedVideoUrl = canonicalUrl;
          if (clean.isNotEmpty) {
            _detectedTitle = clean;
          } else if (_detectedTitle.isEmpty) {
            _detectedTitle = 'Video Google Drive';
          }
          // Unminimize and reset dismissed state on active video selection
          _isBannerMinimized = false;
          _dismissedFileId = null;
        });

        if (clean.isEmpty) {
          _resolveTitleBackground(fileId);
        }
      }
    } catch (_) {}
  }

  Future<void> _pauseWebViewMedia() async {
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript(
          'var v = document.querySelector("video"); if (v) { v.pause(); }',
        );
      } catch (_) {}
    }
  }

  void _applySelectedVideo({bool addToQueue = false}) async {
    if (_detectedVideoUrl == null || _detectedFileId == null) return;
    await _pauseWebViewMedia();

    final title = _detectedTitle.trim().isNotEmpty
        ? _detectedTitle.trim()
        : 'Video Google Drive';

    if (!mounted) return;

    if (widget.mode == GoogleDriveBrowserMode.createRoom) {
      widget.onVideoSelected?.call('google_drive', _detectedVideoUrl!, title);
      setState(() => _canPop = true);
      Navigator.of(context).pop();
      return;
    }

    if (addToQueue || widget.mode == GoogleDriveBrowserMode.queueOnly) {
      if (widget.queueController != null) {
        widget.queueController!.addToQueue(
          mediaType: 'google_drive',
          mediaUrl: _detectedVideoUrl!,
          title: title,
        );
        if (mounted) {
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
      }
      if (mounted) {
        setState(() => _canPop = true);
        Navigator.of(context).pop();
      }
      return;
    }

    // Default: Watch Now in active room
    if (widget.syncController != null) {
      if (!widget.syncController!.canControl) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Hanya Host/Co-host yang dapat mengubah video saat kontrol dikunci.',
              ),
              backgroundColor: AppColors.accentRed,
            ),
          );
        }
        return;
      }
      widget.syncController!.requestChangeMedia('google_drive', _detectedVideoUrl!);
      widget.chatController?.sendSystemMessage(
        '${widget.syncController!.currentUser.username} memutar "$title" dari Google Drive.',
      );
    }

    widget.onVideoSelected?.call('google_drive', _detectedVideoUrl!, title);

    if (mounted) {
      setState(() => _canPop = true);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          await _pauseWebViewMedia();
          if (!context.mounted) return;
          setState(() => _canPop = true);
          Navigator.of(context).pop();
        }
      },
      child: Container(
        height: MediaQuery.of(context).size.height * 0.94,
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  color: AppColors.googleDriveGreen,
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
                    if (_detectedVideoUrl != null &&
                        _detectedFileId != _dismissedFileId)
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
      case GoogleDriveBrowserMode.createRoom:
        modeTitle = 'Pilih Video Google Drive';
        modeSubtitle = 'Pilih video Google Drive untuk buat room';
        modeIcon = Icons.meeting_room_rounded;
        modeColor = AppColors.googleDriveGreen;
        break;
      case GoogleDriveBrowserMode.queueOnly:
        modeTitle = 'Tambah ke Antrean';
        modeSubtitle = 'Pilih video Google Drive untuk antrean';
        modeIcon = Icons.playlist_add_rounded;
        modeColor = AppColors.primaryNeon;
        break;
      case GoogleDriveBrowserMode.watchNow:
        modeTitle = 'Ganti Video Room';
        modeSubtitle = 'Pilih video Google Drive untuk diputar';
        modeIcon = Icons.swap_horiz_rounded;
        modeColor = AppColors.googleDriveGreen;
        break;
      case GoogleDriveBrowserMode.general:
        modeTitle = 'Google Drive';
        modeSubtitle = 'Jelajahi & tonton video bersama';
        modeIcon = Icons.add_to_drive_rounded;
        modeColor = AppColors.googleDriveGreen;
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
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: AppColors.textPrimary,
                    size: 22,
                  ),
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
                          if (widget.mode == GoogleDriveBrowserMode.queueOnly) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryNeon.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppColors.primaryNeon.withValues(alpha: 0.35),
                                  width: 0.8,
                                ),
                              ),
                              child: const Text(
                                'Antrean',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: AppColors.primaryNeon,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        modeSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isSupportedMobilePlatform) ...[
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_rounded,
                      color: AppColors.textSecondary,
                      size: 16,
                    ),
                    onPressed: () async {
                      if (_webViewController != null &&
                          await _webViewController!.canGoBack()) {
                        await _webViewController!.goBack();
                      }
                    },
                    tooltip: 'Halaman Sebelumnya',
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: AppColors.textSecondary,
                      size: 16,
                    ),
                    onPressed: () async {
                      if (_webViewController != null &&
                          await _webViewController!.canGoBack()) {
                        await _webViewController!.goForward();
                      }
                    },
                    tooltip: 'Halaman Berikutnya',
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    onPressed: () => _webViewController?.reload(),
                    tooltip: 'Muat Ulang',
                  ),
                ],
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: () async {
                    await _pauseWebViewMedia();
                    if (mounted) {
                      setState(() => _canPop = true);
                      Navigator.of(context).pop();
                    }
                  },
                  tooltip: 'Tutup',
                ),
              ],
            ),
            const SizedBox(height: 6),
            // URL Display Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_rounded,
                    size: 12,
                    color: AppColors.googleDriveGreen,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _currentUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontFamily: 'monospace',
                      ),
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

  Widget _buildDetectedVideoFloatingBanner() {
    final titleText = _detectedTitle.trim().isNotEmpty
        ? _detectedTitle.trim()
        : 'Video Google Drive';

    if (_isBannerMinimized) {
      return Align(
        alignment: Alignment.bottomRight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _isBannerMinimized = false),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.googleDriveGreen,
                    AppColors.surfaceElevated,
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.googleDriveGreen.withValues(alpha: 0.6),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.googleDriveGreen.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.add_to_drive_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    titleText.length > 20
                        ? '${titleText.substring(0, 18)}...'
                        : titleText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.googleDriveGreen.withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: AppColors.googleDriveGreen.withValues(alpha: 0.15),
            blurRadius: 14,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: AppColors.googleDriveGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_to_drive_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.googleDriveGreen.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'GOOGLE DRIVE TERDETEKSI',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: AppColors.googleDriveGreen,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.remove_rounded, size: 18),
                color: AppColors.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _isBannerMinimized = true),
                tooltip: 'Kecilkan',
              ),
              const SizedBox(width: 10),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: AppColors.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    _dismissedFileId = _detectedFileId;
                    _detectedVideoUrl = null;
                  });
                },
                tooltip: 'Tutup Banner',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            titleText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          // Sharing reminder tip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 12,
                  color: AppColors.accentYellow,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tip: Pastikan akses file disetel ke "Siapa saja yang memiliki link" agar peserta lain dapat menonton.',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    switch (widget.mode) {
      case GoogleDriveBrowserMode.createRoom:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _applySelectedVideo(),
            icon: const Icon(Icons.check_circle_rounded, size: 16),
            label: const Text(
              'Buka Room dengan Video Ini',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.googleDriveGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        );

      case GoogleDriveBrowserMode.queueOnly:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _applySelectedVideo(addToQueue: true),
            icon: const Icon(Icons.playlist_add_rounded, size: 16),
            label: const Text(
              '+ Tambahkan ke Antrean',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryNeon,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        );

      case GoogleDriveBrowserMode.watchNow:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _applySelectedVideo(),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text(
              'Putar Sekarang di Room',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.googleDriveGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        );

      case GoogleDriveBrowserMode.general:
        return Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _applySelectedVideo(),
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: const Text(
                  'Tonton Sekarang',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.googleDriveGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _applySelectedVideo(addToQueue: true),
                icon: const Icon(Icons.playlist_add_rounded, size: 16),
                label: const Text(
                  '+ Antrean',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: BorderSide(
                    color: AppColors.primaryNeon.withValues(alpha: 0.6),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }

  void _handleManualFallbackSubmit() async {
    final text = _fallbackUrlController.text.trim();
    if (text.isEmpty) return;
    final fileId = GoogleDrivePlayerController.extractFileId(text);
    if (fileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tautan Google Drive tidak valid!'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    final canonicalUrl = 'https://drive.google.com/file/d/$fileId/view';
    final resolved = await VideoTitleResolver.resolveTitle(canonicalUrl);
    final clean = VideoTitleResolver.cleanTitle(resolved);

    setState(() {
      _detectedFileId = fileId;
      _detectedVideoUrl = canonicalUrl;
      _detectedTitle = clean.isNotEmpty ? clean : 'Video Google Drive';
    });

    _applySelectedVideo(addToQueue: false);
  }

  void _handleManualFallbackQueue() async {
    final text = _fallbackUrlController.text.trim();
    if (text.isEmpty) return;
    final fileId = GoogleDrivePlayerController.extractFileId(text);
    if (fileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tautan Google Drive tidak valid!'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    final canonicalUrl = 'https://drive.google.com/file/d/$fileId/view';
    final resolved = await VideoTitleResolver.resolveTitle(canonicalUrl);
    final clean = VideoTitleResolver.cleanTitle(resolved);

    setState(() {
      _detectedFileId = fileId;
      _detectedVideoUrl = canonicalUrl;
      _detectedTitle = clean.isNotEmpty ? clean : 'Video Google Drive';
    });

    _applySelectedVideo(addToQueue: true);
  }

  Widget _buildDesktopFallback() {
    return Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.googleDriveGreen.withValues(alpha: 0.15),
                border: Border.all(
                  color: AppColors.googleDriveGreen.withValues(alpha: 0.4),
                ),
              ),
              child: const Icon(
                Icons.add_to_drive_rounded,
                color: AppColors.googleDriveGreen,
                size: 36,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Input Tautan Video Google Drive',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Masukkan tautan video Google Drive (drive.google.com/file/d/...) yang memiliki izin akses publik atau tautan bagikan.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _fallbackUrlController,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'https://drive.google.com/file/d/.../view',
                hintStyle: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
                filled: true,
                fillColor: AppColors.surfaceElevated,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.googleDriveGreen),
                ),
              ),
              onChanged: (val) {
                final fileId = GoogleDrivePlayerController.extractFileId(val);
                if (fileId != null) {
                  setState(() {
                    _detectedFileId = fileId;
                    _detectedVideoUrl = 'https://drive.google.com/file/d/$fileId/view';
                    _detectedTitle = 'Video Google Drive';
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            if (widget.mode == GoogleDriveBrowserMode.queueOnly)
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
                    backgroundColor: AppColors.googleDriveGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              )
            else if (widget.mode == GoogleDriveBrowserMode.createRoom)
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
                    backgroundColor: AppColors.googleDriveGreen,
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
                        widget.mode == GoogleDriveBrowserMode.watchNow
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
                        backgroundColor: AppColors.googleDriveGreen,
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
                          foregroundColor: AppColors.googleDriveGreen,
                          side: const BorderSide(
                            color: AppColors.googleDriveGreen,
                            width: 1.2,
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
    );
  }
}
