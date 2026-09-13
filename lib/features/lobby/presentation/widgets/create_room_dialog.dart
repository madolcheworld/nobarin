import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../room/controllers/unified_player_controller.dart';
import '../../../room/models/room_model.dart';
import '../../data/models/bstation_video_model.dart';
import '../../data/models/playable_media_item.dart';
import '../../data/models/dailymotion_video_model.dart';
import '../../data/models/google_drive_video_model.dart';
import '../../data/models/twitch_stream_model.dart';
import '../../data/models/vimeo_video_model.dart';
import '../../data/models/youtube_video_model.dart';
import '../../data/bstation_service.dart';
import '../../data/dailymotion_service.dart';
import '../../data/google_drive_service.dart';
import '../../data/twitch_service.dart';
import '../../data/vimeo_service.dart';
import '../../data/youtube_service.dart';
import '../lobby_controller.dart';
import '../screens/bstation_picker_screen.dart';
import '../screens/dailymotion_picker_screen.dart';
import '../screens/google_drive_picker_screen.dart';
import '../screens/twitch_picker_screen.dart';
import '../screens/vimeo_picker_screen.dart';
import '../screens/youtube_picker_screen.dart';

class CreateRoomDialog extends ConsumerStatefulWidget {
  final YouTubeVideo? initialYouTubeVideo;
  final TwitchStream? initialTwitchStream;
  final VimeoVideo? initialVimeoVideo;
  final GoogleDriveVideo? initialGoogleDriveVideo;
  final DailymotionVideo? initialDailymotionVideo;
  final BstationVideo? initialBstationVideo;
  final String? initialMediaType;
  final String? initialMediaUrl;
  final void Function(PlayableMediaItem item)? onChangeVideo;

  const CreateRoomDialog({
    super.key,
    this.initialYouTubeVideo,
    this.initialTwitchStream,
    this.initialVimeoVideo,
    this.initialGoogleDriveVideo,
    this.initialDailymotionVideo,
    this.initialBstationVideo,
    this.initialMediaType,
    this.initialMediaUrl,
    this.onChangeVideo,
  });

