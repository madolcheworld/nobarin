import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../chat/controllers/chat_controller.dart';
import '../../../lobby/data/models/bstation_video_model.dart';
import '../../../lobby/data/models/dailymotion_video_model.dart';
import '../../../lobby/data/models/google_drive_video_model.dart';
import '../../../lobby/data/models/youtube_video_model.dart';
import '../../../lobby/presentation/screens/bstation_picker_screen.dart';
import '../../../lobby/presentation/screens/dailymotion_picker_screen.dart';
import '../../../lobby/presentation/screens/google_drive_picker_screen.dart';
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
  String _selectedType = 'youtube'; // 'youtube', 'dailymotion', 'bstation', 'google_drive', 'local_p2p'
  LocalVideoFile? _selectedLocalFile;

  @override
  void initState() {
    super.initState();
    if (!widget.isAddingToQueueInitial) {
      _urlController.text = widget.syncController.player.mediaUrl;
      final currentType = widget.syncController.player.mediaType;
      _selectedType = (currentType == 'direct_url' && !_urlController.text.startsWith('p2p://'))
          ? 'youtube'
          : currentType;
      final detected = UnifiedPlayerController.detectMediaFromUrl(_urlController.text);
      if (detected != null) {
        _thumbnailUrl = detected.thumbnailUrl;
        _titleController.text = detected.title;
      }
    } else {
      _selectedType = 'youtube';
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
    final currentUrl = _urlController.text.trim();
    final ytId = UnifiedPlayerController.extractYouTubeVideoId(currentUrl);

    final isCurrentYt = ytId != null || (currentUrl.isNotEmpty && _selectedType == 'youtube');
    final isCurrentDaily = _selectedType == 'dailymotion' && currentUrl.isNotEmpty;
    final isCurrentBstation = _selectedType == 'bstation' && currentUrl.isNotEmpty;
    final isCurrentDrive = _selectedType == 'google_drive' && currentUrl.isNotEmpty;
    final isCurrentLocal = _selectedLocalFile != null || currentUrl.startsWith('p2p://');

    final bool canProceed = (_selectedType == 'youtube' && isCurrentYt) ||
        (_selectedType == 'dailymotion' && isCurrentDaily) ||
        (_selectedType == 'bstation' && isCurrentBstation) ||
        (_selectedType == 'google_drive' && isCurrentDrive) ||
        (_selectedType == 'local_p2p' && isCurrentLocal);

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
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Tab Content
                if (_selectedType == 'youtube') ...[
                  _ActionSearchCard(
                    title: 'Cari di YouTube',
                    subtitle: 'Cari video, musik, podcast, & klip trending',
                    icon: Icons.search_rounded,
                    color: const Color(0xFFFF0000),
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
                  ),

                  if (isCurrentYt) ...[
                    const SizedBox(height: 12),
                    _SelectedVideoCard(
                      title: _titleController.text.isNotEmpty
                          ? _titleController.text
                          : 'Video YouTube ($ytId)',
                      thumbnailUrl: _thumbnailUrl ??
                          (ytId != null ? 'https://img.youtube.com/vi/$ytId/mqdefault.jpg' : null),
                      platformLabel: 'YouTube',
                      platformColor: const Color(0xFFFF0000),
                      onGanti: () async {
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
                          });
                        }
                      },
                    ),
                  ],
                ] else if (_selectedType == 'dailymotion') ...[
                  _ActionSearchCard(
                    title: 'Jelajahi Video Dailymotion',
                    subtitle: 'Pilih video trending, musik, animasi & berita',
                    icon: Icons.play_circle_filled_rounded,
                    color: const Color(0xFF0066DC),
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
                  ),

                  if (isCurrentDaily) ...[
                    const SizedBox(height: 12),
                    _SelectedVideoCard(
                      title: _titleController.text.isNotEmpty
                          ? _titleController.text
                          : 'Video Dailymotion',
                      thumbnailUrl: _thumbnailUrl ??
                          'https://www.dailymotion.com/thumbnail/video/${UnifiedPlayerController.extractDailymotionVideoId(currentUrl) ?? ""}',
                      platformLabel: 'Dailymotion',
                      platformColor: const Color(0xFF0066DC),
                      onGanti: () async {
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
                          });
                        }
                      },
                    ),
                  ],
                ] else if (_selectedType == 'bstation') ...[
                  _ActionSearchCard(
                    title: 'Jelajahi Video Bstation',
                    subtitle: 'Pilih anime populer, trending, AMV, & kreator',
                    icon: Icons.smart_display_rounded,
                    color: const Color(0xFF00A1D6),
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
                  ),

                  if (isCurrentBstation) ...[
                    const SizedBox(height: 12),
                    _SelectedVideoCard(
                      title: _titleController.text.isNotEmpty
                          ? _titleController.text
                          : 'Video Bstation',
                      thumbnailUrl: _thumbnailUrl,
                      platformLabel: 'Bstation',
                      platformColor: const Color(0xFF00A1D6),
                      onGanti: () async {
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
                          });
                        }
                      },
                    ),
                  ],
                ] else if (_selectedType == 'google_drive') ...[
                  _ActionSearchCard(
                    title: 'Jelajahi Video Google Drive',
                    subtitle: 'Buka Drive Saya (Login Akun) atau Koleksi Publik',
                    icon: Icons.cloud_queue_rounded,
                    color: const Color(0xFF0F9D58),
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
                  ),

                  if (isCurrentDrive) ...[
                    const SizedBox(height: 12),
                    _SelectedVideoCard(
                      title: _titleController.text.isNotEmpty
                          ? _titleController.text
                          : 'Video Google Drive',
                      thumbnailUrl: _thumbnailUrl,
                      platformLabel: 'Google Drive',
                      platformColor: const Color(0xFF0F9D58),
                      onGanti: () async {
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
                          });
                        }
                      },
                    ),
                  ],
                ] else if (_selectedType == 'local_p2p') ...[
                  _ActionSearchCard(
                    title: _selectedLocalFile != null
                        ? _selectedLocalFile!.name
                        : 'Pilih File Video dari HP / PC',
                    subtitle: _selectedLocalFile != null
                        ? '${_selectedLocalFile!.formattedSize} • Format ${_selectedLocalFile!.extension.toUpperCase()}'
                        : 'Streaming via WebRTC Internet langsung tanpa upload',
                    icon: Icons.folder_open_rounded,
                    color: const Color(0xFF00B4D8),
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
                  ),

                  if (_selectedLocalFile != null || isCurrentLocal) ...[
                    const SizedBox(height: 12),
                    _SelectedVideoCard(
                      title: _selectedLocalFile?.name ??
                          (_titleController.text.isNotEmpty
                              ? _titleController.text
                              : 'Video Lokal P2P'),
                      thumbnailUrl: null,
                      platformLabel: 'Lokal P2P',
                      platformColor: const Color(0xFF00B4D8),
                      customSubtitle: _selectedLocalFile != null
                          ? '${_selectedLocalFile!.formattedSize} • ${_selectedLocalFile!.extension.toUpperCase()}'
                          : 'File Lokal Siap Diputar',
                      onGanti: () async {
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
                    ),
                  ],

                  const SizedBox(height: 10),
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

                const SizedBox(height: 16),

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

class _ActionSearchCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionSearchCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Buka',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_forward_ios_rounded, size: 10, color: color),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedVideoCard extends StatelessWidget {
  final String title;
  final String? thumbnailUrl;
  final String platformLabel;
  final Color platformColor;
  final String? customSubtitle;
  final VoidCallback onGanti;

  const _SelectedVideoCard({
    required this.title,
    required this.thumbnailUrl,
    required this.platformLabel,
    required this.platformColor,
    this.customSubtitle,
    required this.onGanti,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 58,
              height: 42,
              child: thumbnailUrl != null && thumbnailUrl!.isNotEmpty
                  ? Image.network(
                      thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: AppColors.surface,
                        child: Icon(Icons.video_library_rounded,
                            size: 20, color: platformColor),
                      ),
                    )
                  : Container(
                      color: AppColors.surface,
                      child: Icon(Icons.video_library_rounded,
                          size: 20, color: platformColor),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: platformColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        platformLabel,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: platformColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Video Terpilih',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (customSubtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    customSubtitle!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onGanti,
            style: TextButton.styleFrom(
              foregroundColor: platformColor,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Ganti',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
