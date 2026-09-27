import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/video_title_resolver.dart';
import '../../../core/widgets/nobarin_button.dart';
import '../../chat/controllers/chat_controller.dart';
import '../../room/controllers/queue_controller.dart';
import '../../room/controllers/sync_controller.dart';
import '../../room/controllers/vimeo_player_controller.dart';

/// Mode operasional untuk In-App Browser Vimeo
enum VimeoBrowserMode {
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

/// In-App Browser sheet that enables users to browse Vimeo (vimeo.com),
/// automatically detects when a video is clicked or navigated to,
/// and provides instant actions to "Tonton Sekarang" or "Tambah ke Antrean".
class VimeoBrowserSheet extends StatefulWidget {
  final SyncController? syncController;
  final QueueController? queueController;
  final ChatController? chatController;
  final void Function(String type, String url, String title)? onVideoSelected;
  final VimeoBrowserMode mode;

  const VimeoBrowserSheet({
    super.key,
    this.syncController,
    this.queueController,
    this.chatController,
    this.onVideoSelected,
    this.mode = VimeoBrowserMode.general,
  });

  /// Displays [VimeoBrowserSheet] as a full-height modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    SyncController? syncController,
    QueueController? queueController,
    ChatController? chatController,
    void Function(String type, String url, String title)? onVideoSelected,
    VimeoBrowserMode mode = VimeoBrowserMode.general,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      enableDrag: false,
      builder: (ctx) => VimeoBrowserSheet(
        syncController: syncController,
        queueController: queueController,
        chatController: chatController,
        onVideoSelected: onVideoSelected,
        mode: mode,
      ),
    );
  }

  @override
  State<VimeoBrowserSheet> createState() => _VimeoBrowserSheetState();
}