  /// Shows CreateRoom dialog as a modern modal bottom sheet
  static Future<RoomModel?> show(
    BuildContext context, {
    YouTubeVideo? initialYouTubeVideo,
    TwitchStream? initialTwitchStream,
    VimeoVideo? initialVimeoVideo,
    GoogleDriveVideo? initialGoogleDriveVideo,
    DailymotionVideo? initialDailymotionVideo,
    BstationVideo? initialBstationVideo,
    String? initialMediaType,
    String? initialMediaUrl,
  }) {
    return showModalBottomSheet<RoomModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateRoomDialog(
        initialYouTubeVideo: initialYouTubeVideo,
        initialTwitchStream: initialTwitchStream,
        initialVimeoVideo: initialVimeoVideo,
        initialGoogleDriveVideo: initialGoogleDriveVideo,
        initialDailymotionVideo: initialDailymotionVideo,
        initialBstationVideo: initialBstationVideo,
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
  Timer? _urlDebounceTimer;

  YouTubeVideo? _selectedYouTubeVideo;
  TwitchStream? _selectedTwitchStream;
  VimeoVideo? _selectedVimeoVideo;
  GoogleDriveVideo? _selectedGoogleDriveVideo;
  DailymotionVideo? _selectedDailymotionVideo;
  BstationVideo? _selectedBstationVideo;
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
    } else if (widget.initialTwitchStream != null) {
      _selectedTwitchStream = widget.initialTwitchStream;
      _mediaType = 'twitch';
      _mediaUrlController.text = widget.initialTwitchStream!.url;
      _titleController.text = widget.initialTwitchStream!.title;
    } else if (widget.initialVimeoVideo != null) {
      _selectedVimeoVideo = widget.initialVimeoVideo;
      _mediaType = 'vimeo';
      _mediaUrlController.text = widget.initialVimeoVideo!.url;
      _titleController.text = widget.initialVimeoVideo!.title;
    } else if (widget.initialGoogleDriveVideo != null) {
      _selectedGoogleDriveVideo = widget.initialGoogleDriveVideo;
      _mediaType = 'google_drive';
      _mediaUrlController.text = widget.initialGoogleDriveVideo!.url;
      _titleController.text = widget.initialGoogleDriveVideo!.title;
    } else if (widget.initialDailymotionVideo != null) {
      _selectedDailymotionVideo = widget.initialDailymotionVideo;
      _mediaType = 'dailymotion';
      _mediaUrlController.text = widget.initialDailymotionVideo!.url;
      _titleController.text = widget.initialDailymotionVideo!.title;
    } else if (widget.initialBstationVideo != null) {
      _selectedBstationVideo = widget.initialBstationVideo;
      _mediaType = 'bstation';
      _mediaUrlController.text = widget.initialBstationVideo!.url;
      _titleController.text = widget.initialBstationVideo!.title;
    } else if (widget.initialMediaUrl != null) {
      _mediaType = widget.initialMediaType ?? 'direct_url';
      _mediaUrlController.text = widget.initialMediaUrl!;
      _titleController.text = 'Nonton Bareng';
    } else if (widget.initialMediaType == 'twitch') {
      _mediaType = 'twitch';
      final twitchPresets = TwitchService.categoryPresets['Populer & Live'] ?? [];
      if (twitchPresets.isNotEmpty) {
        _selectedTwitchStream = twitchPresets[0];
        _mediaUrlController.text = twitchPresets[0].url;
        _titleController.text = twitchPresets[0].title;
      } else {
        _mediaUrlController.text = 'https://www.twitch.tv/monstercat';
        _titleController.text = 'Nonton Twitch';
      }
    } else if (widget.initialMediaType == 'vimeo') {
      _mediaType = 'vimeo';
      final vimeoPresets = VimeoService.categoryPresets['Staff Picks'] ?? [];
      if (vimeoPresets.isNotEmpty) {
        _selectedVimeoVideo = vimeoPresets[0];
        _mediaUrlController.text = vimeoPresets[0].url;
        _titleController.text = vimeoPresets[0].title;
      } else {
        _mediaUrlController.text = 'https://vimeo.com/76979871';
        _titleController.text = 'Nonton Vimeo';
      }
    } else if (widget.initialMediaType == 'google_drive') {
      _mediaType = 'google_drive';
      final drivePresets = GoogleDriveService.categoryPresets['Film & Animasi Open Source'] ?? [];
      if (drivePresets.isNotEmpty) {
        _selectedGoogleDriveVideo = drivePresets[0];
        _mediaUrlController.text = drivePresets[0].url;
        _titleController.text = drivePresets[0].title;
      } else {
        _mediaUrlController.text = 'https://drive.google.com/file/d/1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8/preview';
        _titleController.text = 'Nonton Google Drive';
      }
    } else if (widget.initialMediaType == 'dailymotion') {
      _mediaType = 'dailymotion';
      final dmPresets = DailymotionService.categoryPresets['Trending'] ?? [];
      if (dmPresets.isNotEmpty) {
        _selectedDailymotionVideo = dmPresets[0];
        _mediaUrlController.text = dmPresets[0].url;
        _titleController.text = dmPresets[0].title;
      } else {
        _mediaUrlController.text = 'https://www.dailymotion.com/video/x7tgad0';
        _titleController.text = 'Nonton Dailymotion';
      }
    } else if (widget.initialMediaType == 'bstation' ||
        widget.initialMediaType == 'bilibili') {
      _mediaType = 'bstation';
      final bsPresets = BstationService.categoryPresets['Anime Populer'] ?? [];
      if (bsPresets.isNotEmpty) {
        _selectedBstationVideo = bsPresets[0];
        _mediaUrlController.text = bsPresets[0].url;
        _titleController.text = bsPresets[0].title;
      } else {
        _mediaUrlController.text = 'https://www.bilibili.tv/id/video/2049971954';
        _titleController.text = 'Nonton Bstation';
      }
    } else {
      _titleController.text = 'Nonton Bareng';
      _mediaUrlController.text = ApiConstants.presetMedia[0]['url']!;
    }
    _mediaUrlController.addListener(_onMediaUrlChanged);
  }

