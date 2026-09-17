import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/p2p_file_stream_service.dart';
import '../../../../core/utils/video_title_resolver.dart';
import '../../../browser/presentation/bstation_browser_sheet.dart';
import '../../../browser/presentation/dailymotion_browser_sheet.dart';
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
  int _resolveRequestId = 0;
  bool _isResolvingTitle = false;

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
      if (_urlController.text.isNotEmpty) {
        _resolveTitleForUrl(_urlController.text);
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _onUrlChanged(String value) {
    setState(() {});
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    final detected = UnifiedPlayerController.detectMediaFromUrl(trimmed);
    if (detected != null && _titleController.text.trim().isEmpty) {
      _titleController.text = detected.title;
    }

    _resolveTitleForUrl(trimmed);
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
            currentTitle == 'Video Stream' ||
            currentTitle.startsWith('Video YouTube (') ||
            currentTitle.startsWith('Video Bstation (') ||
            currentTitle.startsWith('Video Dailymotion (') ||
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
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final detected = UnifiedPlayerController.detectMediaFromUrl(url);
    final type = detected?.mediaType ?? 'direct_url';

    widget.syncController.requestChangeMedia(type, url);
    final title = _titleController.text.trim();
    if (title.isNotEmpty &&
        title != 'Video YouTube' &&
        title != 'Video Bstation' &&
        title != 'Video Dailymotion' &&
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

  Future<void> _pickLocalFile() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.video,
      );
      if (picked == null) return;

      final path = picked.path;
      if (path == null || path.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File tidak memiliki path yang valid di perangkat ini.'),
              backgroundColor: AppColors.accentRed,
            ),
          );
        }
        return;
      }

      final fileName = picked.name;
      final fileLength = await picked.length();
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

      // Host file for P2P direct streaming
      await P2PFileStreamService.instance.hostFile(
        filePath: path,
        hostUserId: widget.syncController.currentUser.id,
        hostUserName: widget.syncController.currentUser.username,
      );

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
                const Icon(Icons.stream_rounded, color: Colors.black),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Streaming P2P: $fileName ($sizeMb MB)',
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
                                      ? 'Cari di YouTube'
                                      : 'YouTube',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.isAddingToQueueInitial
                                      ? 'Pilih video untuk antrean'
                                      : 'Jelajahi video di YouTube',
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
                                      ? 'Cari di Bstation'
                                      : 'Bstation / Bilibili',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.isAddingToQueueInitial
                                      ? 'Pilih anime untuk antrean'
                                      : 'Jelajahi anime dan serial video',
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

                // Dailymotion In-App Browser Option Card
                Material(
                  color: Colors.transparent,
                  child: InkWell(
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
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.dailymotionBlue.withValues(alpha: 0.18),
                            AppColors.surfaceElevated,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.dailymotionBlue.withValues(alpha: 0.45),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: AppColors.dailymotionBlue,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_circle_filled_rounded,
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
                                      ? 'Cari di Dailymotion'
                                      : 'Dailymotion',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.isAddingToQueueInitial
                                      ? 'Pilih video untuk antrean'
                                      : 'Jelajahi video di Dailymotion',
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

                // Local Video File (Direct P2P Streaming) Option Card
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _pickLocalFile,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.purpleAccent.withValues(alpha: 0.18),
                            AppColors.surfaceElevated,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.purpleAccent.withValues(alpha: 0.5),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Colors.purpleAccent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.folder_special_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      widget.isAddingToQueueInitial
                                          ? 'File Video Lokal'
                                          : 'File Video Lokal (P2P)',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.purpleAccent.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Langsung',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.purpleAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.isAddingToQueueInitial
                                      ? 'Pilih video dari penyimpanan perangkat'
                                      : 'Stream langsung dari file HP/PC tanpa upload',
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
                        'atau tempel link',
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
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Tempel tautan video di sini...',
                    prefixIcon: const Icon(Icons.link_rounded,
                        color: AppColors.secondaryNeon, size: 20),
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
