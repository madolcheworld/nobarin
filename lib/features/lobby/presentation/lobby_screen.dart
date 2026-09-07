import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/presentation/auth_controller.dart';
import 'lobby_controller.dart';
import 'widgets/create_room_dialog.dart';
import 'widgets/join_code_dialog.dart';
import 'widgets/media_source_dialog.dart';
import 'widgets/room_card.dart';
import 'screens/youtube_picker_screen.dart';
import '../data/models/youtube_video_model.dart';
import '../../room/models/room_model.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  final TextEditingController _searchController = TextEditingController();

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
              'WatchParty',
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
            // Hero / Action Section
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Action Buttons Row
                    Row(
                      children: [
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppColors.primaryNeon.withValues(alpha: 0.35),
                                  blurRadius: 14,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: _openCreateRoomDialog,
                              icon: const Icon(Icons.add_rounded,
                                  color: Colors.white),
                              label: const Text(
                                'Buat Room',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(
                                color: AppColors.secondaryNeon,
                                width: 1.5,
                              ),
                              foregroundColor: AppColors.secondaryNeon,
                            ),
                            onPressed: _openJoinCodeDialog,
                            icon: const Icon(Icons.pin_rounded,
                                color: AppColors.secondaryNeon),
                            label: const Text(
                              'Gabung Kode',
                              style: TextStyle(fontWeight: FontWeight.bold),
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
                        hintText: 'Cari room atau kode...',
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

                    const SizedBox(height: 24),

                    // Section Title
                    Row(
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
                          ),
                          child: Text(
                            '${filteredRooms.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryNeon,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Room List / Grid
            roomsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryNeon,
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
                if (filteredRooms.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.surfaceElevated,
                              ),
                              child: const Icon(
                                Icons.tv_off_rounded,
                                size: 48,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Belum ada room publik',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Buat room pertama dan tonton bersama teman!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _openCreateRoomDialog,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Buat Room'),
                            ),
                          ],
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
                              final room = filteredRooms[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
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
                            childCount: filteredRooms.length,
                          ),
                        );
                      }

                      return SliverGrid(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 1.8,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final room = filteredRooms[index];
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
                          childCount: filteredRooms.length,
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
}
