import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../auth/presentation/auth_controller.dart';
import 'lobby_controller.dart';
import 'widgets/create_room_dialog.dart';
import 'widgets/join_code_dialog.dart';
import 'widgets/media_source_dialog.dart';
import 'widgets/room_card.dart';
import 'screens/bstation_picker_screen.dart';
import 'screens/dailymotion_picker_screen.dart';
import 'screens/google_drive_picker_screen.dart';
import 'screens/twitch_picker_screen.dart';
import 'screens/vimeo_picker_screen.dart';
import 'screens/youtube_picker_screen.dart';
import '../data/models/bstation_video_model.dart';
import '../data/models/dailymotion_video_model.dart';
import '../data/models/google_drive_video_model.dart';
import '../data/models/twitch_stream_model.dart';
import '../data/models/vimeo_video_model.dart';
import '../data/models/youtube_video_model.dart';
import '../../p2p_streaming/presentation/local_video_picker_sheet.dart';
import '../../room/models/room_model.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openCreateRoomDialog() async {
    final sourceType = await MediaSourceDialog.show(context);
    if (sourceType == null || !mounted) return;

    RoomModel? room;

    if (sourceType == MediaSourceType.youtube) {
      final video = await Navigator.of(context).push<YouTubeVideo>(
        MaterialPageRoute(builder: (_) => const YouTubePickerScreen()),
      );
      if (video == null || !mounted) return;

      room = await CreateRoomDialog.show(
        context,
        initialYouTubeVideo: video,
      );
    } else if (sourceType == MediaSourceType.twitch) {
      final stream = await Navigator.of(context).push<TwitchStream>(
        MaterialPageRoute(builder: (_) => const TwitchPickerScreen()),
      );
      if (stream == null || !mounted) return;

      room = await CreateRoomDialog.show(
        context,
        initialTwitchStream: stream,
      );
    } else if (sourceType == MediaSourceType.vimeo) {
      final video = await Navigator.of(context).push<VimeoVideo>(
        MaterialPageRoute(builder: (_) => const VimeoPickerScreen()),
      );
      if (video == null || !mounted) return;

      room = await CreateRoomDialog.show(
        context,
        initialVimeoVideo: video,
      );
    } else if (sourceType == MediaSourceType.googleDrive) {
      final video = await Navigator.of(context).push<GoogleDriveVideo>(
        MaterialPageRoute(builder: (_) => const GoogleDrivePickerScreen()),
      );
      if (video == null || !mounted) return;

      room = await CreateRoomDialog.show(
        context,
        initialGoogleDriveVideo: video,
      );
    } else if (sourceType == MediaSourceType.dailymotion) {
      final video = await Navigator.of(context).push<DailymotionVideo>(
        MaterialPageRoute(builder: (_) => const DailymotionPickerScreen()),
      );
      if (video == null || !mounted) return;

      room = await CreateRoomDialog.show(
        context,
        initialDailymotionVideo: video,
      );
    } else if (sourceType == MediaSourceType.bstation) {
      final video = await Navigator.of(context).push<BstationVideo>(
        MaterialPageRoute(builder: (_) => const BstationPickerScreen()),
      );
      if (video == null || !mounted) return;

      room = await CreateRoomDialog.show(
        context,
        initialBstationVideo: video,
      );
    } else if (sourceType == MediaSourceType.localVideo) {
      final file = await LocalVideoPickerSheet.show(context);
      if (file == null || !mounted) return;

      room = await CreateRoomDialog.show(
        context,
        initialLocalVideoFile: file,
      );
      if (room != null && mounted) {
        await context.push(
          '/room/${room.code}',
          extra: {'room': room, 'localFile': file},
        );
        if (mounted) {
          ref.read(lobbyControllerProvider.notifier).refreshRooms();
        }
        return;
      }
    } else if (sourceType == MediaSourceType.directUrl) {
      room = await CreateRoomDialog.show(
        context,
        initialMediaType: 'direct_url',
      );
    }

    if (room != null && mounted) {
      await context.push('/room/${room.code}', extra: room);
      if (mounted) {
        ref.read(lobbyControllerProvider.notifier).refreshRooms();
      }
    }
  }

  Future<void> _openJoinCodeDialog() async {
    final room = await showDialog<RoomModel>(
      context: context,
      builder: (_) => const JoinCodeDialog(),
    );
    if (room != null && mounted) {
      await context.push('/room/${room.code}', extra: room);
      if (mounted) {
        ref.read(lobbyControllerProvider.notifier).refreshRooms();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final roomsAsync = ref.watch(lobbyControllerProvider);
    final filteredRooms = ref.watch(filteredRoomsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Nobarin',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          // User profile pill
          if (user != null) ...[
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Material(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppColors.surfaceElevated,
                        title: const Text('Keluar Akun?'),
                        content: Text(
                          'Yakin ingin keluar dari akun ${user.username}?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Batal'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accentRed,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Keluar'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      ref.read(authControllerProvider.notifier).logout();
                      context.go('/');
                    }
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(user.avatarUrl,
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Text(
                          user.username,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.logout_rounded,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(lobbyControllerProvider.notifier).refreshRooms(),
        color: AppColors.primaryNeon,
        backgroundColor: AppColors.surfaceElevated,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Hero / Quick Action Cards Section
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dual Action Cards Row
                    Row(
                      children: [
                        // Card 1: Buat Room Baru
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                AppHaptics.light();
                                _openCreateRoomDialog();
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Ink(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 16),
                                decoration: BoxDecoration(
                                  gradient: AppColors.primaryGradient,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primaryNeon
                                          .withValues(alpha: 0.35),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.add_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Buat Room',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Mulai pesta nonton',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white.withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Card 2: Gabung Kode PIN
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                AppHaptics.light();
                                _openJoinCodeDialog();
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Ink(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 16),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceElevated,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppColors.secondaryNeon.withValues(alpha: 0.6),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.secondaryNeon
                                          .withValues(alpha: 0.12),
                                      blurRadius: 12,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.secondaryNeon
                                            .withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.pin_rounded,
                                        color: AppColors.secondaryNeon,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Gabung Kode',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Masukkan Kode 6 Digit',
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
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Search Bar
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Cari judul room, host, atau kode...',
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppColors.textSecondary,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  ref
                                      .read(lobbySearchQueryProvider.notifier)
                                      .state = '';
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (val) {
                        ref.read(lobbySearchQueryProvider.notifier).state = val;
                        setState(() {});
                      },
                    ),

                    const SizedBox(height: 18),

                    // Horizontal Platform Filter Chips
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _buildFilterChip('all', 'Semua', Icons.grid_view_rounded),
                          const SizedBox(width: 8),
                          _buildFilterChip('youtube', 'YouTube', Icons.play_circle_filled_rounded),
                          const SizedBox(width: 8),
                          _buildFilterChip('twitch', 'Twitch', Icons.live_tv_rounded),
                          const SizedBox(width: 8),
                          _buildFilterChip('vimeo', 'Vimeo', Icons.video_collection_rounded),
                          const SizedBox(width: 8),
                          _buildFilterChip('bstation', 'Bstation', Icons.smart_display_rounded),
                          const SizedBox(width: 8),
                          _buildFilterChip('google_drive', 'Drive', Icons.cloud_queue_rounded),
                          const SizedBox(width: 8),
                          _buildFilterChip('dailymotion', 'Dailymotion', Icons.play_circle_filled_rounded),
                          const SizedBox(width: 8),
                          _buildFilterChip('direct_url', 'Direct URL', Icons.link_rounded),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Section Title with room count
                    Builder(
                      builder: (_) {
                        final displayed = _filterByCategory(filteredRooms);
                        return Row(
                          children: [
                            const Text(
                              'Room Publik',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primaryNeon.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppColors.primaryNeon.withValues(alpha: 0.3),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                '${displayed.length}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryNeon,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Room List / Grid
            roomsAsync.when(
              loading: () => SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: RoomCardSkeleton(),
                    ),
                    childCount: 4,
                  ),
                ),
              ),
              error: (err, _) => SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off_rounded,
                          size: 48, color: AppColors.accentRed),
                      const SizedBox(height: 12),
                      const Text(
                        'Gagal memuat daftar room',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => ref
                            .read(lobbyControllerProvider.notifier)
                            .refreshRooms(),
                        child: const Text('Coba Lagi'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (_) {
                final displayedRooms = _filterByCategory(filteredRooms);

                if (displayedRooms.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.borderLight),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.primaryNeon.withValues(alpha: 0.1),
                                  border: Border.all(
                                    color: AppColors.primaryNeon.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.tv_off_rounded,
                                  size: 42,
                                  color: AppColors.primaryNeon,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _selectedCategory == 'all'
                                    ? 'Belum Ada Room Publik'
                                    : 'Tidak Ada Room ${_getCategoryLabel(_selectedCategory)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Buat room pertama dan tonton bersama temanmu sekarang!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 20),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: AppColors.primaryGradient,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                  ),
                                  onPressed: () {
                                    AppHaptics.light();
                                    _openCreateRoomDialog();
                                  },
                                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                                  label: const Text(
                                    'Buat Room Sekarang',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 8),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final double width = constraints.crossAxisExtent;
                      final int crossAxisCount = width > 900
                          ? 3
                          : width > 600
                              ? 2
                              : 1;

                      if (crossAxisCount == 1) {
                        return SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final room = displayedRooms[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: RoomCard(
                                  room: room,
                                  onTap: () async {
                                    await context.push('/room/${room.code}', extra: room);
                                    if (context.mounted) {
                                      ref.read(lobbyControllerProvider.notifier).refreshRooms();
                                    }
                                  },
                                ),
                              );
                            },
                            childCount: displayedRooms.length,
                          ),
                        );
                      }

                      return SliverGrid(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 1.10,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final room = displayedRooms[index];
                            return RoomCard(
                              room: room,
                              onTap: () async {
                                await context.push('/room/${room.code}', extra: room);
                                if (context.mounted) {
                                  ref.read(lobbyControllerProvider.notifier).refreshRooms();
                                }
                              },
                            );
                          },
                          childCount: displayedRooms.length,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<RoomModel> _filterByCategory(List<RoomModel> rooms) {
    if (_selectedCategory == 'all') return rooms;
    return rooms.where((r) {
      if (_selectedCategory == 'youtube') return r.currentMediaType == 'youtube';
      if (_selectedCategory == 'twitch') return r.currentMediaType == 'twitch';
      if (_selectedCategory == 'vimeo') return r.currentMediaType == 'vimeo';
      if (_selectedCategory == 'bstation') {
        return r.currentMediaType == 'bstation' || r.currentMediaType == 'bilibili';
      }
      if (_selectedCategory == 'google_drive') return r.currentMediaType == 'google_drive';
      if (_selectedCategory == 'dailymotion') return r.currentMediaType == 'dailymotion';
      if (_selectedCategory == 'direct_url') return r.currentMediaType == 'direct_url';
      return true;
    }).toList();
  }

  String _getCategoryLabel(String cat) {
    switch (cat) {
      case 'youtube':
        return 'YouTube';
      case 'twitch':
        return 'Twitch';
      case 'vimeo':
        return 'Vimeo';
      case 'bstation':
        return 'Bstation';
      case 'google_drive':
        return 'Google Drive';
      case 'dailymotion':
        return 'Dailymotion';
      case 'direct_url':
        return 'Direct URL';
      default:
        return 'Publik';
    }
  }

  Widget _buildFilterChip(String id, String label, IconData icon) {
    final isSelected = _selectedCategory == id;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AppHaptics.selection();
          setState(() {
            _selectedCategory = id;
          });
        },
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primaryNeon.withValues(alpha: 0.2)
                : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryNeon
                  : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? AppColors.primaryNeon : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
