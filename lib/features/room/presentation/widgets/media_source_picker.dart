import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/p2p_file_stream_service.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../core/utils/input_validators.dart';
import '../../../../core/utils/video_title_resolver.dart';
import '../../../../core/widgets/nobarin_button.dart';
import '../../../../core/widgets/video_source_card.dart';
import '../../../browser/presentation/bstation_browser_sheet.dart';
import '../../../browser/presentation/dailymotion_browser_sheet.dart';
import '../../../browser/presentation/google_drive_browser_sheet.dart';
import '../../../browser/presentation/web_browser_sheet.dart';
import '../../../browser/presentation/youtube_browser_sheet.dart';
import '../../../chat/controllers/chat_controller.dart';
import '../../../screenshare/controllers/webrtc_screenshare_controller.dart';
import '../../controllers/queue_controller.dart';
import '../../controllers/sync_controller.dart';
import '../../controllers/unified_player_controller.dart';

/// Clean, modern, and user-friendly Media Source Picker for Direct URL video.
class MediaSourcePicker extends StatefulWidget {
  final SyncController syncController;
  final ChatController? chatController;
  final QueueController? queueController;
  final WebRtcScreenShareController? screenShareController;
  final bool isAddingToQueueInitial;

  const MediaSourcePicker({
    super.key,
    required this.syncController,
    this.chatController,
    this.queueController,
    this.screenShareController,
    this.isAddingToQueueInitial = false,
  });

  /// Displays [MediaSourcePicker] as a modern modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required SyncController syncController,
    ChatController? chatController,
    QueueController? queueController,
    WebRtcScreenShareController? screenShareController,
    bool isAddingToQueueInitial = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (ctx) => MediaSourcePicker(
        syncController: syncController,
        chatController: chatController,
        queueController: queueController,
        screenShareController: screenShareController,
        isAddingToQueueInitial: isAddingToQueueInitial,
      ),
    );
  }

  @override
  State<MediaSourcePicker> createState() => _MediaSourcePickerState();
}