  void _onMediaUrlChanged() {
    _urlDebounceTimer?.cancel();
    final text = _mediaUrlController.text.trim();
    final ytId = UnifiedPlayerController.extractYouTubeVideoId(text);
    final twitchMedia = UnifiedPlayerController.extractTwitchMedia(text);
    final vimeoId = UnifiedPlayerController.extractVimeoVideoId(text);
    final driveId = GoogleDriveService.extractFileId(text);
    final dmId = UnifiedPlayerController.extractDailymotionVideoId(text);
    final bsId = UnifiedPlayerController.extractBstationVideoId(text);

    if (ytId != null) {
      if (_mediaType != 'youtube') {
        setState(() {
          _mediaType = 'youtube';
          _selectedTwitchStream = null;
          _selectedVimeoVideo = null;
          _selectedGoogleDriveVideo = null;
          _selectedDailymotionVideo = null;
          _selectedBstationVideo = null;
        });
      }
      if (_selectedYouTubeVideo == null || _selectedYouTubeVideo!.id != ytId) {
        _urlDebounceTimer = Timer(const Duration(milliseconds: 400), () {
          YouTubeService.fetchVideoDetails(ytId).then((v) {
            if (mounted) setState(() => _selectedYouTubeVideo = v);
          });
        });
      }
    } else if (twitchMedia != null) {
      if (_mediaType != 'twitch') {
        setState(() {
          _mediaType = 'twitch';
          _selectedYouTubeVideo = null;
          _selectedVimeoVideo = null;
          _selectedGoogleDriveVideo = null;
          _selectedDailymotionVideo = null;
          _selectedBstationVideo = null;
        });
      }
      final channel = twitchMedia.id;
      if (_selectedTwitchStream == null ||
          _selectedTwitchStream!.id.toLowerCase() != channel.toLowerCase()) {
        setState(() {
          _selectedTwitchStream = TwitchStream.fromId(
            id: channel,
            title: 'Twitch Channel ($channel)',
            channelTitle: channel,
          );
        });
      }
    } else if (vimeoId != null) {
      if (_mediaType != 'vimeo') {
        setState(() {
          _mediaType = 'vimeo';
          _selectedYouTubeVideo = null;
          _selectedTwitchStream = null;
          _selectedGoogleDriveVideo = null;
          _selectedDailymotionVideo = null;
          _selectedBstationVideo = null;
        });
      }
      if (_selectedVimeoVideo == null || _selectedVimeoVideo!.id != vimeoId) {
        _urlDebounceTimer = Timer(const Duration(milliseconds: 400), () {
          VimeoService.fetchVideoDetails(vimeoId).then((v) {
            if (mounted) setState(() => _selectedVimeoVideo = v);
          });
        });
      }
    } else if (driveId != null) {
      if (_mediaType != 'google_drive') {
        setState(() {
          _mediaType = 'google_drive';
          _selectedYouTubeVideo = null;
          _selectedTwitchStream = null;
          _selectedVimeoVideo = null;
          _selectedDailymotionVideo = null;
          _selectedBstationVideo = null;
        });
      }
      if (_selectedGoogleDriveVideo == null ||
          _selectedGoogleDriveVideo!.id != driveId) {
        final allPresets =
            GoogleDriveService.categoryPresets.values.expand((v) => v);
        final matched = allPresets.where((v) => v.id == driveId);
        if (matched.isNotEmpty) {
          setState(() => _selectedGoogleDriveVideo = matched.first);
        } else {
          setState(() => _selectedGoogleDriveVideo = GoogleDriveVideo(
                id: driveId,
                title: 'Google Drive Video ($driveId)',
                ownerName: 'Google Drive Shared',
                category: 'Link Kustom',
              ));
        }
      }
    } else if (dmId != null) {
      if (_mediaType != 'dailymotion') {
        setState(() {
          _mediaType = 'dailymotion';
          _selectedYouTubeVideo = null;
          _selectedTwitchStream = null;
          _selectedVimeoVideo = null;
          _selectedGoogleDriveVideo = null;
          _selectedBstationVideo = null;
        });
      }
      if (_selectedDailymotionVideo == null ||
          _selectedDailymotionVideo!.id != dmId) {
        final allPresets = DailymotionService.allPresets;
        final matched = allPresets.where((v) => v.id == dmId);
        if (matched.isNotEmpty) {
          setState(() => _selectedDailymotionVideo = matched.first);
        } else {
          _urlDebounceTimer = Timer(const Duration(milliseconds: 400), () {
            DailymotionService.fetchVideoDetails(dmId).then((v) {
              if (mounted && v != null) {
                setState(() => _selectedDailymotionVideo = v);
              }
            });
          });
        }
      }
    } else if (bsId != null) {
      if (_mediaType != 'bstation') {
        setState(() {
          _mediaType = 'bstation';
          _selectedYouTubeVideo = null;
          _selectedTwitchStream = null;
          _selectedVimeoVideo = null;
          _selectedGoogleDriveVideo = null;
          _selectedDailymotionVideo = null;
        });
      }
      if (_selectedBstationVideo == null ||
          _selectedBstationVideo!.id != bsId) {
        final allPresets = BstationService.allPresets;
        final matched = allPresets.where((v) => v.id == bsId);
        if (matched.isNotEmpty) {
          setState(() => _selectedBstationVideo = matched.first);
        } else {
          _urlDebounceTimer = Timer(const Duration(milliseconds: 400), () {
            BstationService.fetchVideoDetails(bsId).then((v) {
              if (mounted && v != null) {
                setState(() => _selectedBstationVideo = v);
              }
            });
          });
        }
      }
    } else if ((text.endsWith('.mp4') ||
            text.endsWith('.m3u8') ||
            text.endsWith('.webm')) &&
        _mediaType != 'direct_url') {
      setState(() {
        _mediaType = 'direct_url';
        _selectedYouTubeVideo = null;
        _selectedTwitchStream = null;
        _selectedVimeoVideo = null;
        _selectedGoogleDriveVideo = null;
        _selectedDailymotionVideo = null;
        _selectedBstationVideo = null;
      });
    }
  }

