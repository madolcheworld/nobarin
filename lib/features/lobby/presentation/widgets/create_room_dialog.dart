import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../room/controllers/unified_player_controller.dart';
import '../lobby_controller.dart';

class CreateRoomDialog extends ConsumerStatefulWidget {
  const CreateRoomDialog({super.key});

  @override
  ConsumerState<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends ConsumerState<CreateRoomDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _mediaUrlController = TextEditingController();

  String _mediaType = 'direct_url';
  String _controlMode = 'host_only'; // 'host_only' or 'collaborative'
  bool _isPublic = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _titleController.text = 'Nonton Bareng';
    _mediaUrlController.text = ApiConstants.presetMedia[0]['url']!;
    _mediaUrlController.addListener(_onMediaUrlChanged);
  }

  void _onMediaUrlChanged() {
    final text = _mediaUrlController.text.trim();
    if (UnifiedPlayerController.extractYouTubeVideoId(text) != null &&
        _mediaType != 'youtube') {
      setState(() => _mediaType = 'youtube');
    } else if ((text.endsWith('.mp4') ||
            text.endsWith('.m3u8') ||
            text.endsWith('.webm')) &&
        _mediaType != 'direct_url') {
      setState(() => _mediaType = 'direct_url');
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
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_to_queue_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Buat Watch Party Room',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Atur judul, media, dan izin kontrol',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                const Divider(color: AppColors.border),
                const SizedBox(height: 16),

                // Title field
                const Text(
                  'Judul Room *',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    hintText: 'Misal: Nonton Anime Bareng Malam Minggu',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Judul room tidak boleh kosong';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Description field
                const Text(
                  'Deskripsi (Opsional)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _descController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Catatan atau info untuk penonton...',
                  ),
                ),

                const SizedBox(height: 20),

                // Media Type Selector
                const Text(
                  'Pilih Sumber Media',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        avatar: const Icon(Icons.video_library_rounded, size: 16),
                        label: const Text('Direct Video'),
                        selected: _mediaType == 'direct_url',
                        selectedColor: AppColors.secondaryNeon.withValues(alpha: 0.2),
                        side: BorderSide(
                          color: _mediaType == 'direct_url'
                              ? AppColors.secondaryNeon
                              : AppColors.border,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _mediaType = 'direct_url';
                              _mediaUrlController.text =
                                  ApiConstants.presetMedia[0]['url']!;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        avatar: const Icon(Icons.play_circle_filled, size: 16),
                        label: const Text('YouTube'),
                        selected: _mediaType == 'youtube',
                        selectedColor: AppColors.accentRed.withValues(alpha: 0.2),
                        side: BorderSide(
                          color: _mediaType == 'youtube'
                              ? AppColors.accentRed
                              : AppColors.border,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _mediaType = 'youtube';
                              _mediaUrlController.text =
                                  ApiConstants.presetMedia[3]['url']!;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Media URL field
                TextFormField(
                  controller: _mediaUrlController,
                  decoration: InputDecoration(
                    labelText: _mediaType == 'youtube'
                        ? 'Link Video YouTube'
                        : 'Direct URL (MP4 / HLS .m3u8)',
                    prefixIcon: Icon(
                      _mediaType == 'youtube'
                          ? Icons.link_rounded
                          : Icons.movie_creation_outlined,
                      color: _mediaType == 'youtube'
                          ? AppColors.accentRed
                          : AppColors.secondaryNeon,
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'URL media tidak boleh kosong';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 10),

                // Preset Chips
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: ApiConstants.presetMedia
                      .where((m) => m['type'] == _mediaType)
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

                const SizedBox(height: 20),

                // Control Mode
                const Text(
                  'Hak Kontrol Pemutaran',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () =>
                            setState(() => _controlMode = 'host_only'),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _controlMode == 'host_only'
                                ? AppColors.primaryNeon.withValues(alpha: 0.15)
                                : AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _controlMode == 'host_only'
                                  ? AppColors.primaryNeon
                                  : AppColors.border,
                            ),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '👑 Host Only',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Hanya host yang bisa play, pause & seek.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () =>
                            setState(() => _controlMode = 'collaborative'),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _controlMode == 'collaborative'
                                ? AppColors.secondaryNeon.withValues(alpha: 0.15)
                                : AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _controlMode == 'collaborative'
                                  ? AppColors.secondaryNeon
                                  : AppColors.border,
                            ),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🤝 Kolaboratif',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Semua peserta bebas mengontrol video.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Visibility Toggle
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Publikasikan di Lobby Publik',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Jika dimatikan, room hanya bisa diakses lewat kode atau link.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  value: _isPublic,
                  activeThumbColor: AppColors.primaryNeon,
                  onChanged: (val) => setState(() => _isPublic = val),
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
                        onPressed: _isLoading ? null : _handleCreate,
                        child: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Buat Room'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