class _VimeoBrowserSheetState extends State<VimeoBrowserSheet> {
  WebViewController? _webViewController;
  bool _isLoading = true;
  double _loadProgress = 0.0;
  String _currentUrl = 'https://vimeo.com/watch';
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
          'NobarVimeoDetector',
          onMessageReceived: (message) {
            _handleDetectorMessage(message.message);
          },
        )
        ..loadRequest(Uri.parse('https://vimeo.com/watch'));

      _webViewController = controller;
    } catch (e) {
      debugPrint('[VimeoBrowser] Error initializing WebView: $e');
      _isLoading = false;
    }
  }

  void _handleUrlInspection(String url) {
    if (!mounted) return;
    _currentUrl = url;

    final videoId = VimeoPlayerController.extractVideoId(url);
    if (videoId != null && videoId.isNotEmpty) {
      final canonicalUrl = 'https://vimeo.com/$videoId';

      if (_dismissedVideoUrl == canonicalUrl) return;

      if (_detectedVideoUrl != canonicalUrl) {
        setState(() {
          _detectedVideoUrl = canonicalUrl;
          _detectedTitle = 'Video Vimeo ($videoId)';
          _detectedThumbnail = null;
        });

        _resolveTitle(canonicalUrl, videoId);
      }
    }
  }

  void _handleDetectorMessage(String rawMessage) {
    if (!mounted) return;
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is Map<String, dynamic>) {
        final href = decoded['url'] as String? ?? '';
        final title = decoded['title'] as String? ?? '';
        final thumb = decoded['thumbnail'] as String? ?? '';

        final videoId = VimeoPlayerController.extractVideoId(href);
        if (videoId != null && videoId.isNotEmpty) {
          final canonicalUrl = 'https://vimeo.com/$videoId';

          if (_dismissedVideoUrl == canonicalUrl) return;

          setState(() {
            _detectedVideoUrl = canonicalUrl;
            if (title.isNotEmpty) {
              final clean = VideoTitleResolver.cleanTitle(title);
              _detectedTitle = clean.isNotEmpty ? clean : title;
            } else if (_detectedTitle.isEmpty ||
                _detectedTitle.startsWith('Video Vimeo (')) {
              _detectedTitle = 'Video Vimeo ($videoId)';
            }
            if (thumb.isNotEmpty) {
              _detectedThumbnail = thumb;
            }
          });

          if (_detectedTitle.isEmpty || _detectedTitle.startsWith('Video Vimeo (')) {
            _resolveTitle(canonicalUrl, videoId);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _injectSpaDetector() async {
    if (_webViewController == null) return;
    final script = '''
      (function() {
        if (window.__nobarVimeoHooked) return;
        window.__nobarVimeoHooked = true;

        function checkVideoPage() {
          var currentUrl = window.location.href;
          var match = currentUrl.match(/vimeo\\.com\\/(?:channels\\/[^\\/]+\\/|groups\\/[^\\/]+\\/videos\\/|manage\\/videos\\/)?([0-9]{4,})/);
          if (match && match[1]) {
            var title = '';
            var titleEl = document.querySelector('h1') || document.querySelector('meta[property="og:title"]');
            if (titleEl) {
              title = titleEl.getAttribute('content') || titleEl.innerText || '';
            }
            var thumb = '';
            var thumbEl = document.querySelector('meta[property="og:image"]');
            if (thumbEl) {
              thumb = thumbEl.getAttribute('content') || '';
            }

            if (window.NobarVimeoDetector && window.NobarVimeoDetector.postMessage) {
              window.NobarVimeoDetector.postMessage(JSON.stringify({
                url: currentUrl,
                title: title.trim(),
                thumbnail: thumb.trim()
              }));
            }
          }
        }

        var origPushState = history.pushState;
        history.pushState = function() {
          origPushState.apply(this, arguments);
          setTimeout(checkVideoPage, 350);
        };

        var origReplaceState = history.replaceState;
        history.replaceState = function() {
          origReplaceState.apply(this, arguments);
          setTimeout(checkVideoPage, 350);
        };

        window.addEventListener('popstate', function() {
          setTimeout(checkVideoPage, 350);
        });

        checkVideoPage();
        setInterval(checkVideoPage, 1500);
      })();
    ''';

    try {
      await _webViewController!.runJavaScript(script);
    } catch (_) {}
  }

  Future<void> _resolveTitle(String url, String videoId) async {
    try {
      final resolved = await VideoTitleResolver.resolveTitle(
        url,
        mediaType: 'vimeo',
      );
      if (!mounted) return;
      if (resolved != null && resolved.isNotEmpty) {
        setState(() {
          _detectedTitle = resolved;
        });
      }
    } catch (_) {}
  }

  void _dismissCurrentDetection() {
    setState(() {
      _dismissedVideoUrl = _detectedVideoUrl;
      _detectedVideoUrl = null;
      _detectedTitle = '';
      _detectedThumbnail = null;
    });
  }

  void _handleVideoSelection(String action) {
    final url = _detectedVideoUrl;
    if (url == null || url.isEmpty) return;

    final title = _detectedTitle.isNotEmpty ? _detectedTitle : 'Video Vimeo';

    if (action == 'queue' || widget.mode == VimeoBrowserMode.queueOnly) {
      widget.queueController?.addToQueue(
        mediaType: 'vimeo',
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
          backgroundColor: AppColors.vimeoBlue,
          duration: const Duration(seconds: 3),
        ),
      );

      _dismissCurrentDetection();

      if (widget.mode == VimeoBrowserMode.queueOnly) {
        setState(() => _canPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
      return;
    }

    if (widget.syncController != null) {
      widget.syncController!.requestChangeMedia('vimeo', url);
      widget.chatController?.sendSystemMessage(
        '${widget.syncController!.currentUser.username} memutar "$title" dari Vimeo.',
      );
    }
    widget.onVideoSelected?.call('vimeo', url, title);
    setState(() => _canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _handlePop() async {
    if (_webViewController != null && await _webViewController!.canGoBack()) {
      await _webViewController!.goBack();
      return;
    }
    if (mounted) {
      setState(() => _canPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _webViewController == null || _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handlePop();
        }
      },
      child: Container(
        height: MediaQuery.of(context).size.height * 0.92,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              // Top Bar
              _buildTopBar(),

              // Progress Bar
              if (_isLoading)
                LinearProgressIndicator(
                  value: _loadProgress > 0 ? _loadProgress : null,
                  backgroundColor: AppColors.surfaceElevated,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.vimeoBlue,
                  ),
                  minHeight: 2.5,
                ),

              // Content Area (WebView on Mobile or Fallback on Web/Desktop)
              Expanded(
                child: Stack(
                  children: [
                    if (_isSupportedMobilePlatform && _webViewController != null)
                      WebViewWidget(
                        controller: _webViewController!,
                        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
                          Factory<VerticalDragGestureRecognizer>(VerticalDragGestureRecognizer.new),
                          Factory<HorizontalDragGestureRecognizer>(HorizontalDragGestureRecognizer.new),
                          Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
                        },
                      )
                    else
                      _buildFallbackInputView(),

                    // Detected Video Floating Bar
                    if (_detectedVideoUrl != null)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: _buildDetectedVideoBar(),
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
    final Color modeColor;

    switch (widget.mode) {
      case VimeoBrowserMode.createRoom:
        modeTitle = 'Pilih Video Vimeo';
        modeSubtitle = 'Pilih video Vimeo untuk buat room';
        modeColor = AppColors.vimeoBlue;
        break;
      case VimeoBrowserMode.queueOnly:
        modeTitle = 'Tambah ke Antrean (Vimeo)';
        modeSubtitle = 'Pilih video Vimeo untuk antrean';
        modeColor = AppColors.primaryNeon;
        break;
      case VimeoBrowserMode.watchNow:
        modeTitle = 'Ganti Video Room';
        modeSubtitle = 'Pilih video Vimeo untuk diputar';
        modeColor = AppColors.vimeoBlue;
        break;
      case VimeoBrowserMode.general:
        modeTitle = 'Vimeo';
        modeSubtitle = 'Jelajahi video & tonton bersama';
        modeColor = AppColors.vimeoBlue;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: modeColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(
                  child: Icon(
                    Icons.play_circle_filled_rounded,
                    color: modeColor,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modeTitle,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      _isSupportedMobilePlatform && _webViewController != null
                          ? _currentUrl
                          : modeSubtitle,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: modeColor == AppColors.primaryNeon
                            ? AppColors.primaryNeonLight
                            : AppColors.textSecondary,
                        fontWeight: modeColor == AppColors.primaryNeon
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (_isSupportedMobilePlatform && _webViewController != null) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded, size: 16),
                  color: AppColors.textSecondary,
                  tooltip: 'Kembali',
                  onPressed: () async {
                    if (await _webViewController!.canGoBack()) {
                      _webViewController!.goBack();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  color: AppColors.textSecondary,
                  tooltip: 'Muat ulang',
                  onPressed: () {
                    _webViewController!.reload();
                  },
                ),
              ],
              NobarinModalIconButton(
                icon: Icons.close_rounded,
                onPressed: _handlePop,
                tooltip: 'Tutup',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetectedVideoBar() {
    final title = _detectedTitle.isNotEmpty ? _detectedTitle : 'Video Vimeo';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.vimeoBlue.withValues(alpha: 0.85),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: AppColors.vimeoBlue.withValues(alpha: 0.28),
            blurRadius: 12,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.vimeoBlue.withValues(alpha: 0.65),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _detectedThumbnail != null
                    ? Image.network(
                        _detectedThumbnail!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Center(
                          child: Icon(
                            Icons.play_circle_filled_rounded,
                            color: AppColors.vimeoBlue,
                            size: 22,
                          ),
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.play_circle_filled_rounded,
                          color: AppColors.vimeoBlue,
                          size: 22,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.vimeoBlue.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppColors.vimeoBlue.withValues(alpha: 0.4),
                              width: 0.8,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.video_library_rounded,
                                  size: 12, color: AppColors.vimeoBlue),
                              SizedBox(width: 4),
                              Text(
                                'Vimeo',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.vimeoBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Video Terdeteksi',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: AppColors.textSecondary,
                tooltip: 'Abaikan',
                onPressed: _dismissCurrentDetection,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (widget.mode == VimeoBrowserMode.createRoom) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.vimeoBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () => _handleVideoSelection('createRoom'),
                    icon: const Icon(Icons.check_circle_rounded, size: 16),
                    label: const Text(
                      'Pilih Video Ini',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ] else if (widget.mode == VimeoBrowserMode.queueOnly) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryNeon,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () => _handleVideoSelection('queue'),
                    icon: const Icon(Icons.playlist_add_rounded, size: 16),
                    label: const Text(
                      '+ Tambahkan ke Antrean',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.vimeoBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () => _handleVideoSelection(
                      widget.mode == VimeoBrowserMode.watchNow ? 'watchNow' : 'play',
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(
                      widget.mode == VimeoBrowserMode.watchNow
                          ? 'Putar Sekarang di Room'
                          : 'Tonton Sekarang',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                if (widget.mode == VimeoBrowserMode.general && widget.queueController != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryNeonLight,
                        side: BorderSide(
                          color: AppColors.primaryNeon.withValues(alpha: 0.6),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => _handleVideoSelection('queue'),
                      icon: const Icon(Icons.playlist_add_rounded, size: 16),
                      label: const Text(
                        '+ Antrean',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ],
      ),
    );
  }

  bool _isValidVimeoUrl(String url) {
    return VimeoPlayerController.extractVideoId(url) != null;
  }

  void _onFallbackSubmit() {
    final url = _fallbackUrlController.text.trim();
    if (url.isEmpty) return;

    if (!_isValidVimeoUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL Vimeo tidak valid! Contoh: https://vimeo.com/76979871'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    final videoId = VimeoPlayerController.extractVideoId(url)!;
    final canonicalUrl = 'https://vimeo.com/$videoId';

    setState(() {
      _detectedVideoUrl = canonicalUrl;
      final clean = VideoTitleResolver.cleanTitle(_detectedTitle);
      _detectedTitle = clean.isNotEmpty ? clean : 'Video Vimeo';
      _detectedThumbnail = null;
    });

    _handleVideoSelection(widget.mode == VimeoBrowserMode.watchNow ? 'watchNow' : 'play');
  }

  void _onFallbackQueueSubmit() {
    final url = _fallbackUrlController.text.trim();
    if (url.isEmpty) return;

    if (!_isValidVimeoUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL Vimeo tidak valid! Contoh: https://vimeo.com/76979871'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    final videoId = VimeoPlayerController.extractVideoId(url)!;
    final canonicalUrl = 'https://vimeo.com/$videoId';

    setState(() {
      _detectedVideoUrl = canonicalUrl;
      final clean = VideoTitleResolver.cleanTitle(_detectedTitle);
      _detectedTitle = clean.isNotEmpty ? clean : 'Video Vimeo';
      _detectedThumbnail = null;
    });

    _handleVideoSelection('queue');
  }

  Widget _buildFallbackInputView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.vimeoBlue.withValues(alpha: 0.15),
                  border: Border.all(color: AppColors.vimeoBlue.withValues(alpha: 0.35)),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.play_circle_filled_rounded,
                    color: AppColors.vimeoBlue,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Tempel Tautan Vimeo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Buka browser favorit Anda, salin tautan video Vimeo, dan tempelkan di bawah ini:',
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
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'https://vimeo.com/76979871...',
                  prefixIcon: const Icon(Icons.link_rounded, color: AppColors.vimeoBlue),
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
                onSubmitted: (_) => _onFallbackSubmit(),
                onChanged: (val) {
                  final id = VimeoPlayerController.extractVideoId(val);
                  if (id != null) {
                    _resolveTitle('https://vimeo.com/$id', id);
                  }
                },
              ),
              const SizedBox(height: 16),
              if (widget.mode == VimeoBrowserMode.queueOnly)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryNeon,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _onFallbackQueueSubmit,
                    icon: const Icon(Icons.playlist_add_rounded),
                    label: const Text(
                      '+ Tambahkan ke Antrean',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                )
              else if (widget.mode == VimeoBrowserMode.createRoom)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.vimeoBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _onFallbackSubmit,
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text(
                      'Pilih Video Ini',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.vimeoBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _onFallbackSubmit,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          widget.mode == VimeoBrowserMode.watchNow
                              ? 'Putar Sekarang'
                              : 'Tonton Sekarang',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    if (widget.queueController != null) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryNeonLight,
                            side: BorderSide(
                              color: AppColors.primaryNeon.withValues(alpha: 0.6),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _onFallbackQueueSubmit,
                          icon: const Icon(Icons.playlist_add_rounded),
                          label: const Text(
                            '+ Antrean',
                            style: TextStyle(fontWeight: FontWeight.bold),
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