class _MediaSourcePickerState extends State<MediaSourcePicker> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  Timer? _debounceTimer;
  int _resolveRequestId = 0;
  bool _isResolvingTitle = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isAddingToQueueInitial) {
      final currentUrl = widget.syncController.player.mediaUrl;
      final isLocalOrLoopback = currentUrl.startsWith('http://127.0.0.1') ||
          currentUrl.startsWith('p2p://') ||
          UnifiedPlayerController.isLocalFilePath(currentUrl) ||
          (P2PFileStreamService.instance.activeMetadata != null &&
              currentUrl ==
                  P2PFileStreamService
                      .instance.activeMetadata?.lanUrl);
      if (currentUrl.isNotEmpty &&
          currentUrl != 'screenshare' &&
          !isLocalOrLoopback) {
        _urlController.text = currentUrl;
        final detected =
            UnifiedPlayerController.detectMediaFromUrl(currentUrl);
        if (detected != null) {
          _titleController.text = detected.title;
        }
        _resolveTitleForUrl(currentUrl);
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _onUrlChanged(String value) {
    setState(() {});
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _debounceTimer?.cancel();
      return;
    }

    final detected = UnifiedPlayerController.detectMediaFromUrl(trimmed);
    if (detected != null) {
      final currentTitle = _titleController.text.trim();
      final isPlaceholder = currentTitle.isEmpty ||
          currentTitle == 'Video YouTube' ||
          currentTitle == 'Video Bstation' ||
          currentTitle == 'Video Dailymotion' ||
          currentTitle == 'Video Google Drive' ||
          currentTitle == 'Video Web Browser' ||
          currentTitle == 'Video Stream';
      if (isPlaceholder) {
        _titleController.text = detected.title;
      }
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        _resolveTitleForUrl(trimmed);
      }
    });
  }

  Future<void> _resolveTitleForUrl(String url) async {
    final requestId = ++_resolveRequestId;
    setState(() => _isResolvingTitle = true);

    try {
      final resolved = await VideoTitleResolver.resolveTitle(url);
      if (!mounted || requestId != _resolveRequestId) return;

      if (resolved != null && resolved.trim().isNotEmpty) {
        final currentTitle = _titleController.text.trim();
        final isPlaceholder = currentTitle.isEmpty ||
            currentTitle == 'Video YouTube' ||
            currentTitle == 'Video Bstation' ||
            currentTitle == 'Video Dailymotion' ||
            currentTitle == 'Video Google Drive' ||
            currentTitle == 'Video Web Browser' ||
            currentTitle == 'Video Stream' ||
            currentTitle.startsWith('Video YouTube (') ||
            currentTitle.startsWith('Video Bstation (') ||
            currentTitle.startsWith('Video Dailymotion (') ||
            currentTitle.startsWith('Video Google Drive (') ||
            currentTitle.startsWith('Video Web Browser (') ||
            RegExp(r'^\d+$').hasMatch(currentTitle);

        if (isPlaceholder) {
          _titleController.text = resolved;
        }
      }
    } catch (e) {
      debugPrint('[MediaSourcePicker] Failed to resolve title: $e');
    } finally {
      if (mounted && requestId == _resolveRequestId) {
        setState(() => _isResolvingTitle = false);
      }
    }
  }

  void _applyMedia() {
    if (!widget.syncController.canControl) {
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
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    if (!InputValidators.isValidMediaUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Format atau protokol URL video tidak didukung.'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    final detected = UnifiedPlayerController.detectMediaFromUrl(url);
    final type = detected?.mediaType ?? 'direct_url';

    widget.syncController.requestChangeMedia(type, url);
    final title = _titleController.text.trim();
    if (title.isNotEmpty &&
        title != 'Video YouTube' &&
        title != 'Video Bstation' &&
        title != 'Video Dailymotion' &&
        title != 'Video Google Drive' &&
        title != 'Video Web Browser' &&
        title != 'Video Stream') {
      widget.chatController?.sendSystemMessage(
        '${widget.syncController.currentUser.username} memutar "$title".',
      );
    } else {
      widget.chatController?.sendSystemMessage(
        '${widget.syncController.currentUser.username} mengubah video.',
      );
    }
    Navigator.of(context).pop();
  }

  Future<void> _pickLocalFile() async {
    try {
      if (!widget.isAddingToQueueInitial && !widget.syncController.canControl) {
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

      final picked = await FilePicker.pickFile(
        type: FileType.video,
      );
      if (picked == null) return;

      final path = kIsWeb
          ? (picked.xFile.path.isNotEmpty ? picked.xFile.path : picked.uri.toString())
          : (picked.path ?? (picked.xFile.path.isNotEmpty ? picked.xFile.path : ''));
      if (path.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File tidak memiliki path atau URL yang valid di perangkat ini.'),
              backgroundColor: AppColors.accentRed,
            ),
          );
        }
        return;
      }

      final fileName = picked.name;
      int fileLength = 0;
      try {
        fileLength = picked.lengthSync() ?? await picked.length();
      } catch (_) {}
      final sizeMb = (fileLength / (1024 * 1024)).toStringAsFixed(1);

      if (widget.isAddingToQueueInitial) {
        widget.queueController?.addToQueue(
          mediaType: 'direct_url',
          mediaUrl: path,
          title: fileName,
        );
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.playlist_add_check_rounded, color: Colors.black),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '"$fileName" ditambahkan ke antrean!',
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
            ),
          );
        }
        return;
      }

      // Host file for P2P direct streaming on native platforms (LAN + WebRTC)
      if (!kIsWeb) {
        await P2PFileStreamService.instance.hostFile(
          filePath: path,
          hostUserId: widget.syncController.currentUser.id,
          hostUserName: widget.syncController.currentUser.username,
        );
      }

      widget.syncController.requestChangeMedia('direct_url', path);
      widget.chatController?.sendSystemMessage(
        '${widget.syncController.currentUser.username} memutar file lokal: $fileName ($sizeMb MB).',
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  kIsWeb ? Icons.play_circle_fill_rounded : Icons.stream_rounded,
                  color: Colors.black,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kIsWeb
                        ? 'Memutar File Lokal: $fileName ($sizeMb MB)'
                        : 'Streaming P2P: $fileName ($sizeMb MB)',
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
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('[MediaSourcePicker] Error picking local file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memilih file video: $e'),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    }
  }

  Future<void> _handleScreenShare(WebRtcScreenShareController controller) async {
    if (controller.isSharing) {
      AppHaptics.medium();
      Navigator.of(context).pop();
      await controller.stopScreenShare();
      return;
    }

    if (controller.isScreenSharingActive) {
      AppHaptics.selection();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.secondaryNeon),
          ),
          content: Row(
            children: [
              const Icon(Icons.personal_video_rounded,
                  color: AppColors.secondaryNeon, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${controller.sharerName ?? "Peserta lain"} sedang berbagi layar.',
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 12),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (!controller.canShareScreen) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.accentYellow),
          ),
          content: const Row(
            children: [
              Icon(Icons.lock_rounded, color: AppColors.accentYellow, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Hanya Host yang dapat membagikan layar pada mode Host Only.',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    AppHaptics.medium();
    Navigator.of(context).pop();
    final success = await controller.startScreenShare();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.accentRed),
          ),
          content: Text(
            controller.errorMessage ?? 'Tidak dapat memulai berbagi layar.',
            style: const TextStyle(color: AppColors.accentRed, fontSize: 12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildScreenShareCard(
    BuildContext context,
    WebRtcScreenShareController controller,
  ) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final isSharing = controller.isSharing;
        final isScreenSharingActive = controller.isScreenSharingActive;
        final sharerName = controller.sharerName ?? 'Peserta lain';

        final Color accentColor = isSharing
            ? AppColors.accentRed
            : AppColors.secondaryNeon;

        final String title = isSharing
            ? 'Hentikan Mirror Layar'
            : (isScreenSharingActive
                ? 'Mirror Layar Sedang Aktif'
                : 'Mirror Layar / Bagikan Layar');

        final String subtitle = isSharing
            ? 'Layar Anda sedang disiarkan ke semua peserta'
            : (isScreenSharingActive
                ? 'Disiarkan oleh $sharerName'
                : 'Siarkan layar perangkat Anda secara langsung via WebRTC');

        final IconData icon = isSharing
            ? Icons.stop_screen_share_rounded
            : (isScreenSharingActive
                ? Icons.personal_video_rounded
                : Icons.mobile_screen_share_rounded);

        final String badgeLabel = isSharing
            ? 'Sedang Siaran'
            : (isScreenSharingActive ? 'Aktif' : 'Real-time');

        return VideoSourceFeatureCard(
          title: title,
          subtitle: subtitle,
          icon: icon,
          iconColor: Colors.white,
          iconBackgroundColor: accentColor,
          accentColor: accentColor,
          badgeText: badgeLabel,
          trailingIcon: isSharing
              ? Icons.close_rounded
              : Icons.arrow_forward_ios_rounded,
          onTap: () => _handleScreenShare(controller),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final currentUrl = _urlController.text.trim();
    final bool canProceed = currentUrl.isNotEmpty;
    final bool canControl = widget.syncController.canControl;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Drag Handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 4, bottom: 12),
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textSecondary.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Clean Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: widget.isAddingToQueueInitial
                              ? AppColors.primaryNeon.withValues(alpha: 0.15)
                              : AppColors.secondaryNeon.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.isAddingToQueueInitial
                              ? Icons.queue_music_rounded
                              : Icons.video_library_rounded,
                          color: widget.isAddingToQueueInitial
                              ? AppColors.primaryNeon
                              : AppColors.secondaryNeon,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.isAddingToQueueInitial
                              ? 'Tambah ke Antrean'
                              : 'Ganti Sumber Video',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      NobarinModalIconButton(
                        icon: Icons.close_rounded,
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Tutup',
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 2-Column Bento Card Grid for Video Sources
                  VideoSourceGrid(
                    spacing: 12,
                    children: [
                      // 1. YouTube Option Card
                      VideoSourceCard(
                        title: widget.isAddingToQueueInitial
                            ? 'Cari di YouTube'
                            : 'YouTube',
                        subtitle: widget.isAddingToQueueInitial
                            ? 'Pilih video untuk antrean'
                            : 'Jelajahi video di YouTube',
                        icon: Icons.smart_display_rounded,
                        iconColor: Colors.white,
                        iconBackgroundColor: AppColors.youtubeRed,
                        accentColor: AppColors.youtubeRed,
                        badgeText: 'Populer',
                        onTap: () {
                          Navigator.of(context).pop();
                          YouTubeBrowserSheet.show(
                            context,
                            syncController: widget.syncController,
                            queueController: widget.queueController,
                            chatController: widget.chatController,
                            mode: widget.isAddingToQueueInitial
                                ? YouTubeBrowserMode.queueOnly
                                : YouTubeBrowserMode.watchNow,
                          );
                        },
                      ),

                      // 2. Bstation Option Card
                      VideoSourceCard(
                        title: widget.isAddingToQueueInitial
                            ? 'Cari di Bstation'
                            : 'Bstation / Bilibili',
                        subtitle: widget.isAddingToQueueInitial
                            ? 'Pilih anime untuk antrean'
                            : 'Jelajahi anime dan serial video',
                        icon: Icons.tv_rounded,
                        iconColor: Colors.white,
                        iconBackgroundColor: AppColors.bstationBlue,
                        accentColor: AppColors.bstationBlue,
                        badgeText: 'Anime',
                        onTap: () {
                          Navigator.of(context).pop();
                          BstationBrowserSheet.show(
                            context,
                            syncController: widget.syncController,
                            queueController: widget.queueController,
                            chatController: widget.chatController,
                            mode: widget.isAddingToQueueInitial
                                ? BstationBrowserMode.queueOnly
                                : BstationBrowserMode.watchNow,
                          );
                        },
                      ),

                      // 3. Web Browser (Auto-Detect Video) Option Card
                      VideoSourceCard(
                        title: widget.isAddingToQueueInitial
                            ? 'Cari di Web Browser'
                            : 'Web Browser',
                        subtitle: widget.isAddingToQueueInitial
                            ? 'Buka situs & deteksi video antrean'
                            : 'Jelajahi web & deteksi otomatis video',
                        icon: Icons.public_rounded,
                        iconColor: Colors.black,
                        iconBackgroundColor: AppColors.webBrowserTeal,
                        accentColor: AppColors.webBrowserTeal,
                        badgeText: 'Auto-Detect',
                        onTap: () {
                          Navigator.of(context).pop();
                          WebBrowserSheet.show(
                            context,
                            syncController: widget.syncController,
                            queueController: widget.queueController,
                            chatController: widget.chatController,
                            mode: widget.isAddingToQueueInitial
                                ? WebBrowserMode.queueOnly
                                : WebBrowserMode.watchNow,
                          );
                        },
                      ),

                      // 4. Google Drive Option Card
                      VideoSourceCard(
                        title: widget.isAddingToQueueInitial
                            ? 'Pilih dari Google Drive'
                            : 'Google Drive',
                        subtitle: widget.isAddingToQueueInitial
                            ? 'Pilih video Drive untuk antrean'
                            : 'Login & putar video dari Google Drive',
                        icon: Icons.add_to_drive_rounded,
                        iconColor: Colors.white,
                        iconBackgroundColor: AppColors.googleDriveGreen,
                        accentColor: AppColors.googleDriveGreen,
                        badgeText: 'Drive',
                        onTap: () {
                          Navigator.of(context).pop();
                          GoogleDriveBrowserSheet.show(
                            context,
                            syncController: widget.syncController,
                            queueController: widget.queueController,
                            chatController: widget.chatController,
                            mode: widget.isAddingToQueueInitial
                                ? GoogleDriveBrowserMode.queueOnly
                                : GoogleDriveBrowserMode.watchNow,
                          );
                        },
                      ),

                      // 5. Dailymotion Option Card
                      VideoSourceCard(
                        title: widget.isAddingToQueueInitial
                            ? 'Cari di Dailymotion'
                            : 'Dailymotion',
                        subtitle: widget.isAddingToQueueInitial
                            ? 'Pilih video untuk antrean'
                            : 'Jelajahi video di Dailymotion',
                        icon: Icons.play_circle_filled_rounded,
                        iconColor: Colors.white,
                        iconBackgroundColor: AppColors.dailymotionBlue,
                        accentColor: AppColors.dailymotionBlue,
                        badgeText: 'Trending',
                        onTap: () {
                          Navigator.of(context).pop();
                          DailymotionBrowserSheet.show(
                            context,
                            syncController: widget.syncController,
                            queueController: widget.queueController,
                            chatController: widget.chatController,
                            mode: widget.isAddingToQueueInitial
                                ? DailymotionBrowserMode.queueOnly
                                : DailymotionBrowserMode.watchNow,
                          );
                        },
                      ),

                      // 6. Local Video File (Direct P2P Streaming) Option Card
                      VideoSourceCard(
                        title: widget.isAddingToQueueInitial
                            ? 'File Video Lokal'
                            : 'File Video Lokal (P2P)',
                        subtitle: widget.isAddingToQueueInitial
                            ? 'Pilih video dari perangkat'
                            : 'Stream langsung dari HP/PC tanpa upload',
                        icon: Icons.folder_special_rounded,
                        iconColor: Colors.white,
                        iconBackgroundColor: AppColors.p2pPurple,
                        accentColor: AppColors.p2pPurple,
                        badgeText: 'Langsung',
                        onTap: _pickLocalFile,
                      ),
                    ],
                  ),

                  if (!widget.isAddingToQueueInitial &&
                      widget.screenShareController != null) ...[
                    const SizedBox(height: 12),
                    _buildScreenShareCard(context, widget.screenShareController!),
                  ],

                  if (!widget.isAddingToQueueInitial) ...[
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        const Expanded(child: Divider(color: AppColors.border)),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'atau tempel link',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider(color: AppColors.border)),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // URL Input Field
                    const Text(
                      'Link Video / Stream',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _urlController,
                      maxLength: 2048,
                      buildCounter:
                          (
                            _, {
                            required currentLength,
                            required isFocused,
                            required maxLength,
                          }) => null,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Tempel tautan video di sini...',
                        prefixIcon: const Icon(Icons.link_rounded,
                            color: AppColors.secondaryNeon, size: 20),
                        suffixIcon: _urlController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: AppColors.textSecondary,
                                  size: 18,
                                ),
                                tooltip: 'Hapus tautan',
                                onPressed: () {
                                  _urlController.clear();
                                  _titleController.clear();
                                  _onUrlChanged('');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: AppColors.surfaceElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                      ),
                      onChanged: _onUrlChanged,
                    ),

                    const SizedBox(height: 12),

                    // Title Input Field
                    const Text(
                      'Judul Video (Opsional)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _titleController,
                      maxLength: 100,
                      buildCounter:
                          (
                            _, {
                            required currentLength,
                            required isFocused,
                            required maxLength,
                          }) => null,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Masukkan judul video...',
                        prefixIcon: const Icon(Icons.title_rounded,
                            color: AppColors.textSecondary, size: 20),
                        suffixIcon: _isResolvingTitle
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        AppColors.primaryNeon),
                                  ),
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: AppColors.surfaceElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Play Now Button
                    NobarinPrimaryButton(
                      label: !canControl ? 'Kontrol Dikunci Host' : 'Putar Sekarang',
                      icon: !canControl ? Icons.lock_rounded : Icons.play_arrow_rounded,
                      fontSize: 15,
                      onPressed: (canProceed && canControl) ? _applyMedia : null,
                    ),
                  ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
