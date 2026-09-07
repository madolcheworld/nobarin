import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../chat/controllers/chat_controller.dart';
import '../../../lobby/data/models/youtube_video_model.dart';
import '../../../lobby/presentation/screens/youtube_picker_screen.dart';
import '../../controllers/queue_controller.dart';
import '../../controllers/sync_controller.dart';
import '../../controllers/unified_player_controller.dart';

/// Clean, modern, and user-friendly Media Source Picker.
/// Can be used as a bottom sheet (recommended) or as a dialog.
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
  String? _thumbnailUrl;
  String _selectedType = 'youtube'; // 'youtube' or 'direct_url'
  bool _showPresets = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isAddingToQueueInitial) {
      _urlController.text = widget.syncController.player.mediaUrl;
      _selectedType = widget.syncController.player.mediaType;
    } else {
      _selectedType = 'youtube';
    }
    _urlController.addListener(_onUrlChanged);
  }

  void _onUrlChanged() {
    final text = _urlController.text.trim();
    final detectedYtId = UnifiedPlayerController.extractYouTubeVideoId(text);
    if (detectedYtId != null && _selectedType != 'youtube') {
      setState(() {
        _selectedType = 'youtube';
        _thumbnailUrl = 'https://img.youtube.com/vi/$detectedYtId/mqdefault.jpg';
      });
    } else if (detectedYtId != null && _thumbnailUrl == null) {
      setState(() {
        _thumbnailUrl = 'https://img.youtube.com/vi/$detectedYtId/mqdefault.jpg';
      });
    } else if ((text.endsWith('.mp4') ||
            text.endsWith('.m3u8') ||
            text.endsWith('.webm')) &&
        _selectedType != 'direct_url') {
      setState(() {
        _selectedType = 'direct_url';
        _thumbnailUrl = null;
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _urlController.removeListener(_onUrlChanged);
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        _urlController.text = text;
        final ytId = UnifiedPlayerController.extractYouTubeVideoId(text);
        if (ytId != null) {
          setState(() {
            _selectedType = 'youtube';
            _thumbnailUrl = 'https://img.youtube.com/vi/$ytId/mqdefault.jpg';
          });
        }
      }
    } catch (_) {}
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

  void _addToQueue() {
    final url = _urlController.text.trim();
    if (url.isEmpty || widget.queueController == null) return;

    var type = _selectedType;
    if (UnifiedPlayerController.extractYouTubeVideoId(url) != null) {
      type = 'youtube';
    } else if (type == 'youtube' &&
        (url.endsWith('.mp4') ||
            url.endsWith('.m3u8') ||
            url.endsWith('.webm'))) {
      type = 'direct_url';
    }

    var title = _titleController.text.trim();
    if (title.isEmpty) {
      final ytId = UnifiedPlayerController.extractYouTubeVideoId(url);
      if (ytId != null) {
        title = 'Video YouTube ($ytId)';
      } else {
        final uri = Uri.tryParse(url);
        final segment = uri?.pathSegments.isNotEmpty == true
            ? uri!.pathSegments.last
            : null;
        title = segment ?? 'Video Direct';
      }
    }

    widget.queueController!.addToQueue(
      mediaType: type,
      mediaUrl: url,
      title: title,
      thumbnailUrl: _thumbnailUrl,
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
    final hasUrl = _urlController.text.trim().isNotEmpty;
    final ytId = UnifiedPlayerController.extractYouTubeVideoId(_urlController.text.trim());

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

                const SizedBox(height: 14),

                // Modern Pill Segmented Control
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _PillTabItem(
                          icon: Icons.play_circle_fill_rounded,
                          iconColor: const Color(0xFFFF0000),
                          label: 'YouTube',
                          isSelected: _selectedType == 'youtube',
                          onTap: () => setState(() => _selectedType = 'youtube'),
                        ),
                      ),
                      Expanded(
                        child: _PillTabItem(
                          icon: Icons.link_rounded,
                          iconColor: AppColors.secondaryNeon,
                          label: 'Direct / HLS',
                          isSelected: _selectedType == 'direct_url',
                          onTap: () => setState(() => _selectedType = 'direct_url'),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Tab Content
                if (_selectedType == 'youtube') ...[
                  // YouTube Search Action Card
                  Material(
                    color: const Color(0xFFFF0000).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final video = await Navigator.of(context).push<YouTubeVideo>(
                          MaterialPageRoute(
                            builder: (_) => const YouTubePickerScreen(),
                          ),
                        );
                        if (video != null && mounted) {
                          setState(() {
                            _urlController.text = video.url;
                            _titleController.text = video.title;
                            _thumbnailUrl = video.thumbnailUrl;
                            _selectedType = 'youtube';
                          });
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF0000).withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.search_rounded,
                                color: Color(0xFFFF0000),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cari di YouTube',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Cari video, trending, musik & klip',
                                    style: TextStyle(
                                      fontSize: 11,
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

                  const SizedBox(height: 12),

                  // Divider with text
                  Row(
                    children: [
                      Expanded(
                          child: Divider(color: AppColors.border.withValues(alpha: 0.6))),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'atau tempel tautan',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textMuted),
                        ),
                      ),
                      Expanded(
                          child: Divider(color: AppColors.border.withValues(alpha: 0.6))),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // YouTube URL Input with Paste button
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'https://youtube.com/watch?v=...',
                      hintStyle: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.link_rounded,
                          color: Color(0xFFFF0000), size: 18),
                      suffixIcon: hasUrl
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _urlController.clear();
                                _titleController.clear();
                                setState(() => _thumbnailUrl = null);
                              },
                            )
                          : TextButton.icon(
                              onPressed: _pasteFromClipboard,
                              icon: const Icon(Icons.content_paste_rounded,
                                  size: 14),
                              label: const Text('Paste',
                                  style: TextStyle(fontSize: 11)),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: AppColors.secondaryNeon,
                              ),
                            ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),

                  // Live Preview Card (if video identified)
                  if (hasUrl && (ytId != null || _thumbnailUrl != null)) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.accentRed.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 64,
                              height: 42,
                              child: Image.network(
                                _thumbnailUrl ??
                                    'https://img.youtube.com/vi/$ytId/mqdefault.jpg',
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  color: Colors.black26,
                                  child: const Icon(Icons.movie_rounded,
                                      size: 18, color: Colors.white54),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _titleController.text.isNotEmpty
                                      ? _titleController.text
                                      : 'Video YouTube ($ytId)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Siap diputar',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.primaryNeon,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  // Direct URL Tab
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'URL Video Langsung',
                      hintText: 'https://domain.com/video.mp4 atau .m3u8',
                      hintStyle: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.movie_outlined,
                          color: AppColors.secondaryNeon, size: 18),
                      suffixIcon: hasUrl
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _urlController.clear();
                                _titleController.clear();
                              },
                            )
                          : TextButton.icon(
                              onPressed: _pasteFromClipboard,
                              icon: const Icon(Icons.content_paste_rounded,
                                  size: 14),
                              label: const Text('Paste',
                                  style: TextStyle(fontSize: 11)),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: AppColors.secondaryNeon,
                              ),
                            ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Optional Title
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Judul Video (Opsional)',
                      hintText: 'Contoh: Episode 1 / Movie Name',
                      hintStyle:
                          TextStyle(fontSize: 12, color: AppColors.textMuted),
                      prefixIcon: Icon(Icons.title_rounded,
                          color: AppColors.textSecondary, size: 18),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Micro format badges
                  const Row(
                    children: [
                      Text(
                        'Format didukung:',
                        style: TextStyle(
                            fontSize: 10, color: AppColors.textSecondary),
                      ),
                      SizedBox(width: 6),
                      _FormatBadge(label: 'MP4'),
                      SizedBox(width: 4),
                      _FormatBadge(label: 'HLS .m3u8'),
                      SizedBox(width: 4),
                      _FormatBadge(label: 'WEBM'),
                    ],
                  ),
                ],

                const SizedBox(height: 12),

                // Collapsible Demo/Sample Media Accordion
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: _showPresets,
                    onExpansionChanged: (v) => setState(() => _showPresets = v),
                    tilePadding: EdgeInsets.zero,
                    dense: true,
                    title: const Row(
                      children: [
                        Icon(Icons.bolt_rounded,
                            size: 15, color: Colors.amber),
                        SizedBox(width: 6),
                        Text(
                          'Contoh Video Uji Coba (Demo)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.border, width: 0.6),
                        ),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: ApiConstants.presetMedia
                              .where((m) => m['type'] == _selectedType)
                              .map((m) {
                            return ActionChip(
                              avatar: Icon(
                                m['type'] == 'youtube'
                                    ? Icons.play_arrow_rounded
                                    : Icons.movie_rounded,
                                size: 14,
                                color: m['type'] == 'youtube'
                                    ? const Color(0xFFFF0000)
                                    : AppColors.secondaryNeon,
                              ),
                              label: Text(
                                m['title']!,
                                style: const TextStyle(fontSize: 11),
                              ),
                              backgroundColor: AppColors.surface,
                              side: const BorderSide(
                                  color: AppColors.border, width: 0.8),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              onPressed: () {
                                _urlController.text = m['url']!;
                                _titleController.text = m['title']!;
                                setState(() {
                                  _showPresets = false;
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Primary & Secondary Actions
                if (widget.isAddingToQueueInitial) ...[
                  ElevatedButton.icon(
                    onPressed: hasUrl ? _addToQueue : null,
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
                    onPressed: hasUrl ? _applyMedia : null,
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text(
                      'Putar Sekarang',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  if (widget.queueController != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: hasUrl ? _addToQueue : null,
                      icon: const Icon(Icons.playlist_add_rounded, size: 17),
                      label: const Text('Tambahkan ke Antrean Saja'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryNeon,
                        side: BorderSide(
                          color: hasUrl
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

class _PillTabItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PillTabItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.surface
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? iconColor : AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormatBadge extends StatelessWidget {
  final String label;
  const _FormatBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}
