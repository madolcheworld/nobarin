import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../browser/presentation/bstation_browser_sheet.dart';
import '../../../browser/presentation/youtube_browser_sheet.dart';
import '../../../chat/controllers/chat_controller.dart';
import '../../controllers/queue_controller.dart';
import '../../controllers/sync_controller.dart';
import '../../controllers/unified_player_controller.dart';

/// Clean, modern, and user-friendly Media Source Picker for Direct URL video.
class MediaSourcePicker extends StatefulWidget {
  final SyncController syncController;
  final ChatController? chatController;
  final QueueController? queueController;
  final bool isAddingToQueueInitial;

  const MediaSourcePicker({
    super.key,
    required this.syncController,
    this.chatController,
    this.queueController,
    this.isAddingToQueueInitial = false,
  });

  /// Displays [MediaSourcePicker] as a modern modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required SyncController syncController,
    ChatController? chatController,
    QueueController? queueController,
    bool isAddingToQueueInitial = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MediaSourcePicker(
        syncController: syncController,
        chatController: chatController,
        queueController: queueController,
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

  @override
  void initState() {
    super.initState();
    if (!widget.isAddingToQueueInitial) {
      _urlController.text = widget.syncController.player.mediaUrl;
      final detected =
          UnifiedPlayerController.detectMediaFromUrl(_urlController.text);
      if (detected != null) {
        _titleController.text = detected.title;
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _applyMedia() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final detected = UnifiedPlayerController.detectMediaFromUrl(url);
    final type = detected?.mediaType ?? 'direct_url';

    widget.syncController.requestChangeMedia(type, url);
    widget.chatController?.sendSystemMessage(
      '${widget.syncController.currentUser.username} mengubah video.',
    );
    Navigator.of(context).pop();
  }

  void _addToQueue() {
    final url = _urlController.text.trim();
    if (url.isEmpty || widget.queueController == null) return;

    final detected = UnifiedPlayerController.detectMediaFromUrl(url);
    final type = detected?.mediaType ?? 'direct_url';

    var title = _titleController.text.trim();
    if (title.isEmpty) {
      title = detected?.title ?? 'Video Antrean';
    }

    widget.queueController!.addToQueue(
      mediaType: type,
      mediaUrl: url,
      title: title,
    );

    Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final currentUrl = _urlController.text.trim();
    final bool canProceed = currentUrl.isNotEmpty;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: AppColors.border, width: 1),
            ),
          ),
          padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottomInset),
          child: SingleChildScrollView(
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
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textSecondary, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Tutup',
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // YouTube In-App Browser Option Card
                Material(
                  color: Colors.transparent,
                  child: InkWell(
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
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.youtubeRed.withValues(alpha: 0.18),
                            AppColors.surfaceElevated,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.youtubeRed.withValues(alpha: 0.45),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: AppColors.youtubeRed,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.isAddingToQueueInitial
                                      ? 'Cari YouTube untuk Antrean'
                                      : 'Jelajahi YouTube (In-App)',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.isAddingToQueueInitial
                                      ? 'Buka browser YouTube & tambahkan video ke antrean'
                                      : 'Buka browser, cari & putar video langsung',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Bstation In-App Browser Option Card
                Material(
                  color: Colors.transparent,
                  child: InkWell(
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
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.bstationBlue.withValues(alpha: 0.18),
                            AppColors.surfaceElevated,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.bstationBlue.withValues(alpha: 0.45),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: AppColors.bstationBlue,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.tv_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.isAddingToQueueInitial
                                      ? 'Cari Bstation untuk Antrean'
                                      : 'Jelajahi Bstation (In-App)',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.isAddingToQueueInitial
                                      ? 'Buka browser Bstation & tambahkan video ke antrean'
                                      : 'Buka browser, cari & tonton anime/video langsung',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    const Expanded(child: Divider(color: AppColors.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'atau masukkan link langsung',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const Expanded(child: Divider(color: AppColors.border)),
                  ],
                ),

                const SizedBox(height: 14),

                // URL Input Field
                const Text(
                  'URL Video (YouTube / Bstation / MP4 / HLS / WebM)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _urlController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'https://youtube.com/... atau https://bilibili.tv/... atau direct video',
                    prefixIcon: const Icon(Icons.link_rounded,
                        color: AppColors.secondaryNeon, size: 20),
                    filled: true,
                    fillColor: AppColors.surfaceElevated,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
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
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Masukkan judul video...',
                    prefixIcon: const Icon(Icons.title_rounded,
                        color: AppColors.textSecondary, size: 20),
                    filled: true,
                    fillColor: AppColors.surfaceElevated,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Primary & Secondary Actions
                if (widget.isAddingToQueueInitial) ...[
                  ElevatedButton.icon(
                    onPressed: canProceed ? _addToQueue : null,
                    icon: const Icon(Icons.playlist_add_rounded, size: 18),
                    label: const Text('Tambahkan ke Antrean'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: AppColors.primaryNeon,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ] else ...[
                  // Play Now Button
                  ElevatedButton.icon(
                    onPressed: canProceed ? _applyMedia : null,
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text(
                      'Putar Sekarang',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: AppColors.primaryNeon,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  if (widget.queueController != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: canProceed ? _addToQueue : null,
                      icon: const Icon(Icons.playlist_add_rounded, size: 17),
                      label: const Text('Tambahkan ke Antrean Saja'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryNeon,
                        side: BorderSide(
                          color: canProceed
                              ? AppColors.primaryNeon
                              : AppColors.border,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
