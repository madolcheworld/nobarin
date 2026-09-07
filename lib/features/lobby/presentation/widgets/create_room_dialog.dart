import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../room/controllers/unified_player_controller.dart';
import '../../../room/models/room_model.dart';
import '../../data/models/youtube_video_model.dart';
import '../../data/youtube_service.dart';
import '../lobby_controller.dart';
import '../screens/youtube_picker_screen.dart';

class CreateRoomDialog extends ConsumerStatefulWidget {
  final YouTubeVideo? initialYouTubeVideo;
  final String? initialMediaType;
  final String? initialMediaUrl;
  final VoidCallback? onChangeVideo;

  const CreateRoomDialog({
    super.key,
    this.initialYouTubeVideo,
    this.initialMediaType,
    this.initialMediaUrl,
    this.onChangeVideo,
  });

  /// Shows CreateRoom dialog as a modern modal bottom sheet
  static Future<RoomModel?> show(
    BuildContext context, {
    YouTubeVideo? initialYouTubeVideo,
    String? initialMediaType,
    String? initialMediaUrl,
  }) {
    return showModalBottomSheet<RoomModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateRoomDialog(
        initialYouTubeVideo: initialYouTubeVideo,
        initialMediaType: initialMediaType,
        initialMediaUrl: initialMediaUrl,
      ),
    );
  }

  @override
  ConsumerState<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends ConsumerState<CreateRoomDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _mediaUrlController = TextEditingController();

  YouTubeVideo? _selectedYouTubeVideo;
  String _mediaType = 'direct_url';
  String _controlMode = 'host_only'; // 'host_only' or 'collaborative'
  bool _isPublic = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialYouTubeVideo != null) {
      _selectedYouTubeVideo = widget.initialYouTubeVideo;
      _mediaType = 'youtube';
      _mediaUrlController.text = widget.initialYouTubeVideo!.url;
      _titleController.text = widget.initialYouTubeVideo!.title;
    } else if (widget.initialMediaUrl != null) {
      _mediaType = widget.initialMediaType ?? 'direct_url';
      _mediaUrlController.text = widget.initialMediaUrl!;
      _titleController.text = 'Nonton Bareng';
    } else {
      _titleController.text = 'Nonton Bareng';
      _mediaUrlController.text = ApiConstants.presetMedia[0]['url']!;
    }
    _mediaUrlController.addListener(_onMediaUrlChanged);
  }

  void _onMediaUrlChanged() {
    final text = _mediaUrlController.text.trim();
    final ytId = UnifiedPlayerController.extractYouTubeVideoId(text);
    if (ytId != null) {
      if (_mediaType != 'youtube') {
        setState(() => _mediaType = 'youtube');
      }
      if (_selectedYouTubeVideo == null || _selectedYouTubeVideo!.id != ytId) {
        YouTubeService.fetchVideoDetails(ytId).then((v) {
          if (mounted) setState(() => _selectedYouTubeVideo = v);
        });
      }
    } else if ((text.endsWith('.mp4') ||
            text.endsWith('.m3u8') ||
            text.endsWith('.webm')) &&
        _mediaType != 'direct_url') {
      setState(() {
        _mediaType = 'direct_url';
        _selectedYouTubeVideo = null;
      });
    }
  }

  @override
  void dispose() {
    _mediaUrlController.removeListener(_onMediaUrlChanged);
    _titleController.dispose();
    _descController.dispose();
    _mediaUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickAnotherYouTubeVideo() async {
    final result = await Navigator.of(context).push<YouTubeVideo>(
      MaterialPageRoute(builder: (_) => const YouTubePickerScreen()),
    );
    if (result != null && mounted) {
      setState(() {
        _selectedYouTubeVideo = result;
        _mediaType = 'youtube';
        _mediaUrlController.text = result.url;
        _titleController.text = result.title;
      });
    }
  }

  Future<void> _handleCreate() async {
    if (!_formKey.currentState!.validate()) return;

    final user = ref.read(authControllerProvider).asData?.value;
    if (user == null) return;

    setState(() => _isLoading = true);

    var mediaType = _mediaType;
    final mediaUrl = _mediaUrlController.text.trim();
    if (UnifiedPlayerController.extractYouTubeVideoId(mediaUrl) != null) {
      mediaType = 'youtube';
    } else if (mediaType == 'youtube' &&
        (mediaUrl.endsWith('.mp4') ||
            mediaUrl.endsWith('.m3u8') ||
            mediaUrl.endsWith('.webm'))) {
      mediaType = 'direct_url';
    }

    final room = await ref.read(lobbyControllerProvider.notifier).createRoom(
          title: _titleController.text.trim(),
          description: _descController.text.trim().isEmpty
              ? null
              : _descController.text.trim(),
          hostId: user.id,
          hostName: user.username,
          isPublic: _isPublic,
          controlMode: _controlMode,
          initialMediaType: mediaType,
          initialMediaUrl: mediaUrl,
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (room != null) {
      Navigator.of(context).pop(room);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal membuat room. Silakan coba lagi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: AppColors.border),
            left: BorderSide(color: AppColors.border),
            right: BorderSide(color: AppColors.border),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 12, 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.video_camera_front_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Buat Room Nonton',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Atur detail room sebelum mulai',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textSecondary, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Tutup',
                    ),
                  ],
                ),
              ),

              const Divider(color: AppColors.border, height: 1),

              // Scrollable Form Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Selected YouTube Video Preview Card
                        if (_mediaType == 'youtube') ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.border.withValues(alpha: 0.8),
                              ),
                            ),
                            child: Row(
                              children: [
                                // 16:9 Thumbnail with duration & badge
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Stack(
                                    children: [
                                      Image.network(
                                        _selectedYouTubeVideo?.thumbnailUrl ??
                                            'https://img.youtube.com/vi/${UnifiedPlayerController.extractYouTubeVideoId(_mediaUrlController.text) ?? ""}/hqdefault.jpg',
                                        width: 106,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(
                                          width: 106,
                                          height: 60,
                                          color: Colors.black26,
                                          child: const Icon(
                                            Icons.play_arrow_rounded,
                                            color: Color(0xFFFF0000),
                                            size: 28,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 3,
                                        left: 3,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFF0000),
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.play_arrow,
                                                  size: 9, color: Colors.white),
                                              SizedBox(width: 1.5),
                                              Text(
                                                'YouTube',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (_selectedYouTubeVideo != null &&
                                          _selectedYouTubeVideo!
                                              .duration.isNotEmpty)
                                        Positioned(
                                          bottom: 3,
                                          right: 3,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.black
                                                  .withValues(alpha: 0.8),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                            child: Text(
                                              _selectedYouTubeVideo!.duration,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Video title and channel
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedYouTubeVideo?.title ??
                                            'Video YouTube',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                          height: 1.25,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              _selectedYouTubeVideo
                                                      ?.channelTitle ??
                                                  'YouTube',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.verified,
                                              size: 11,
                                              color: AppColors.textSecondary),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Ganti Video Pill Button
                                InkWell(
                                  onTap: _pickAnotherYouTubeVideo,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 9, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white24),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.swap_horiz_rounded,
                                            size: 15,
                                            color: AppColors.textPrimary),
                                        SizedBox(width: 3),
                                        Text(
                                          'Ganti',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Direct URL options (if direct URL)
                        if (_mediaType == 'direct_url') ...[
                          const Text(
                            'Link Video (MP4 / HLS .m3u8) *',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _mediaUrlController,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                              hintText: 'https://example.com/video.mp4',
                              prefixIcon: Icon(
                                Icons.link_rounded,
                                color: AppColors.secondaryNeon,
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'URL media tidak boleh kosong';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: ApiConstants.presetMedia
                                .where((m) => m['type'] == 'direct_url')
                                .map((media) {
                              return ActionChip(
                                label: Text(
                                  media['title']!,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor: AppColors.surfaceElevated,
                                side: const BorderSide(color: AppColors.border),
                                onPressed: () {
                                  setState(() {
                                    _mediaUrlController.text = media['url']!;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Room Title
                        const Text(
                          'Judul Room *',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _titleController,
                          style: const TextStyle(
                              fontSize: 13.5, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Misal: Nonton Bareng Anime',
                            prefixIcon: const Icon(Icons.edit_note_rounded,
                                color: AppColors.primaryNeon, size: 22),
                            suffixIcon: _titleController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded,
                                        size: 18, color: AppColors.textSecondary),
                                    onPressed: () =>
                                        setState(() => _titleController.clear()),
                                  )
                                : null,
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Judul room tidak boleh kosong';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 14),

                        // Hak Kontrol Pemutaran (Compact Segmented Tabs)
                        const Text(
                          'Hak Kontrol Pemutaran',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              // Host Saja
                              Expanded(
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _controlMode = 'host_only'),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 9),
                                    decoration: BoxDecoration(
                                      gradient: _controlMode == 'host_only'
                                          ? AppColors.primaryGradient
                                          : null,
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    alignment: Alignment.center,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.shield_rounded,
                                          size: 15,
                                          color: _controlMode == 'host_only'
                                              ? Colors.white
                                              : AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Host Saja',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight:
                                                _controlMode == 'host_only'
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                            color: _controlMode == 'host_only'
                                              ? Colors.white
                                              : AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // Kolaboratif
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(
                                      () => _controlMode = 'collaborative'),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 9),
                                    decoration: BoxDecoration(
                                      color: _controlMode == 'collaborative'
                                          ? AppColors.secondaryNeon
                                              .withValues(alpha: 0.25)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(9),
                                      border: _controlMode == 'collaborative'
                                          ? Border.all(
                                              color: AppColors.secondaryNeon)
                                          : null,
                                    ),
                                    alignment: Alignment.center,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.group_rounded,
                                          size: 15,
                                          color: _controlMode == 'collaborative'
                                              ? AppColors.secondaryNeon
                                              : AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Kolaboratif',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight:
                                                _controlMode == 'collaborative'
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                            color: _controlMode == 'collaborative'
                                                ? AppColors.secondaryNeon
                                                : AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 5, left: 4),
                        child: Text(
                          _controlMode == 'host_only'
                              ? '🔒 Hanya host yang dapat memutar, menjeda, dan mengatur waktu.'
                              : '🤝 Semua peserta di dalam room bebas mengontrol video.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Room Visibility Card
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: (_isPublic
                                        ? AppColors.secondaryNeon
                                        : AppColors.textSecondary)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _isPublic
                                    ? Icons.public_rounded
                                    : Icons.lock_outline_rounded,
                                size: 18,
                                color: _isPublic
                                    ? AppColors.secondaryNeon
                                    : AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isPublic ? 'Room Publik' : 'Room Privat',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    _isPublic
                                        ? 'Dapat ditemukan di lobby'
                                        : 'Hanya via kode room',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isPublic,
                              activeThumbColor: AppColors.secondaryNeon,
                              onChanged: (val) =>
                                  setState(() => _isPublic = val),
                            ),
                          ],
                        ),
                      ),

                        const SizedBox(height: 14),

                        // Deskripsi (Opsional)
                        const Text(
                          'Deskripsi (Opsional)',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _descController,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            hintText: 'Catatan atau info untuk penonton...',
                            prefixIcon: Icon(Icons.description_outlined,
                                color: AppColors.textSecondary, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Pinned Bottom Action Bar
              Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  10,
                  20,
                  12 + bottomInset + safeBottom,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    top: BorderSide(
                      color: AppColors.border.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleCreate,
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: _isLoading ? null : AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        child: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.rocket_launch_rounded, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Mulai Room Nonton',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
