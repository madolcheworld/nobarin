import 'package:flutter/material.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../chat/controllers/chat_controller.dart';
import '../../controllers/sync_controller.dart';
import '../../controllers/unified_player_controller.dart';

class MediaSourcePicker extends StatefulWidget {
  final SyncController syncController;
  final ChatController? chatController;

  const MediaSourcePicker({
    super.key,
    required this.syncController,
    this.chatController,
  });

  @override
  State<MediaSourcePicker> createState() => _MediaSourcePickerState();
}

class _MediaSourcePickerState extends State<MediaSourcePicker> {
  final TextEditingController _urlController = TextEditingController();
  String _selectedType = 'direct_url'; // 'direct_url' or 'youtube'

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.syncController.player.mediaUrl;
    _selectedType = widget.syncController.player.mediaType;
    _urlController.addListener(_onUrlChanged);
  }

  void _onUrlChanged() {
    final text = _urlController.text.trim();
    if (UnifiedPlayerController.extractYouTubeVideoId(text) != null &&
        _selectedType != 'youtube') {
      setState(() => _selectedType = 'youtube');
    } else if ((text.endsWith('.mp4') ||
            text.endsWith('.m3u8') ||
            text.endsWith('.webm')) &&
        _selectedType != 'direct_url') {
      setState(() => _selectedType = 'direct_url');
    }
  }

  @override
  void dispose() {
    _urlController.removeListener(_onUrlChanged);
    _urlController.dispose();
    super.dispose();
  }

  void _applyMedia() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    var type = _selectedType;
    if (UnifiedPlayerController.extractYouTubeVideoId(url) != null) {
      type = 'youtube';
    } else if (type == 'youtube' &&
        (url.endsWith('.mp4') ||
            url.endsWith('.m3u8') ||
            url.endsWith('.webm'))) {
      type = 'direct_url';
    }

    widget.syncController.requestChangeMedia(type, url);
    widget.chatController?.sendSystemMessage(
      '${widget.syncController.currentUser.username} mengubah video.',
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryNeon.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.video_library_rounded,
                      color: AppColors.secondaryNeon,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Ganti Sumber Video',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Segment Type Selector
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      avatar: const Icon(Icons.video_collection_rounded, size: 16),
                      label: const Text('Direct URL', style: TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      selected: _selectedType == 'direct_url',
                      selectedColor: AppColors.secondaryNeon.withValues(alpha: 0.25),
                      side: BorderSide(
                        color: _selectedType == 'direct_url'
                            ? AppColors.secondaryNeon
                            : AppColors.border,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedType = 'direct_url');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      avatar: const Icon(Icons.play_circle_fill, size: 16),
                      label: const Text('YouTube', style: TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      selected: _selectedType == 'youtube',
                      selectedColor: AppColors.accentRed.withValues(alpha: 0.25),
                      side: BorderSide(
                        color: _selectedType == 'youtube'
                            ? AppColors.accentRed
                            : AppColors.border,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedType = 'youtube');
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // URL Input
              TextField(
                controller: _urlController,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: _selectedType == 'youtube'
                      ? 'Link Video YouTube'
                      : 'URL Video Langsung (MP4 / HLS .m3u8)',
                  prefixIcon: Icon(
                    _selectedType == 'youtube'
                        ? Icons.link_rounded
                        : Icons.movie_outlined,
                    color: _selectedType == 'youtube'
                        ? AppColors.accentRed
                        : AppColors.secondaryNeon,
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Preset Options
              const Text(
                'Video Rekomendasi / Uji Coba:',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ApiConstants.presetMedia
                    .where((m) => m['type'] == _selectedType)
                    .map((m) {
                  return ActionChip(
                    label: Text(m['title']!,
                        style: const TextStyle(fontSize: 11)),
                    backgroundColor: AppColors.surfaceElevated,
                    side: const BorderSide(color: AppColors.border),
                    onPressed: () {
                      _urlController.text = m['url']!;
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _applyMedia,
                      child: const Text('Putar Video'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
