import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/p2p_file_stream_service.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../browser/presentation/bstation_browser_sheet.dart';
import '../../../browser/presentation/dailymotion_browser_sheet.dart';
import '../../../browser/presentation/google_drive_browser_sheet.dart';
import '../../../browser/presentation/web_browser_sheet.dart';
import '../../../browser/presentation/youtube_browser_sheet.dart';
import '../../../room/controllers/dailymotion_player_controller.dart';
import '../../../room/controllers/google_drive_player_controller.dart';
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
      enableDrag: false,
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
  String? _selectedLocalFileSize;

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
      } else if (detected?.mediaType == 'dailymotion' || widget.initialMediaType == 'dailymotion') {
        _selectedMediaType = 'dailymotion';
        _selectedVideoId = detected?.mediaId;
        _selectedVideoTitle = widget.initialTitle ?? detected?.title ?? 'Video Dailymotion';
      } else if (detected?.mediaType == 'google_drive' ||
          widget.initialMediaType == 'google_drive' ||
          widget.initialMediaType == 'gdrive') {
        _selectedMediaType = 'google_drive';
        _selectedVideoId = detected?.mediaId;
        _selectedVideoTitle = widget.initialTitle ?? detected?.title ?? 'Video Google Drive';
      } else if (detected?.mediaType == 'web_browser' ||
          widget.initialMediaType == 'web_browser') {
        _selectedMediaType = 'web_browser';
        _selectedVideoId = null;
        _selectedVideoTitle = widget.initialTitle ?? detected?.title ?? 'Video Web Browser';
      } else if (widget.initialMediaType == 'screenshare' || widget.initialMediaUrl == 'screenshare') {
        _selectedMediaType = 'screenshare';
        _selectedVideoId = null;
        _selectedVideoTitle = widget.initialTitle ?? 'Mirror Layar (Screen Share)';
      } else if (detected?.isDirectUrl == true && UnifiedPlayerController.isLocalFilePath(widget.initialMediaUrl!)) {
        _selectedMediaType = 'direct_url';
        _selectedVideoTitle = widget.initialTitle ?? detected?.title ?? 'File Video Lokal';
      } else if (detected?.isDirectUrl == true || widget.initialMediaType == 'direct_url') {
        _selectedMediaType = 'direct_url';
        _selectedVideoTitle = widget.initialTitle ?? detected?.title ?? 'Video Stream';
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
        final vId = UnifiedPlayerController.extractYoutubeId(url);
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

  void _openDailymotionBrowser() {
    DailymotionBrowserSheet.show(
      context,
      mode: DailymotionBrowserMode.createRoom,
      onVideoSelected: (type, url, title) {
        final vId = DailymotionPlayerController.extractVideoId(url);
        setState(() {
          _selectedMediaType = 'dailymotion';
          _selectedMediaUrl = url;
          _selectedVideoTitle = title.isNotEmpty ? title : 'Video Dailymotion';
          _selectedVideoId = vId;
          _currentStep = 1;
          if (_titleController.text == 'Nonton Bareng' ||
              _titleController.text.isEmpty ||
              _titleController.text.startsWith('Nobar:')) {
            _titleController.text = title.isNotEmpty && title != 'Video Dailymotion'
                ? 'Nobar: $title'
                : 'Nobar: Dailymotion';
          }
        });
      },
    );
  }

  void _openGoogleDriveBrowser() {
    GoogleDriveBrowserSheet.show(
      context,
      mode: GoogleDriveBrowserMode.createRoom,
      onVideoSelected: (type, url, title) {
        final fId = GoogleDrivePlayerController.extractFileId(url);
        setState(() {
          _selectedMediaType = 'google_drive';
          _selectedMediaUrl = url;
          _selectedVideoTitle = title.isNotEmpty ? title : 'Video Google Drive';
          _selectedVideoId = fId;
          _currentStep = 1;
          if (_titleController.text == 'Nonton Bareng' ||
              _titleController.text.isEmpty ||
              _titleController.text.startsWith('Nobar:')) {
            _titleController.text = title.isNotEmpty && title != 'Video Google Drive'
                ? 'Nobar: $title'
                : 'Nobar: Google Drive';
          }
        });
      },
    );
  }

  void _openWebBrowser() {
    WebBrowserSheet.show(
      context,
      mode: WebBrowserMode.createRoom,
      onVideoSelected: (type, url, title) {
        setState(() {
          _selectedMediaType = type;
          _selectedMediaUrl = url;
          _selectedVideoTitle = title.isNotEmpty ? title : 'Video Web Browser';
          _selectedVideoId = null;
          _currentStep = 1;
          if (_titleController.text == 'Nonton Bareng' ||
              _titleController.text.isEmpty ||
              _titleController.text.startsWith('Nobar:')) {
            _titleController.text =
                title.isNotEmpty && title != 'Video Web Browser'
                    ? 'Nobar: $title'
                    : 'Nobar: Web Browser';
          }
        });
      },
    );
  }

  void _pickLocalVideoFile() async {
    try {
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

      setState(() {
        _selectedMediaType = 'direct_url';
        _selectedMediaUrl = path;
        _selectedVideoTitle = fileName;
        _selectedVideoId = null;
        _selectedLocalFileSize = '$sizeMb MB';
        _currentStep = 1;
        if (_titleController.text == 'Nonton Bareng' ||
            _titleController.text.isEmpty ||
            _titleController.text.startsWith('Nobar:')) {
          _titleController.text = 'Nobar: $fileName';
        }
      });
    } catch (e) {
      debugPrint('[CreateRoomDialog] Error picking local file: $e');
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

  void _selectScreenShareSource() {
    setState(() {
      _selectedMediaType = 'screenshare';
      _selectedMediaUrl = 'screenshare';
      _selectedVideoTitle = 'Mirror Layar (Screen Share)';
      _selectedVideoId = null;
      _currentStep = 1;
      if (_titleController.text == 'Nonton Bareng' ||
          _titleController.text.isEmpty ||
          _titleController.text.startsWith('Nobar:')) {
        _titleController.text = 'Nobar: Mirror Layar';
      }
    });
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

    String? initialMediaUrl = _selectedMediaUrl;
    // If local video file is selected, initiate P2P hosting so LAN server is immediately available on native
    if (!kIsWeb &&
        _selectedMediaType == 'direct_url' &&
        _selectedMediaUrl != null &&
        UnifiedPlayerController.isLocalFilePath(_selectedMediaUrl!)) {
      try {
        final metadata = await P2PFileStreamService.instance.hostFile(
          filePath: _selectedMediaUrl!,
          hostUserId: user.id,
          hostUserName: user.username,
        );
        if (metadata.lanUrl != null && metadata.lanUrl!.isNotEmpty) {
          initialMediaUrl = metadata.lanUrl;
        }
      } catch (e) {
        debugPrint('[CreateRoomDialog] P2P host notice: $e');
      }
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
          initialMediaType: _selectedMediaType ?? 'youtube',
          initialMediaUrl: initialMediaUrl,
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.primaryNeon,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: _currentStep == 1
                    ? AppColors.primaryNeon
                    : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
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
    String? badgeText,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: iconBackgroundColor.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (badgeText != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: accentColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 13,
                    color: accentColor,
                  ),
                ),
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
        // 1. YouTube Option Card
        _buildSourceOptionCard(
          title: 'YouTube',
          subtitle: 'Streaming dan video musik',
          icon: Icons.smart_display_rounded,
          iconColor: Colors.white,
          iconBackgroundColor: AppColors.youtubeRed,
          borderColor: AppColors.youtubeRed.withValues(alpha: 0.45),
          gradientColors: [
            AppColors.youtubeRed.withValues(alpha: 0.16),
            AppColors.surfaceElevated,
          ],
          accentColor: AppColors.youtubeRed,
          badgeText: 'Populer',
          onTap: _openYouTubeBrowser,
        ),
        const SizedBox(height: 12),

        // 2. Bstation Option Card
        _buildSourceOptionCard(
          title: 'Bstation / Bilibili',
          subtitle: 'Anime & serial video',
          icon: Icons.tv_rounded,
          iconColor: Colors.white,
          iconBackgroundColor: AppColors.bstationBlue,
          borderColor: AppColors.bstationBlue.withValues(alpha: 0.45),
          gradientColors: [
            AppColors.bstationBlue.withValues(alpha: 0.16),
            AppColors.surfaceElevated,
          ],
          accentColor: AppColors.bstationBlue,
          badgeText: 'Anime',
          onTap: _openBstationBrowser,
        ),
        const SizedBox(height: 12),

        // 3. Dailymotion Option Card
        _buildSourceOptionCard(
          title: 'Dailymotion',
          subtitle: 'Video berita, musik, & hiburan',
          icon: Icons.play_circle_filled_rounded,
          iconColor: Colors.white,
          iconBackgroundColor: AppColors.dailymotionBlue,
          borderColor: AppColors.dailymotionBlue.withValues(alpha: 0.45),
          gradientColors: [
            AppColors.dailymotionBlue.withValues(alpha: 0.16),
            AppColors.surfaceElevated,
          ],
          accentColor: AppColors.dailymotionBlue,
          badgeText: 'Trending',
          onTap: _openDailymotionBrowser,
        ),
        const SizedBox(height: 12),

        // 4. Google Drive Option Card
        _buildSourceOptionCard(
          title: 'Google Drive',
          subtitle: 'Putar video dari akun Google Drive Anda',
          icon: Icons.add_to_drive_rounded,
          iconColor: Colors.white,
          iconBackgroundColor: AppColors.googleDriveGreen,
          borderColor: AppColors.googleDriveGreen.withValues(alpha: 0.45),
          gradientColors: [
            AppColors.googleDriveGreen.withValues(alpha: 0.16),
            AppColors.surfaceElevated,
          ],
          accentColor: AppColors.googleDriveGreen,
          badgeText: 'Drive',
          onTap: _openGoogleDriveBrowser,
        ),
        const SizedBox(height: 12),

        // 5. Web Browser (Auto-Detect Video) Option Card
        _buildSourceOptionCard(
          title: 'Web Browser',
          subtitle: 'Buka situs apa saja & deteksi otomatis video yang diputar',
          icon: Icons.public_rounded,
          iconColor: Colors.black,
          iconBackgroundColor: AppColors.webBrowserTeal,
          borderColor: AppColors.webBrowserTeal.withValues(alpha: 0.5),
          gradientColors: [
            AppColors.webBrowserTeal.withValues(alpha: 0.16),
            AppColors.surfaceElevated,
          ],
          accentColor: AppColors.webBrowserTeal,
          badgeText: 'Auto-Detect',
          onTap: _openWebBrowser,
        ),
        const SizedBox(height: 12),

        // 6. Local Video File (Direct P2P Streaming) Option Card
        _buildSourceOptionCard(
          title: 'File Video Lokal (P2P)',
          subtitle: 'Stream video dari memori HP/PC tanpa upload',
          icon: Icons.folder_special_rounded,
          iconColor: Colors.white,
          iconBackgroundColor: AppColors.p2pPurple,
          borderColor: AppColors.p2pPurple.withValues(alpha: 0.5),
          gradientColors: [
            AppColors.p2pPurple.withValues(alpha: 0.18),
            AppColors.surfaceElevated,
          ],
          accentColor: AppColors.p2pPurple,
          badgeText: 'P2P',
          onTap: _pickLocalVideoFile,
        ),
        const SizedBox(height: 12),

        // 5. Mirror Device / Screen Sharing Option Card
        _buildSourceOptionCard(
          title: 'Mirror Layar / Bagikan Layar',
          subtitle: 'Siarkan layar HP Anda via WebRTC langsung ke room',
          icon: Icons.mobile_screen_share_rounded,
          iconColor: Colors.white,
          iconBackgroundColor: AppColors.secondaryNeon,
          borderColor: AppColors.secondaryNeon.withValues(alpha: 0.5),
          gradientColors: [
            AppColors.secondaryNeon.withValues(alpha: 0.18),
            AppColors.surfaceElevated,
          ],
          accentColor: AppColors.secondaryNeon,
          badgeText: 'Real-time',
          onTap: _selectScreenShareSource,
        ),

        // If a video was already selected and user clicked "Ganti Video" / back to step 1
        if (_selectedMediaUrl != null && _selectedMediaUrl!.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => setState(() => _currentStep = 1),
            icon: const Icon(Icons.check_circle_rounded,
                size: 19, color: AppColors.accentGreen),
            label: Text(
              'Tetap gunakan: ${_selectedVideoTitle ?? "Video Terpilih"}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.primaryNeon.withValues(alpha: 0.16),
              side: BorderSide(
                color: AppColors.primaryNeonLight.withValues(alpha: 0.65),
                width: 1.4,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildChangeVideoButton() {
    return InkWell(
      onTap: () => setState(() => _currentStep = 0),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primaryNeon.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.primaryNeonLight.withValues(alpha: 0.55),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.swap_horiz_rounded,
              size: 16,
              color: AppColors.primaryNeonLight,
            ),
            SizedBox(width: 5),
            Text(
              'Ganti Video',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryNeonLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: AppColors.accentGreen.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: AppColors.accentGreen.withValues(alpha: 0.5),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded,
              size: 11, color: AppColors.accentGreen),
          SizedBox(width: 3),
          Text(
            'Terpilih',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: AppColors.accentGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYouTubePreviewCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.surfaceHighlight,
            AppColors.surfaceElevated,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.youtubeRed.withValues(alpha: 0.65),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Video Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: _selectedVideoId != null
                    ? Image.network(
                        'https://img.youtube.com/vi/$_selectedVideoId/hqdefault.jpg',
                        width: 88,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 88,
                          height: 56,
                          color: Colors.black26,
                          child: const Icon(Icons.smart_display_rounded,
                              color: AppColors.youtubeRed),
                        ),
                      )
                    : Container(
                        width: 88,
                        height: 56,
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
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildSelectedBadge(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: AppColors.youtubeRed.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.smart_display_rounded,
                                  size: 12, color: AppColors.youtubeRed),
                              SizedBox(width: 4),
                              Text(
                                'YouTube',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.youtubeRed,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _selectedVideoTitle ?? 'Video YouTube',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildChangeVideoButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBstationPreviewCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.surfaceHighlight,
            AppColors.surfaceElevated,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.bstationBlue.withValues(alpha: 0.65),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Video Thumbnail / Icon
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  width: 88,
                  height: 56,
                  color: AppColors.bstationBlue.withValues(alpha: 0.18),
                  child: const Icon(
                    Icons.tv_rounded,
                    color: AppColors.bstationBlue,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Title and Source Badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildSelectedBadge(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color:
                                AppColors.bstationBlue.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.tv_rounded,
                                  size: 12, color: AppColors.bstationBlue),
                              SizedBox(width: 4),
                              Text(
                                'Bstation',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.bstationBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _selectedVideoTitle ?? 'Video Bstation',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildChangeVideoButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDailymotionPreviewCard() {
    final thumbUrl = _selectedVideoId != null
        ? 'https://www.dailymotion.com/thumbnail/video/$_selectedVideoId'
        : null;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.surfaceHighlight,
            AppColors.surfaceElevated,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.dailymotionBlue.withValues(alpha: 0.65),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Video Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: thumbUrl != null
                    ? Image.network(
                        thumbUrl,
                        width: 88,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 88,
                          height: 56,
                          color:
                              AppColors.dailymotionBlue.withValues(alpha: 0.18),
                          child: const Icon(
                            Icons.play_circle_filled_rounded,
                            color: AppColors.dailymotionBlue,
                            size: 28,
                          ),
                        ),
                      )
                    : Container(
                        width: 88,
                        height: 56,
                        color:
                            AppColors.dailymotionBlue.withValues(alpha: 0.18),
                        child: const Icon(
                          Icons.play_circle_filled_rounded,
                          color: AppColors.dailymotionBlue,
                          size: 28,
                        ),
                      ),
              ),
              const SizedBox(width: 12),

              // Title and Source Badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildSelectedBadge(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: AppColors.dailymotionBlue
                                .withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_circle_filled_rounded,
                                  size: 12, color: AppColors.dailymotionBlue),
                              SizedBox(width: 4),
                              Text(
                                'Dailymotion',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.dailymotionBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _selectedVideoTitle ?? 'Video Dailymotion',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildChangeVideoButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleDrivePreviewCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.surfaceHighlight,
            AppColors.surfaceElevated,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.googleDriveGreen.withValues(alpha: 0.65),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon container as thumbnail placeholder
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  width: 88,
                  height: 56,
                  color: AppColors.googleDriveGreen.withValues(alpha: 0.18),
                  child: const Center(
                    child: Icon(
                      Icons.add_to_drive_rounded,
                      size: 28,
                      color: AppColors.googleDriveGreen,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6.5,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.googleDriveGreen.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_to_drive_rounded,
                                size: 12,
                                color: AppColors.googleDriveGreen,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Google Drive',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.googleDriveGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _selectedVideoTitle ?? 'Video Google Drive',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildChangeVideoButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocalVideoPreviewCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.surfaceHighlight,
            AppColors.surfaceElevated,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.p2pPurple.withValues(alpha: 0.65),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  width: 88,
                  height: 56,
                  color: AppColors.p2pPurple.withValues(alpha: 0.18),
                  child: const Center(
                    child: Icon(
                      Icons.folder_special_rounded,
                      color: AppColors.p2pPurple,
                      size: 28,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Title, File Size and Source Badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildSelectedBadge(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: AppColors.p2pPurple.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.stream_rounded,
                                  size: 12, color: AppColors.p2pPurple),
                              SizedBox(width: 4),
                              Text(
                                'File Lokal P2P',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.p2pPurple,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_selectedLocalFileSize != null)
                          Text(
                            _selectedLocalFileSize!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _selectedVideoTitle ?? 'File Video Lokal',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildChangeVideoButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScreenSharePreviewCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.surfaceHighlight,
            AppColors.surfaceElevated,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.secondaryNeon.withValues(alpha: 0.65),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  width: 88,
                  height: 56,
                  color: AppColors.secondaryNeon.withValues(alpha: 0.18),
                  child: const Center(
                    child: Icon(
                      Icons.mobile_screen_share_rounded,
                      color: AppColors.secondaryNeon,
                      size: 28,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Title and Source Badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildSelectedBadge(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: AppColors.secondaryNeon.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.mobile_screen_share_rounded,
                                  size: 12, color: AppColors.secondaryNeon),
                              SizedBox(width: 4),
                              Text(
                                'Mirror Layar',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.secondaryNeon,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accentGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'WebRTC P2P',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.accentGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _selectedVideoTitle ?? 'Mirror Layar (Screen Share)',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Layar HP Anda akan disiarkan langsung via WebRTC saat masuk room',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildChangeVideoButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebBrowserPreviewCard() {
    final isDirectStream = _selectedMediaType == 'direct_url';
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.surfaceHighlight,
            AppColors.surfaceElevated,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.webBrowserTeal.withValues(alpha: 0.65),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  width: 88,
                  height: 56,
                  color: AppColors.webBrowserTeal.withValues(alpha: 0.18),
                  child: const Center(
                    child: Icon(
                      Icons.public_rounded,
                      size: 28,
                      color: AppColors.webBrowserTeal,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildSelectedBadge(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6.5,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.webBrowserTeal
                                .withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.public_rounded,
                                size: 12,
                                color: AppColors.webBrowserTeal,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isDirectStream
                                    ? 'Web Stream'
                                    : 'Web Browser',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.webBrowserTeal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _selectedVideoTitle ?? 'Video Web Browser',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildChangeVideoButton(),
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
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          if (_selectedMediaType == 'bstation') ...[
            _buildBstationPreviewCard(),
          ] else if (_selectedMediaType == 'dailymotion') ...[
            _buildDailymotionPreviewCard(),
          ] else if (_selectedMediaType == 'google_drive') ...[
            _buildGoogleDrivePreviewCard(),
          ] else if (_selectedMediaType == 'web_browser') ...[
            _buildWebBrowserPreviewCard(),
          ] else if (_selectedMediaType == 'screenshare') ...[
            _buildScreenSharePreviewCard(),
          ] else if (_selectedMediaType == 'direct_url' &&
              _selectedMediaUrl != null &&
              UnifiedPlayerController.isLocalFilePath(_selectedMediaUrl!)) ...[
            _buildLocalVideoPreviewCard(),
          ] else if (_selectedMediaType == 'direct_url') ...[
            _buildWebBrowserPreviewCard(),
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
                  subtitle: 'Hanya host yang mengontrol',
                  icon: Icons.admin_panel_settings_rounded,
                  isSelected: _controlMode == 'host_only',
                  onTap: () => setState(() => _controlMode = 'host_only'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SelectionCard(
                  title: 'Kolaboratif',
                  subtitle: 'Semua peserta bisa kontrol',
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
                            ? 'Tampil di lobby publik'
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
                  activeThumbColor: AppColors.primaryNeon,
                  onChanged: (val) => setState(() => _isPublic = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Submit Button
          Container(
            height: 50,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryNeon.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _isLoading
                  ? const SizedBox.shrink()
                  : const Icon(
                      Icons.play_circle_fill_rounded,
                      size: 22,
                      color: Colors.white,
                    ),
              label: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Buat Room Sekarang',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
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
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return PopScope(
      canPop: !_isLoading && _currentStep == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _isLoading) return;
        if (_currentStep == 1) {
          setState(() => _currentStep = 0);
        }
      },
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: 600,
                maxHeight: MediaQuery.of(context).size.height * 0.90,
              ),
              decoration: BoxDecoration(
                color: AppColors.glassFillHeavy,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(
                  color: AppColors.glassBorderHighlight,
                  width: 1.1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: Stack(
              children: [
                Column(
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
                              onPressed: _isLoading
                                  ? null
                                  : () => setState(() => _currentStep = 0),
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
                            onPressed: _isLoading
                                ? null
                                : () => Navigator.of(context).pop(),
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
                        key: ValueKey<int>(_currentStep),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          20,
                          16,
                          20,
                          18 + bottomInset + (safeBottom > 0 ? safeBottom : 12),
                        ),
                        child: _currentStep == 0
                            ? _buildStep1VideoSelection()
                            : _buildStep2RoomSettings(),
                      ),
                    ),
                  ],
                ),

                // Full loading overlay when room creation is in progress
                if (_isLoading)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.92),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: AppColors.primaryGradient,
                                  boxShadow: AppColors.neonVioletGlow,
                                ),
                                child: const Center(
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Sedang Membuat Room...',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Mendaftarkan room & menyiapkan media player',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryNeon.withValues(alpha: 0.15)
              : AppColors.glassFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primaryNeon : AppColors.glassBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected ? AppColors.neonVioletGlow : null,
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