  @override
  void dispose() {
    _urlDebounceTimer?.cancel();
    _mediaUrlController.removeListener(_onMediaUrlChanged);
    _titleController.dispose();
    _descController.dispose();
    _mediaUrlController.dispose();
    super.dispose();
  }

  void _applySelectedMedia(PlayableMediaItem item) {
    setState(() {
      _selectedYouTubeVideo = item is YouTubeVideo ? item : null;
      _selectedTwitchStream = item is TwitchStream ? item : null;
      _selectedVimeoVideo = item is VimeoVideo ? item : null;
      _selectedGoogleDriveVideo = item is GoogleDriveVideo ? item : null;
      _selectedDailymotionVideo = item is DailymotionVideo ? item : null;
      _selectedBstationVideo = item is BstationVideo ? item : null;
      _mediaType = item.mediaType;
      _mediaUrlController.text = item.url;
      _titleController.text = item.title;
    });
  }

  Future<void> _pickMedia<T extends PlayableMediaItem>(Widget screen) async {
    final result = await Navigator.of(context).push<T>(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (result != null && mounted) {
      _applySelectedMedia(result);
    }
  }

  Future<void> _pickAnotherYouTubeVideo() =>
      _pickMedia<YouTubeVideo>(const YouTubePickerScreen());

  Future<void> _pickAnotherTwitchStream() =>
      _pickMedia<TwitchStream>(const TwitchPickerScreen());

  Future<void> _pickAnotherVimeoVideo() =>
      _pickMedia<VimeoVideo>(const VimeoPickerScreen());

  Future<void> _pickAnotherGoogleDriveVideo() =>
      _pickMedia<GoogleDriveVideo>(const GoogleDrivePickerScreen());

  Future<void> _pickAnotherDailymotionVideo() =>
      _pickMedia<DailymotionVideo>(const DailymotionPickerScreen());

  Future<void> _pickAnotherBstationVideo() =>
      _pickMedia<BstationVideo>(const BstationPickerScreen());

  Future<void> _handleCreate() async {
    if (!_formKey.currentState!.validate()) return;

    final user = ref.read(authControllerProvider).asData?.value;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesi pengguna tidak ditemukan. Silakan atur nama terlebih dahulu.'),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    var mediaType = _mediaType;
    final mediaUrl = _mediaUrlController.text.trim();
    String? mediaThumbnail;

    if (_selectedYouTubeVideo != null) {
      mediaThumbnail = _selectedYouTubeVideo!.thumbnailUrl;
    } else if (_selectedTwitchStream != null) {
      mediaThumbnail = _selectedTwitchStream!.thumbnailUrl;
    } else if (_selectedVimeoVideo != null) {
      mediaThumbnail = _selectedVimeoVideo!.thumbnailUrl;
    } else if (_selectedGoogleDriveVideo != null) {
      mediaThumbnail = _selectedGoogleDriveVideo!.thumbnailUrl;
    } else if (_selectedDailymotionVideo != null) {
      mediaThumbnail = _selectedDailymotionVideo!.thumbnailUrl;
    } else if (_selectedBstationVideo != null) {
      mediaThumbnail = _selectedBstationVideo!.thumbnailUrl;
    }

    if (mediaUrl.isNotEmpty) {
      final detected = UnifiedPlayerController.detectMediaFromUrl(mediaUrl);
      if (detected != null) {
        mediaType = detected.mediaType;
        mediaThumbnail ??= detected.thumbnailUrl;
      }
    }
    mediaThumbnail ??= RoomModel.resolveThumbnail(url: mediaUrl, type: mediaType);

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
          initialThumbnailUrl: mediaThumbnail,
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

                        // Twitch options
                        if (_mediaType == 'twitch') ...[
                          // Selected Twitch Stream Preview Card
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFF9146FF).withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Stack(
                                    children: [
                                      Image.network(
                                        _selectedTwitchStream?.thumbnailUrl ??
                                            'https://static-cdn.jtvnw.net/previews-ttv/live_user_${_selectedTwitchStream?.id ?? "monstercat"}-640x360.jpg',
                                        width: 106,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(
                                          width: 106,
                                          height: 60,
                                          color: Colors.black26,
                                          child: const Icon(
                                            Icons.live_tv_rounded,
                                            color: Color(0xFF9146FF),
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
                                            color: const Color(0xFF9146FF),
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.circle,
                                                  size: 6, color: Colors.white),
                                              SizedBox(width: 2),
                                              Text(
                                                'Twitch',
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
                                      Positioned(
                                        bottom: 3,
                                        right: 3,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE91916),
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                          child: const Text(
                                            'LIVE',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedTwitchStream?.title ??
                                            'Twitch Live Stream',
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
                                              _selectedTwitchStream?.channelTitle ??
                                                  'Twitch Channel',
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
                                              color: Color(0xFF9146FF)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: _pickAnotherTwitchStream,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 9, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF9146FF).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF9146FF).withValues(alpha: 0.4)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.swap_horiz_rounded,
                                            size: 15,
                                            color: Color(0xFF9146FF)),
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
                          const Text(
                            'Link Channel / Video / Clip Twitch *',
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
                              hintText: 'https://twitch.tv/monstercat',
                              prefixIcon: Icon(
                                Icons.videogame_asset_rounded,
                                color: Color(0xFF9146FF),
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'URL Twitch tidak boleh kosong';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: ApiConstants.presetMedia
                                .where((m) => m['type'] == 'twitch')
                                .map((media) {
                              return ActionChip(
                                avatar: const Icon(
                                  Icons.videogame_asset_rounded,
                                  size: 14,
                                  color: Color(0xFF9146FF),
                                ),
                                label: Text(
                                  media['title']!,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor: AppColors.surfaceElevated,
                                side: const BorderSide(color: AppColors.border),
                                onPressed: () {
                                  setState(() {
                                    _mediaUrlController.text = media['url']!;
                                    final twitchPresets = TwitchService.categoryPresets['Populer & Live'] ?? [];
                                    final matched = twitchPresets.where((s) => s.url == media['url'] || s.id == media['title']?.toLowerCase());
                                    if (matched.isNotEmpty) {
                                      _selectedTwitchStream = matched.first;
                                    } else {
                                      final channel = UnifiedPlayerController.extractTwitchMedia(media['url']!)?.id;
                                      if (channel != null) {
                                        _selectedTwitchStream = TwitchStream.fromId(
                                          id: channel,
                                          title: media['title'] ?? channel,
                                          channelTitle: channel,
                                        );
                                      }
                                    }
                                    if (_titleController.text.isEmpty ||
                                        _titleController.text == 'Nonton Bareng' ||
                                        _titleController.text == 'Nonton Twitch') {
                                      _titleController.text = 'Nonton ${media['title']}';
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Vimeo options
                        if (_mediaType == 'vimeo') ...[
                          // Selected Vimeo Video Preview Card
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFF1AB7EA).withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Stack(
                                    children: [
                                      Image.network(
                                        _selectedVimeoVideo?.thumbnailUrl ??
                                            'https://vumbnail.com/${UnifiedPlayerController.extractVimeoVideoId(_mediaUrlController.text) ?? "76979871"}.jpg',
                                        width: 106,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(
                                          width: 106,
                                          height: 60,
                                          color: Colors.black26,
                                          child: const Icon(
                                            Icons.video_collection_rounded,
                                            color: Color(0xFF1AB7EA),
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
                                            color: const Color(0xFF1AB7EA),
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                          child: const Text(
                                            'Vimeo',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_selectedVimeoVideo != null &&
                                          _selectedVimeoVideo!.duration.isNotEmpty)
                                        Positioned(
                                          bottom: 3,
                                          right: 3,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(alpha: 0.8),
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                            child: Text(
                                              _selectedVimeoVideo!.duration,
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
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedVimeoVideo?.title ??
                                            'Vimeo Video',
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
                                              _selectedVimeoVideo?.channelTitle ??
                                                  'Vimeo Creator',
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
                                              color: Color(0xFF1AB7EA)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: _pickAnotherVimeoVideo,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 9, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1AB7EA).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF1AB7EA).withValues(alpha: 0.4)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.swap_horiz_rounded,
                                            size: 15,
                                            color: Color(0xFF1AB7EA)),
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
                          const Text(
                            'Link Video Vimeo *',
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
                              hintText: 'https://vimeo.com/76979871',
                              prefixIcon: Icon(
                                Icons.ondemand_video_rounded,
                                color: Color(0xFF1AB7EA),
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'URL Vimeo tidak boleh kosong';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: ApiConstants.presetMedia
                                .where((m) => m['type'] == 'vimeo')
                                .map((media) {
                              return ActionChip(
                                avatar: const Icon(
                                  Icons.ondemand_video_rounded,
                                  size: 14,
                                  color: Color(0xFF1AB7EA),
                                ),
                                label: Text(
                                  media['title']!,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor: AppColors.surfaceElevated,
                                side: const BorderSide(color: AppColors.border),
                                onPressed: () {
                                  setState(() {
                                    _mediaUrlController.text = media['url']!;
                                    final vimeoPresets = VimeoService.categoryPresets['Staff Picks'] ?? [];
                                    final matched = vimeoPresets.where((v) => v.url == media['url'] || v.title == media['title']);
                                    if (matched.isNotEmpty) {
                                      _selectedVimeoVideo = matched.first;
                                    } else {
                                      final id = UnifiedPlayerController.extractVimeoVideoId(media['url']!);
                                      if (id != null) {
                                        _selectedVimeoVideo = VimeoVideo(
                                          id: id,
                                          title: media['title'] ?? 'Vimeo Video ($id)',
                                          channelTitle: 'Vimeo Creator',
                                          thumbnailUrl: 'https://vumbnail.com/$id.jpg',
                                          duration: 'HD',
                                        );
                                      }
                                    }
                                    if (_titleController.text.isEmpty ||
                                        _titleController.text == 'Nonton Bareng' ||
                                        _titleController.text == 'Nonton Vimeo') {
                                      _titleController.text = 'Nonton ${media['title']}';
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Google Drive options (if Google Drive)
                        if (_mediaType == 'google_drive') ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFF0F9D58).withValues(alpha: 0.6),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Stack(
                                    children: [
                                      Image.network(
                                        _selectedGoogleDriveVideo?.driveThumbnailUrl ??
                                            'https://drive.google.com/thumbnail?id=${GoogleDriveService.extractFileId(_mediaUrlController.text) ?? "1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8"}&sz=w640',
                                        width: 106,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(
                                          width: 106,
                                          height: 60,
                                          color: const Color(0xFF132B1C),
                                          child: const Icon(
                                            Icons.cloud_circle_rounded,
                                            color: Color(0xFF0F9D58),
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
                                            color: const Color(0xFF0F9D58),
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                          child: const Text(
                                            'Drive',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_selectedGoogleDriveVideo != null &&
                                          _selectedGoogleDriveVideo!.duration.isNotEmpty)
                                        Positioned(
                                          bottom: 3,
                                          right: 3,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(alpha: 0.8),
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                            child: Text(
                                              _selectedGoogleDriveVideo!.duration,
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
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedGoogleDriveVideo?.title ??
                                            'Google Drive Video',
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
                                              _selectedGoogleDriveVideo?.ownerName ??
                                                  'Google Drive Shared',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.verified_rounded,
                                              size: 11,
                                              color: Color(0xFF4285F4)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: _pickAnotherGoogleDriveVideo,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 9, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F9D58).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF0F9D58).withValues(alpha: 0.4)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.swap_horiz_rounded,
                                            size: 15,
                                            color: Color(0xFF0F9D58)),
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
                          const Text(
                            'Link Video Google Drive *',
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
                              hintText: 'https://drive.google.com/file/d/...',
                              prefixIcon: Icon(
                                Icons.cloud_queue_rounded,
                                color: Color(0xFF0F9D58),
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'URL Google Drive tidak boleh kosong';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: ApiConstants.presetMedia
                                .where((m) => m['type'] == 'google_drive')
                                .map((media) {
                              return ActionChip(
                                avatar: const Icon(
                                  Icons.cloud_queue_rounded,
                                  size: 14,
                                  color: Color(0xFF0F9D58),
                                ),
                                label: Text(
                                  media['title']!,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor: AppColors.surfaceElevated,
                                side: const BorderSide(color: AppColors.border),
                                onPressed: () {
                                  setState(() {
                                    _mediaUrlController.text = media['url']!;
                                    final allPresets = GoogleDriveService.categoryPresets.values.expand((v) => v);
                                    final matched = allPresets.where((v) => v.url == media['url'] || v.title == media['title']);
                                    if (matched.isNotEmpty) {
                                      _selectedGoogleDriveVideo = matched.first;
                                    } else {
                                      final id = GoogleDriveService.extractFileId(media['url']!);
                                      if (id != null) {
                                        _selectedGoogleDriveVideo = GoogleDriveVideo(
                                          id: id,
                                          title: media['title'] ?? 'Google Drive Video ($id)',
                                          ownerName: 'Google Drive Shared',
                                          category: 'Koleksi Drive',
                                        );
                                      }
                                    }
                                    if (_titleController.text.isEmpty ||
                                        _titleController.text == 'Nonton Bareng' ||
                                        _titleController.text == 'Nonton Google Drive') {
                                      _titleController.text = 'Nonton ${media['title']}';
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Dailymotion options (if Dailymotion)
                        if (_mediaType == 'dailymotion') ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFF0066DC).withValues(alpha: 0.6),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Stack(
                                    children: [
                                      Image.network(
                                        _selectedDailymotionVideo?.effectiveThumbnailUrl ??
                                            'https://www.dailymotion.com/thumbnail/video/${UnifiedPlayerController.extractDailymotionVideoId(_mediaUrlController.text) ?? "x7tgad0"}',
                                        width: 106,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(
                                          width: 106,
                                          height: 60,
                                          color: const Color(0xFF001F4D),
                                          child: const Icon(
                                            Icons.play_circle_filled_rounded,
                                            color: Color(0xFF0066DC),
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
                                            color: const Color(0xFF0066DC),
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                          child: const Text(
                                            'Daily',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_selectedDailymotionVideo != null &&
                                          _selectedDailymotionVideo!.durationFormatted.isNotEmpty)
                                        Positioned(
                                          bottom: 3,
                                          right: 3,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(alpha: 0.8),
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                            child: Text(
                                              _selectedDailymotionVideo!.durationFormatted,
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
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedDailymotionVideo?.title ??
                                            'Dailymotion Video',
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
                                              _selectedDailymotionVideo?.uploaderName ??
                                                  'Dailymotion',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.verified_rounded,
                                              size: 11,
                                              color: Color(0xFF0066DC)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: _pickAnotherDailymotionVideo,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 9, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0066DC).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF0066DC).withValues(alpha: 0.4)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.swap_horiz_rounded,
                                            size: 15,
                                            color: Color(0xFF0066DC)),
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
                          const Text(
                            'Link Video Dailymotion *',
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
                              hintText: 'https://www.dailymotion.com/video/...',
                              prefixIcon: Icon(
                                Icons.play_circle_filled_rounded,
                                color: Color(0xFF0066DC),
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'URL Dailymotion tidak boleh kosong';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: ApiConstants.presetMedia
                                .where((m) => m['type'] == 'dailymotion')
                                .map((media) {
                              return ActionChip(
                                avatar: const Icon(
                                  Icons.play_circle_filled_rounded,
                                  size: 14,
                                  color: Color(0xFF0066DC),
                                ),
                                label: Text(
                                  media['title']!,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor: AppColors.surfaceElevated,
                                side: const BorderSide(color: AppColors.border),
                                onPressed: () {
                                  setState(() {
                                    _mediaUrlController.text = media['url']!;
                                    final allPresets = DailymotionService.allPresets;
                                    final matched = allPresets.where((v) => v.url == media['url'] || v.title == media['title']);
                                    if (matched.isNotEmpty) {
                                      _selectedDailymotionVideo = matched.first;
                                    } else {
                                      final id = UnifiedPlayerController.extractDailymotionVideoId(media['url']!);
                                      if (id != null) {
                                        _selectedDailymotionVideo = DailymotionVideo.fromId(
                                          id,
                                          title: media['title'],
                                        );
                                      }
                                    }
                                    if (_titleController.text.isEmpty ||
                                        _titleController.text == 'Nonton Bareng' ||
                                        _titleController.text == 'Nonton Dailymotion') {
                                      _titleController.text = 'Nonton ${media['title']}';
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Bstation options (if Bstation)
                        if (_mediaType == 'bstation') ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFF00A1D6).withValues(alpha: 0.6),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Stack(
                                    children: [
                                      Image.network(
                                        _selectedBstationVideo?.effectiveThumbnailUrl ??
                                            'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=800&auto=format&fit=crop&q=80',
                                        width: 106,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(
                                          width: 106,
                                          height: 60,
                                          color: const Color(0xFF002F44),
                                          child: const Icon(
                                            Icons.smart_display_rounded,
                                            color: Color(0xFF00A1D6),
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
                                            color: _selectedBstationVideo?.episodeNumber != null
                                                ? const Color(0xFFFB7299)
                                                : const Color(0xFF00A1D6),
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                          child: Text(
                                            _selectedBstationVideo?.episodeNumber ?? 'Bstation',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_selectedBstationVideo != null &&
                                          _selectedBstationVideo!.durationFormatted.isNotEmpty)
                                        Positioned(
                                          bottom: 3,
                                          right: 3,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(alpha: 0.8),
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                            child: Text(
                                              _selectedBstationVideo!.durationFormatted,
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
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedBstationVideo?.title ??
                                            'Bstation Video',
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
                                              _selectedBstationVideo?.uploaderName ??
                                                  'Bstation Creator',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.verified_rounded,
                                              size: 11,
                                              color: Color(0xFF00A1D6)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: _pickAnotherBstationVideo,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 9, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00A1D6).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF00A1D6).withValues(alpha: 0.4)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.swap_horiz_rounded,
                                            size: 15,
                                            color: Color(0xFF00A1D6)),
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
                          const Text(
                            'Link Video / Anime Bstation *',
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
                              hintText: 'https://www.bilibili.tv/id/video/...',
                              prefixIcon: Icon(
                                Icons.smart_display_rounded,
                                color: Color(0xFF00A1D6),
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'URL Bstation tidak boleh kosong';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: ApiConstants.presetMedia
                                .where((m) => m['type'] == 'bstation')
                                .map((media) {
                              return ActionChip(
                                avatar: const Icon(
                                  Icons.smart_display_rounded,
                                  size: 14,
                                  color: Color(0xFF00A1D6),
                                ),
                                label: Text(
                                  media['title']!,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor: AppColors.surfaceElevated,
                                side: const BorderSide(color: AppColors.border),
                                onPressed: () {
                                  setState(() {
                                    _mediaUrlController.text = media['url']!;
                                    final allPresets = BstationService.allPresets;
                                    final matched = allPresets.where((v) => v.url == media['url'] || v.title == media['title']);
                                    if (matched.isNotEmpty) {
                                      _selectedBstationVideo = matched.first;
                                    } else {
                                      final id = UnifiedPlayerController.extractBstationVideoId(media['url']!);
                                      if (id != null) {
                                        _selectedBstationVideo = BstationVideo.fromId(
                                          id,
                                          title: media['title'],
                                        );
                                      }
                                    }
                                    if (_titleController.text.isEmpty ||
                                        _titleController.text == 'Nonton Bareng' ||
                                        _titleController.text == 'Nonton Bstation') {
                                      _titleController.text = 'Nonton ${media['title']}';
                                    }
                                  });
                                },
                              );
                            }).toList(),
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
