import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../chat/controllers/chat_controller.dart';
import '../../../lobby/data/models/bstation_video_model.dart';
import '../../../lobby/data/models/dailymotion_video_model.dart';
import '../../../lobby/data/models/google_drive_video_model.dart';
import '../../../lobby/data/models/twitch_stream_model.dart';
import '../../../lobby/data/models/vimeo_video_model.dart';
import '../../../lobby/data/models/youtube_video_model.dart';
import '../../../lobby/presentation/screens/bstation_picker_screen.dart';
import '../../../lobby/presentation/screens/dailymotion_picker_screen.dart';
import '../../../lobby/presentation/screens/google_drive_picker_screen.dart';
import '../../../lobby/presentation/screens/twitch_picker_screen.dart';
import '../../../lobby/presentation/screens/vimeo_picker_screen.dart';
import '../../../lobby/presentation/screens/youtube_picker_screen.dart';
import '../../controllers/queue_controller.dart';
import '../../controllers/sync_controller.dart';
import '../../controllers/unified_player_controller.dart';
import '../../../p2p_streaming/controllers/p2p_stream_controller.dart';
import '../../../p2p_streaming/models/local_video_file.dart';
import '../../../p2p_streaming/presentation/local_video_picker_sheet.dart';

/// Clean, modern, and user-friendly Media Source Picker.
/// Can be used as a bottom sheet (recommended) or as a dialog.
class MediaSourcePicker extends StatefulWidget {
  final SyncController syncController;
  final ChatController? chatController;
  final QueueController? queueController;
  final P2pStreamController? p2pController;
  final bool isAddingToQueueInitial;

  const MediaSourcePicker({
    super.key,
    required this.syncController,
    this.chatController,
    this.queueController,
    this.p2pController,
    this.isAddingToQueueInitial = false,
  });

  /// Displays [MediaSourcePicker] as a modern modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required SyncController syncController,
    ChatController? chatController,
    QueueController? queueController,
    P2pStreamController? p2pController,
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
        p2pController: p2pController,
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
  String _selectedType = 'youtube'; // 'youtube', 'twitch', 'vimeo', 'direct_url', 'local_p2p'
  LocalVideoFile? _selectedLocalFile;
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
    final detected = UnifiedPlayerController.detectMediaFromUrl(text);

    if (detected != null) {
      setState(() {
        _selectedType = detected.mediaType;
        _thumbnailUrl = detected.thumbnailUrl;
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
        final detected = UnifiedPlayerController.detectMediaFromUrl(text);
        if (detected != null) {
          setState(() {
            _selectedType = detected.mediaType;
            _thumbnailUrl = detected.thumbnailUrl;
          });
        }
      }
    } catch (_) {}
  }

  void _applyMedia() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    if (_selectedType == 'local_p2p' && _selectedLocalFile != null) {
      widget.p2pController?.startHostStreaming(_selectedLocalFile!);
      final p2pUrl = 'p2p://${_selectedLocalFile!.id}?title=${Uri.encodeComponent(_selectedLocalFile!.name)}';
      widget.syncController.requestChangeMedia('direct_url', p2pUrl);
      widget.syncController.player.loadMedia(
        'direct_url',
        _selectedLocalFile!.path ?? p2pUrl,
        autoPlay: true,
      );
      widget.chatController?.sendSystemMessage(
        '${widget.syncController.currentUser.username} memutar video lokal: ${_selectedLocalFile!.name} (P2P Internet)',
      );
      Navigator.of(context).pop();
      return;
    }

    final detected = UnifiedPlayerController.detectMediaFromUrl(url);
    final type = detected?.mediaType ?? _selectedType;

