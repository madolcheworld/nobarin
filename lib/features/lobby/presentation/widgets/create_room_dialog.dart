import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../browser/presentation/bstation_browser_sheet.dart';
import '../../../browser/presentation/youtube_browser_sheet.dart';
import '../../../room/controllers/unified_player_controller.dart';
import '../../../room/models/room_model.dart';
import '../lobby_controller.dart';

class CreateRoomDialog extends ConsumerStatefulWidget {
  final String? initialMediaType;
  final String? initialMediaUrl;
  final String? initialTitle;

  const CreateRoomDialog({
    super.key,
    this.initialMediaType,
    this.initialMediaUrl,
    this.initialTitle,
  });

  /// Shows CreateRoom dialog as a modern modal bottom sheet
  static Future<RoomModel?> show(
    BuildContext context, {
    String? initialMediaType,
    String? initialMediaUrl,
    String? initialTitle,
  }) {
    return showModalBottomSheet<RoomModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateRoomDialog(
        initialMediaType: initialMediaType,
        initialMediaUrl: initialMediaUrl,
        initialTitle: initialTitle,
      ),
    );
  }

  @override
  ConsumerState<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends ConsumerState<CreateRoomDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  final _descController = TextEditingController();

  /// Step 0: Pilih Sumber Video
  /// Step 1: Pengaturan Room
  int _currentStep = 0;

  String? _selectedMediaType;
  String? _selectedMediaUrl;
  String? _selectedVideoTitle;
  String? _selectedVideoId;

  String _controlMode = 'host_only'; // 'host_only' or 'collaborative'
  bool _isPublic = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.initialTitle != null && widget.initialTitle!.isNotEmpty
          ? widget.initialTitle!
          : 'Nonton Bareng',
    );

    if (widget.initialMediaUrl != null && widget.initialMediaUrl!.isNotEmpty) {
      _selectedMediaUrl = widget.initialMediaUrl!;
      final detected = UnifiedPlayerController.detectMediaFromUrl(widget.initialMediaUrl!);
      if (detected?.mediaType == 'bstation' || widget.initialMediaType == 'bstation') {
        _selectedMediaType = 'bstation';
        _selectedVideoId = detected?.mediaId;
        _selectedVideoTitle = widget.initialTitle ?? detected?.title ?? 'Video Bstation';
      } else {
        _selectedMediaType = 'youtube';
        _selectedVideoId = detected?.mediaId;
        _selectedVideoTitle = widget.initialTitle ?? detected?.title ?? 'Video YouTube';
      }
      _currentStep = 1;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _openYouTubeBrowser() {
    YouTubeBrowserSheet.show(
      context,
      mode: YouTubeBrowserMode.createRoom,
      onVideoSelected: (type, url, title) {
        final vId = YoutubePlayerController.convertUrlToId(url);
        setState(() {
          _selectedMediaType = 'youtube';
          _selectedMediaUrl = url;
          _selectedVideoTitle = title.isNotEmpty ? title : 'Video YouTube';
          _selectedVideoId = vId;
          _currentStep = 1;
          if (_titleController.text == 'Nonton Bareng' ||
              _titleController.text.isEmpty ||
              _titleController.text.startsWith('Nobar:')) {
            _titleController.text = title.isNotEmpty && title != 'Video YouTube'
                ? 'Nobar: $title'
                : 'Nobar: YouTube';
          }
        });
      },
    );
  }

  void _openBstationBrowser() {
    BstationBrowserSheet.show(
      context,
      mode: BstationBrowserMode.createRoom,
      onVideoSelected: (type, url, title) {
        setState(() {
          _selectedMediaType = 'bstation';
          _selectedMediaUrl = url;
          _selectedVideoTitle = title.isNotEmpty ? title : 'Video Bstation';
          _selectedVideoId = null;
          _currentStep = 1;
          if (_titleController.text == 'Nonton Bareng' ||
              _titleController.text.isEmpty ||
              _titleController.text.startsWith('Nobar:')) {
            _titleController.text = title.isNotEmpty && title != 'Video Bstation'
                ? 'Nobar: $title'
                : 'Nobar: Bstation';
          }
        });
      },
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedMediaUrl == null || _selectedMediaUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan pilih video terlebih dahulu.')),
      );
      setState(() => _currentStep = 0);
      return;
    }

    final user = ref.read(authControllerProvider).asData?.value;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan login terlebih dahulu.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final room = await ref.read(lobbyControllerProvider.notifier).createRoom(
          title: _titleController.text.trim(),
          description: _descController.text.trim().isEmpty
              ? null
              : _descController.text.trim(),
          hostId: user.id,
          hostName: user.username,
          isPublic: _isPublic,
          controlMode: _controlMode,
          initialMediaType: _selectedMediaType ?? 'youtube',
          initialMediaUrl: _selectedMediaUrl,
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

  Widget _buildStepProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _currentStep == 0
                            ? AppColors.primaryNeon
                            : AppColors.accentGreen,
                      ),
                      child: Center(
                        child: _currentStep > 0
                            ? const Icon(Icons.check, size: 12, color: Colors.black)
                            : const Text(
                                '1',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Pilih Video',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _currentStep == 0
                            ? AppColors.primaryNeon
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.primaryNeon,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _currentStep == 1
                            ? AppColors.primaryNeon
                            : AppColors.surfaceElevated,
                        border: Border.all(
                          color: _currentStep == 1
                              ? AppColors.primaryNeon
                              : AppColors.border,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '2',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _currentStep == 1
                                ? Colors.black
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Pengaturan Room',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _currentStep == 1
                            ? AppColors.primaryNeon
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: _currentStep == 1
                        ? AppColors.primaryNeon
                        : AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBackgroundColor,
    required Color borderColor,
    required List<Color> gradientColors,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBackgroundColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: accentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep1VideoSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Pilih Sumber Video',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tentukan video yang ingin ditonton bersama. Pilih platform di bawah:',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),

        // 1. YouTube Option Card
        _buildSourceOptionCard(
          title: 'YouTube',
          subtitle: 'Jelajahi dan pilih video langsung di YouTube',
          icon: Icons.smart_display_rounded,
          iconColor: Colors.white,
          iconBackgroundColor: AppColors.youtubeRed,
          borderColor: AppColors.youtubeRed.withValues(alpha: 0.5),
          gradientColors: [
            AppColors.youtubeRed.withValues(alpha: 0.18),
            AppColors.surfaceElevated,
          ],
          accentColor: AppColors.youtubeRed,
          onTap: _openYouTubeBrowser,
        ),
        const SizedBox(height: 14),

        // 2. Bstation Option Card
        _buildSourceOptionCard(
          title: 'Bstation / Bilibili',
          subtitle: 'Jelajahi anime dan serial video di Bstation',
          icon: Icons.tv_rounded,
          iconColor: Colors.white,
          iconBackgroundColor: AppColors.bstationBlue,
          borderColor: AppColors.bstationBlue.withValues(alpha: 0.5),
          gradientColors: [
            AppColors.bstationBlue.withValues(alpha: 0.18),
            AppColors.surfaceElevated,
          ],
          accentColor: AppColors.bstationBlue,
          onTap: _openBstationBrowser,
        ),

        // If a video was already selected and user clicked "Ganti Video" / back to step 1
        if (_selectedMediaUrl != null && _selectedMediaUrl!.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => setState(() => _currentStep = 1),
            icon: const Icon(Icons.check_circle_outline_rounded,
                size: 18, color: AppColors.primaryNeon),
            label: Text(
              'Tetap gunakan: ${_selectedVideoTitle ?? "Video Terpilih"}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryNeon,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.primaryNeon, width: 1.2),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildYouTubePreviewCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.youtubeRed.withValues(alpha: 0.5),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Video Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _selectedVideoId != null
                    ? Image.network(
                        'https://img.youtube.com/vi/$_selectedVideoId/hqdefault.jpg',
                        width: 84,
                        height: 54,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 84,
                          height: 54,
                          color: Colors.black26,
                          child: const Icon(Icons.smart_display_rounded,
                              color: AppColors.youtubeRed),
                        ),
                      )
                    : Container(
                        width: 84,
                        height: 54,
                        color: Colors.black26,
                        child: const Icon(Icons.smart_display_rounded,
                            color: AppColors.youtubeRed),
                      ),
              ),
              const SizedBox(width: 12),

              // Title and Source Badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.youtubeRed.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.smart_display_rounded,
                              size: 11, color: AppColors.youtubeRed),
                          SizedBox(width: 4),
                          Text(
                            'YouTube',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.youtubeRed,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedVideoTitle ?? 'Video YouTube',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _currentStep = 0),
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: const Text('Ganti Video', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryNeon,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBstationPreviewCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.bstationBlue.withValues(alpha: 0.5),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Video Thumbnail / Icon
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 84,
                  height: 54,
                  color: AppColors.bstationBlue.withValues(alpha: 0.15),
                  child: const Icon(
                    Icons.tv_rounded,
                    color: AppColors.bstationBlue,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Title and Source Badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.bstationBlue.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tv_rounded,
                              size: 11, color: AppColors.bstationBlue),
                          SizedBox(width: 4),
                          Text(
                            'Bstation',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.bstationBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedVideoTitle ?? 'Video Bstation',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _currentStep = 0),
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: const Text('Ganti Video', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryNeon,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep2RoomSettings() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Selected Video Preview
          const Text(
            'Video Terpilih',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (_selectedMediaType == 'bstation') ...[
            _buildBstationPreviewCard(),
          ] else ...[
            _buildYouTubePreviewCard(),
          ],
          const SizedBox(height: 18),

          // Room Name
          const Text(
            'Nama Room',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _titleController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Contoh: Nonton Bareng Teman',
              prefixIcon: const Icon(Icons.meeting_room_rounded,
                  color: AppColors.primaryNeon, size: 20),
              filled: true,
              fillColor: AppColors.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Nama room tidak boleh kosong';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Description
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
            style: const TextStyle(color: AppColors.textPrimary),
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Catatan atau pengantar untuk peserta...',
              filled: true,
              fillColor: AppColors.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Playback Control Mode
          const Text(
            'Mode Kontrol Pemutaran',
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
                child: _SelectionCard(
                  title: 'Host Only',
                  subtitle: 'Hanya host yang bisa play/pause/seek',
                  icon: Icons.admin_panel_settings_rounded,
                  isSelected: _controlMode == 'host_only',
                  onTap: () => setState(() => _controlMode = 'host_only'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SelectionCard(
                  title: 'Kolaboratif',
                  subtitle: 'Semua peserta bebas mengontrol',
                  icon: Icons.groups_rounded,
                  isSelected: _controlMode == 'collaborative',
                  onTap: () => setState(() => _controlMode = 'collaborative'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Public / Private Switch
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  _isPublic ? Icons.public_rounded : Icons.lock_rounded,
                  color: _isPublic
                      ? AppColors.primaryNeon
                      : AppColors.accentYellow,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isPublic ? 'Room Publik' : 'Room Privat',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        _isPublic
                            ? 'Dapat ditemukan di lobby publik'
                            : 'Hanya dapat diakses via kode room',
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
                  activeThumbColor: AppColors.primaryNeon,
                  onChanged: (val) => setState(() => _isPublic = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Submit Button
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: AppColors.primaryNeon,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.black,
                    ),
                  )
                : const Text(
                    'Buat Room Sekarang',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return PopScope(
      canPop: _currentStep == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentStep == 1) {
          setState(() => _currentStep = 0);
        }
      },
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 600,
            maxHeight: MediaQuery.of(context).size.height * 0.90,
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
                  padding: const EdgeInsets.fromLTRB(16, 4, 12, 6),
                  child: Row(
                    children: [
                      if (_currentStep == 1) ...[
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: AppColors.textPrimary, size: 22),
                          onPressed: () => setState(() => _currentStep = 0),
                          tooltip: 'Kembali ke pilih video',
                        ),
                      ] else ...[
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
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _currentStep == 0
                                  ? 'Pilih Sumber Video'
                                  : 'Pengaturan Room',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              _currentStep == 0
                                  ? 'Langkah 1 dari 2'
                                  : 'Langkah 2 dari 2',
                              style: const TextStyle(
                                fontSize: 11,
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

                // Step progress bar
                _buildStepProgressBar(),

                const Divider(color: AppColors.border, height: 1),

                // Step content
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
                    child: _currentStep == 0
                        ? _buildStep1VideoSelection()
                        : _buildStep2RoomSettings(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SelectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryNeon.withValues(alpha: 0.1)
              : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primaryNeon : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected
                      ? AppColors.primaryNeon
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? AppColors.primaryNeon
                          : AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
