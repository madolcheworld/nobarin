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
import 'widgets/room_card.dart';
import 'widgets/user_profile_sheet.dart';
import '../../room/models/room_model.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _showFab = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final shouldShow =
        _scrollController.hasClients && _scrollController.offset > 120;
    if (shouldShow != _showFab) {
      setState(() {
        _showFab = shouldShow;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _openCreateRoomDialog() async {
    final room = await CreateRoomDialog.show(context);
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

  Widget _buildFilterChip({
    required String label,
    IconData? icon,
    Color? iconColor,
    int? count,
    required LobbyFilterCategory category,
    required LobbyFilterCategory selectedCategory,
  }) {
    final isSelected = selectedCategory == category;

    return InkWell(
      onTap: () {
        AppHaptics.selection();
        ref.read(lobbyFilterCategoryProvider.notifier).state = category;
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryNeon.withValues(alpha: 0.22)
              : AppColors.glassFillLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryNeon
                : AppColors.glassBorder,
            width: isSelected ? 1.4 : 1.0,
          ),
          boxShadow: isSelected ? AppColors.neonVioletGlow : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: iconColor ?? AppColors.textPrimary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primaryNeon
                      : AppColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? Colors.white
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final roomsAsync = ref.watch(lobbyControllerProvider);
    final filteredRooms = ref.watch(filteredRoomsProvider);
    final selectedCategory = ref.watch(lobbyFilterCategoryProvider);
    final rawQuery = ref.watch(lobbySearchQueryProvider).trim();

    final allRooms = roomsAsync.asData?.value ?? [];
    final allRoomsCount = allRooms.length;
    final liveRoomsCount = allRooms.where((r) => r.isPlaying).length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(10),
                boxShadow: AppColors.neonVioletGlow,
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
          // Realtime Status Indicator
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.accentGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.accentGreen.withValues(alpha: 0.3),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentGreen,
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  'Online',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accentGreen,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // User profile trigger button
          InkWell(
            onTap: () {
              AppHaptics.light();
              UserProfileSheet.show(context);
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user?.avatarUrl ?? '🦊',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 80),
                    child: Text(
                      user?.username ?? 'Tamu',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.tune_rounded,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
      floatingActionButton: AnimatedSlide(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        offset: _showFab ? Offset.zero : const Offset(0, 2),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _showFab ? 1.0 : 0.0,
          child: _showFab
              ? FloatingActionButton.extended(
                  onPressed: () {
                    AppHaptics.light();
                    _openCreateRoomDialog();
                  },
                  backgroundColor: AppColors.primaryNeonDark,
                  foregroundColor: Colors.white,
                  elevation: 6,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'Buat Room',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(lobbyControllerProvider.notifier).refreshRooms(),
        color: AppColors.primaryNeon,
        backgroundColor: AppColors.surfaceElevated,
        child: CustomScrollView(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Top Section: Sapaan, Dual Hero Cards, Pencarian, & Filter Chips
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Sapaan Ramah Sederhana
                    Text(
                      'Halo, ${user?.username ?? 'Teman'}! 👋',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Mau nonton apa hari ini?',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),

                    const SizedBox(height: 18),

                    // 2. Dual Action Cards Row (Buat Room & Gabung Kode)
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
                                      blurRadius: 14,
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
                                        color: Colors.white
                                            .withValues(alpha: 0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.video_call_rounded,
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
                                      'Mulai nobar & ajak teman',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white
                                            .withValues(alpha: 0.85),
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
                                  color: AppColors.glassFill,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppColors.secondaryNeon
                                        .withValues(alpha: 0.45),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.secondaryNeon
                                          .withValues(alpha: 0.15),
                                      blurRadius: 14,
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
                                      'Masukkan 6 digit PIN',
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

                    // 3. Search Bar
                    TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      decoration: InputDecoration(
                        hintText: 'Cari judul room atau nama host...',
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppColors.textSecondary,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  _searchFocusNode.unfocus();
                                  ref
                                      .read(lobbySearchQueryProvider.notifier)
                                      .state = '';
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      onSubmitted: (_) {
                        _searchFocusNode.unfocus();
                      },
                      onChanged: (val) {
                        ref.read(lobbySearchQueryProvider.notifier).state = val;
                        setState(() {});
                      },
                    ),

                    const SizedBox(height: 16),

                    // 4. Category Filter Chips Row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(
                            label: 'Semua',
                            count: allRoomsCount,
                            category: LobbyFilterCategory.all,
                            selectedCategory: selectedCategory,
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            label: '🔴 Sedang Live',
                            count: liveRoomsCount,
                            category: LobbyFilterCategory.liveOnly,
                            selectedCategory: selectedCategory,
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            label: 'YouTube',
                            icon: Icons.smart_display_rounded,
                            iconColor: AppColors.youtubeRed,
                            category: LobbyFilterCategory.youtube,
                            selectedCategory: selectedCategory,
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            label: 'Bstation',
                            icon: Icons.tv_rounded,
                            iconColor: AppColors.bstationBlue,
                            category: LobbyFilterCategory.bstation,
                            selectedCategory: selectedCategory,
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            label: 'Dailymotion',
                            icon: Icons.play_circle_filled_rounded,
                            iconColor: AppColors.dailymotionBlue,
                            category: LobbyFilterCategory.dailymotion,
                            selectedCategory: selectedCategory,
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            label: 'File P2P',
                            icon: Icons.folder_special_rounded,
                            iconColor: Colors.purpleAccent,
                            category: LobbyFilterCategory.p2pFile,
                            selectedCategory: selectedCategory,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 5. Section Header with Room Count
                    Row(
                      children: [
                        const Text(
                          'Room Publik',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                AppColors.primaryNeon.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.primaryNeon
                                  .withValues(alpha: 0.3),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            '${filteredRooms.length}',
                            style: const TextStyle(
                              fontSize: 11.5,
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

            // Room List / Shimmer / Empty State
            roomsAsync.when(
              loading: () => SliverPadding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
                final displayedRooms = filteredRooms;

                // Empty State Handling
                if (displayedRooms.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated
                                .withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.borderLight),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Distinct Icons & Labels
                              if (rawQuery.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.primaryNeon
                                        .withValues(alpha: 0.1),
                                  ),
                                  child: const Icon(
                                    Icons.search_off_rounded,
                                    size: 38,
                                    color: AppColors.primaryNeon,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'Room Tidak Ditemukan',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Tidak ada room yang cocok dengan "$rawQuery"',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                OutlinedButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    ref
                                        .read(lobbySearchQueryProvider.notifier)
                                        .state = '';
                                    setState(() {});
                                  },
                                  child: const Text('Hapus Pencarian'),
                                ),
                              ] else if (selectedCategory !=
                                  LobbyFilterCategory.all) ...[
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.secondaryNeon
                                        .withValues(alpha: 0.1),
                                  ),
                                  child: const Icon(
                                    Icons.filter_alt_off_rounded,
                                    size: 38,
                                    color: AppColors.secondaryNeon,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'Tidak Ada Room di Kategori Ini',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Belum ada room publik untuk filter yang dipilih.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                OutlinedButton(
                                  onPressed: () {
                                    ref
                                        .read(lobbyFilterCategoryProvider
                                            .notifier)
                                        .state = LobbyFilterCategory.all;
                                  },
                                  child: const Text('Tampilkan Semua Room'),
                                ),
                              ] else ...[
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.primaryNeon
                                        .withValues(alpha: 0.1),
                                    border: Border.all(
                                      color: AppColors.primaryNeon
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.tv_off_rounded,
                                    size: 38,
                                    color: AppColors.primaryNeon,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'Belum Ada Room Publik',
                                  style: TextStyle(
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
                                const SizedBox(height: 18),
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
                                    icon: const Icon(Icons.add_rounded,
                                        color: Colors.white),
                                    label: const Text(
                                      'Buat Room Sekarang',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }

                // Room List layout (1 column on mobile, 2 columns on wide screens)
                return SliverPadding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final double width = constraints.crossAxisExtent;
                      final bool isWide = width > 760;

                      if (!isWide) {
                        return SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final room = displayedRooms[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: RoomCard(
                                  room: room,
                                  onTap: () async {
                                    await context.push('/room/${room.code}',
                                        extra: room);
                                    if (context.mounted) {
                                      ref
                                          .read(
                                              lobbyControllerProvider.notifier)
                                          .refreshRooms();
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
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 600,
                          mainAxisExtent: 110,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 14,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final room = displayedRooms[index];
                            return RoomCard(
                              room: room,
                              onTap: () async {
                                await context.push('/room/${room.code}',
                                    extra: room);
                                if (context.mounted) {
                                  ref
                                      .read(lobbyControllerProvider.notifier)
                                      .refreshRooms();
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

            // Bottom space
            const SliverToBoxAdapter(
              child: SizedBox(height: 32),
            ),
          ],
        ),
      ),
    );
  }
}