    widget.syncController.requestChangeMedia(type, url);
    widget.chatController?.sendSystemMessage(
      '${widget.syncController.currentUser.username} mengubah video.',
    );
    Navigator.of(context).pop();
  }

  void _addToQueue() {
    final url = _urlController.text.trim();
    if (url.isEmpty || widget.queueController == null) return;

    if (_selectedType == 'local_p2p' && _selectedLocalFile != null) {
      final p2pUrl = 'p2p://${_selectedLocalFile!.id}?title=${Uri.encodeComponent(_selectedLocalFile!.name)}';
      widget.queueController!.addToQueue(
        mediaType: 'direct_url',
        mediaUrl: p2pUrl,
        title: _selectedLocalFile!.name,
      );
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${_selectedLocalFile!.name}" ditambahkan ke antrean!'),
          backgroundColor: AppColors.primaryNeon,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final detected = UnifiedPlayerController.detectMediaFromUrl(url);
    final type = detected?.mediaType ?? _selectedType;

    var title = _titleController.text.trim();
    if (title.isEmpty) {
      title = detected?.title ?? 'Video Antrean';
    }

    widget.queueController!.addToQueue(
      mediaType: type,
      mediaUrl: url,
      title: title,
      thumbnailUrl: detected?.thumbnailUrl ?? _thumbnailUrl,
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
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _PillTabItem(
                          icon: Icons.play_circle_fill_rounded,
                          iconColor: const Color(0xFFFF0000),
                          label: 'YT',
                          isSelected: _selectedType == 'youtube',
                          onTap: () => setState(() => _selectedType = 'youtube'),
                        ),
                        const SizedBox(width: 4),
                        _PillTabItem(
                          icon: Icons.live_tv_rounded,
                          iconColor: const Color(0xFF9146FF),
                          label: 'Twitch',
                          isSelected: _selectedType == 'twitch',
                          onTap: () => setState(() => _selectedType = 'twitch'),
                        ),
                        const SizedBox(width: 4),
                        _PillTabItem(
                          icon: Icons.video_collection_rounded,
                          iconColor: const Color(0xFF1AB7EA),
                          label: 'Vimeo',
                          isSelected: _selectedType == 'vimeo',
                          onTap: () => setState(() => _selectedType = 'vimeo'),
                        ),
                        const SizedBox(width: 4),
                        _PillTabItem(
                          icon: Icons.play_circle_filled_rounded,
                          iconColor: const Color(0xFF0066DC),
                          label: 'Daily',
                          isSelected: _selectedType == 'dailymotion',
                          onTap: () => setState(() => _selectedType = 'dailymotion'),
                        ),
                        const SizedBox(width: 4),
                        _PillTabItem(
                          icon: Icons.smart_display_rounded,
                          iconColor: const Color(0xFF00A1D6),
                          label: 'Bili',
                          isSelected: _selectedType == 'bstation',
                          onTap: () => setState(() => _selectedType = 'bstation'),
                        ),
                        const SizedBox(width: 4),
                        _PillTabItem(
                          icon: Icons.cloud_queue_rounded,
                          iconColor: const Color(0xFF0F9D58),
                          label: 'Drive',
                          isSelected: _selectedType == 'google_drive',
                          onTap: () => setState(() => _selectedType = 'google_drive'),
                        ),
                        const SizedBox(width: 4),
                        _PillTabItem(
                          icon: Icons.wifi_tethering_rounded,
                          iconColor: const Color(0xFF00B4D8),
                          label: 'Lokal P2P',
                          isSelected: _selectedType == 'local_p2p',
                          onTap: () => setState(() => _selectedType = 'local_p2p'),
                        ),
                        const SizedBox(width: 4),
                        _PillTabItem(
                          icon: Icons.link_rounded,
                          iconColor: AppColors.secondaryNeon,
                          label: 'Direct',
                          isSelected: _selectedType == 'direct_url',
                          onTap: () => setState(() => _selectedType = 'direct_url'),
                        ),
                      ],
                    ),
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
                ] else if (_selectedType == 'twitch') ...[
                  // Twitch Browse / Search Action Card
                  Material(
                    color: const Color(0xFF9146FF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final stream = await Navigator.of(context).push<TwitchStream>(
                          MaterialPageRoute(
                            builder: (_) => const TwitchPickerScreen(),
                          ),
                        );
                        if (stream != null && mounted) {
                          setState(() {
                            _urlController.text = stream.url;
                            _titleController.text = stream.title;
                            _thumbnailUrl = stream.thumbnailUrl;
                            _selectedType = 'twitch';
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
                                color: const Color(0xFF9146FF).withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.search_rounded,
                                color: Color(0xFF9146FF),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Jelajahi Stream Twitch',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Pilih siaran live, musik 24/7, esports, gaming',
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

                  // Twitch URL Input
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Tautan Channel atau Video Twitch',
                      hintText: 'https://twitch.tv/monstercat atau /videos/...',
                      hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      prefixIcon: const Icon(
                        Icons.live_tv_rounded,
                        color: Color(0xFF9146FF),
                        size: 18,
                      ),
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
                              icon: const Icon(Icons.content_paste_rounded, size: 14),
                              label: const Text('Paste', style: TextStyle(fontSize: 11)),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: const Color(0xFF9146FF),
                              ),
                            ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Optional Title
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Judul Siaran (Opsional)',
                      hintText: 'Contoh: Nonton Bareng Streamer Favorit',
                      hintStyle: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      prefixIcon: Icon(Icons.title_rounded, color: AppColors.textSecondary, size: 18),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ] else if (_selectedType == 'vimeo') ...[
                  // Vimeo Browse / Search Action Card
                  Material(
                    color: const Color(0xFF1AB7EA).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final video = await Navigator.of(context).push<VimeoVideo>(
                          MaterialPageRoute(
                            builder: (_) => const VimeoPickerScreen(),
                          ),
                        );
                        if (video != null && mounted) {
                          setState(() {
                            _urlController.text = video.url;
                            _titleController.text = video.title;
                            _thumbnailUrl = video.thumbnailUrl;
                            _selectedType = 'vimeo';
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
                                color: const Color(0xFF1AB7EA).withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.search_rounded,
                                color: Color(0xFF1AB7EA),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Jelajahi Video Vimeo',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Pilih Staff Picks, film pendek, animasi 3D',
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

                  // Vimeo URL Input
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Tautan Video Vimeo',
                      hintText: 'https://vimeo.com/76979871',
                      hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      prefixIcon: const Icon(
                        Icons.video_collection_rounded,
                        color: Color(0xFF1AB7EA),
                        size: 18,
                      ),
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
                              icon: const Icon(Icons.content_paste_rounded, size: 14),
                              label: const Text('Paste', style: TextStyle(fontSize: 11)),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: const Color(0xFF1AB7EA),
                              ),
                            ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Optional Title
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Judul Video (Opsional)',
                      hintText: 'Contoh: Tears of Steel 4K',
                      hintStyle: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      prefixIcon: Icon(Icons.title_rounded, color: AppColors.textSecondary, size: 18),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ] else if (_selectedType == 'google_drive') ...[
                  // Google Drive Browse / Search Action Card
                  Material(
                    color: const Color(0xFF0F9D58).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final video = await Navigator.of(context).push<GoogleDriveVideo>(
                          MaterialPageRoute(
                            builder: (_) => const GoogleDrivePickerScreen(),
                          ),
                        );
                        if (video != null && mounted) {
                          setState(() {
                            _urlController.text = video.url;
                            _titleController.text = video.title;
                            _thumbnailUrl = video.thumbnailUrl;
                            _selectedType = 'google_drive';
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
                                color: const Color(0xFF0F9D58).withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.cloud_queue_rounded,
                                color: Color(0xFF0F9D58),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Jelajahi Video Google Drive',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Buka Drive Saya (Login Akun) atau Koleksi Publik',
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

                  // Drive URL Input
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Tautan atau File ID Google Drive',
                      hintText: 'https://drive.google.com/file/d/... atau ID',
                      hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      prefixIcon: const Icon(
                        Icons.cloud_queue_rounded,
                        color: Color(0xFF0F9D58),
                        size: 18,
                      ),
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
                              icon: const Icon(Icons.content_paste_rounded, size: 14),
                              label: const Text('Paste', style: TextStyle(fontSize: 11)),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: const Color(0xFF0F9D58),
                              ),
                            ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Optional Title
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Judul Video (Opsional)',
                      hintText: 'Contoh: Tears of Steel Drive 4K',
                      hintStyle: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      prefixIcon: Icon(Icons.title_rounded, color: AppColors.textSecondary, size: 18),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ] else if (_selectedType == 'dailymotion') ...[
                  // Dailymotion Browse / Search Action Card
                  Material(
                    color: const Color(0xFF0066DC).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final video = await Navigator.of(context).push<DailymotionVideo>(
                          MaterialPageRoute(
                            builder: (_) => const DailymotionPickerScreen(),
                          ),
                        );
                        if (video != null && mounted) {
                          setState(() {
                            _urlController.text = video.url;
                            _titleController.text = video.title;
                            _thumbnailUrl = video.effectiveThumbnailUrl;
                            _selectedType = 'dailymotion';
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
                                color: const Color(0xFF0066DC).withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_circle_filled_rounded,
                                color: Color(0xFF0066DC),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Jelajahi Video Dailymotion',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Pilih video trending, berita, musik & animasi',
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
                          'atau tempel link Dailymotion',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textMuted),
                        ),
                      ),
                      Expanded(
                          child: Divider(color: AppColors.border.withValues(alpha: 0.6))),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Dailymotion URL Input
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Link Video Dailymotion',
                      hintText: 'https://www.dailymotion.com/video/x7tgad0',
                      hintStyle: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.link_rounded,
                          color: Color(0xFF0066DC), size: 18),
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
                              icon: const Icon(Icons.content_paste_rounded, size: 14),
                              label: const Text('Paste', style: TextStyle(fontSize: 11)),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: const Color(0xFF0066DC),
                              ),
                            ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Optional Title
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Judul Video (Opsional)',
                      hintText: 'Contoh: Big Buck Bunny Dailymotion',
                      hintStyle: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      prefixIcon: Icon(Icons.title_rounded, color: AppColors.textSecondary, size: 18),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ] else if (_selectedType == 'bstation') ...[
                  // Bstation Browse / Search Action Card
                  Material(
                    color: const Color(0xFF00A1D6).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final video = await Navigator.of(context).push<BstationVideo>(
                          MaterialPageRoute(
                            builder: (_) => const BstationPickerScreen(),
                          ),
                        );
                        if (video != null && mounted) {
                          setState(() {
                            _urlController.text = video.url;
                            _titleController.text = video.title;
                            _thumbnailUrl = video.effectiveThumbnailUrl;
                            _selectedType = 'bstation';
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
                                color: const Color(0xFF00A1D6).withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.smart_display_rounded,
                                color: Color(0xFF00A1D6),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Jelajahi Video Bstation',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Pilih anime populer, trending, AMV, kreator & musik',
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
                          'atau tempel link Bstation',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textMuted),
                        ),
                      ),
                      Expanded(
                          child: Divider(color: AppColors.border.withValues(alpha: 0.6))),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Bstation URL Input
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Link Video / Anime Bstation',
                      hintText: 'https://bilibili.tv/id/video/... atau BV...',
                      hintStyle: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.smart_display_rounded,
                          color: Color(0xFF00A1D6), size: 18),
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
                              icon: const Icon(Icons.content_paste_rounded, size: 14),
                              label: const Text('Paste', style: TextStyle(fontSize: 11)),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: const Color(0xFF00A1D6),
                              ),
                            ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Optional Title
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Judul Video (Opsional)',
                      hintText: 'Contoh: Spy x Family Episode 1',
                      hintStyle: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      prefixIcon: Icon(Icons.title_rounded, color: AppColors.textSecondary, size: 18),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ] else if (_selectedType == 'direct_url') ...[
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
                ] else if (_selectedType == 'local_p2p') ...[
                  // Local P2P Video Picker Action Card
                  Material(
                    color: const Color(0xFF00B4D8).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final file = await LocalVideoPickerSheet.show(
                          context,
                          isAddingToQueue: widget.isAddingToQueueInitial,
                        );
                        if (file != null && mounted) {
                          setState(() {
                            _selectedLocalFile = file;
                            _urlController.text = file.path ??
                                'p2p://${file.id}?title=${Uri.encodeComponent(file.name)}';
                            _titleController.text = file.name;
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
                                color: const Color(0xFF00B4D8).withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.folder_open_rounded,
                                color: Color(0xFF00B4D8),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedLocalFile != null
                                        ? _selectedLocalFile!.name
                                        : 'Pilih File Video dari HP / PC',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _selectedLocalFile != null
                                        ? '${_selectedLocalFile!.formattedSize} • Format ${_selectedLocalFile!.extension.toUpperCase()}'
                                        : 'Streaming via WebRTC Internet langsung tanpa upload',
                                    style: const TextStyle(
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

                  // Optional Title
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Judul Video (Opsional)',
                      hintText: 'Contoh: Movie Name 1080p',
                      hintStyle:
                          TextStyle(fontSize: 12, color: AppColors.textMuted),
                      prefixIcon: Icon(Icons.title_rounded,
                          color: AppColors.textSecondary, size: 18),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),

                  const SizedBox(height: 8),

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
                      _FormatBadge(label: 'MKV'),
                      SizedBox(width: 4),
                      _FormatBadge(label: 'WEBM'),
                      SizedBox(width: 4),
                      _FormatBadge(label: 'MOV'),
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
                                    : (m['type'] == 'twitch'
                                        ? Icons.live_tv_rounded
                                        : (m['type'] == 'vimeo'
                                            ? Icons.video_collection_rounded
                                            : (m['type'] == 'google_drive'
                                                ? Icons.cloud_queue_rounded
                                                : (m['type'] == 'dailymotion'
                                                    ? Icons.play_circle_filled_rounded
                                                    : (m['type'] == 'bstation'
                                                        ? Icons.smart_display_rounded
                                                        : Icons.movie_rounded))))),
                                size: 14,
                                color: m['type'] == 'youtube'
                                    ? const Color(0xFFFF0000)
                                    : (m['type'] == 'twitch'
                                        ? const Color(0xFF9146FF)
                                        : (m['type'] == 'vimeo'
                                            ? const Color(0xFF1AB7EA)
                                            : (m['type'] == 'google_drive'
                                                ? const Color(0xFF0F9D58)
                                                : (m['type'] == 'dailymotion'
                                                    ? const Color(0xFF0066DC)
                                                    : (m['type'] == 'bstation'
                                                        ? const Color(0xFF00A1D6)
                                                        : AppColors.secondaryNeon))))),
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
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? iconColor : AppColors.textMuted,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
