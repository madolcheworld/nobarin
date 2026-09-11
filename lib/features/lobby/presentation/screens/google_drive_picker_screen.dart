import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../data/google_drive_auth_service.dart';
import '../../data/google_drive_service.dart';
import '../../data/models/google_drive_account.dart';
import '../../data/models/google_drive_video_model.dart';
import 'generic_media_picker_screen.dart';

/// Screen for picking Google Drive videos, supporting:
/// 1. Personal Google Drive (with Google Sign-In, file list, and room access sharing)
/// 2. Public / Curated collection presets & manual link input
class GoogleDrivePickerScreen extends StatefulWidget {
  const GoogleDrivePickerScreen({super.key});

  @override
  State<GoogleDrivePickerScreen> createState() => _GoogleDrivePickerScreenState();
}

class _GoogleDrivePickerScreenState extends State<GoogleDrivePickerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  List<GoogleDriveVideo> _userVideos = [];
  bool _isLoadingUserVideos = false;
  String? _userVideosError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initAuthAndLoadVideos();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initAuthAndLoadVideos() async {
    final authService = GoogleDriveAuthService.instance;
    await authService.init();
    if (authService.isSignedIn) {
      _loadUserVideos();
    }
  }

  Future<void> _loadUserVideos([String? query]) async {
    final authService = GoogleDriveAuthService.instance;
    final account = authService.currentAccount;
    if (account == null) return;

    setState(() {
      _isLoadingUserVideos = true;
      _userVideosError = null;
    });

    try {
      final token = await authService.getValidAccessToken();
      final videos = await GoogleDriveService.fetchUserVideos(
        accessToken: token,
        query: query ?? _searchController.text,
        isMock: account.isMock,
      );
      if (mounted) {
        setState(() {
          _userVideos = videos;
          _isLoadingUserVideos = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userVideosError = 'Gagal memuat video: $e';
          _isLoadingUserVideos = false;
        });
      }
    }
  }

  Future<void> _handleSignIn({bool forceMock = false}) async {
    AppHaptics.medium();
    final authService = GoogleDriveAuthService.instance;
    final account = await authService.signIn(forceMock: forceMock);
    if (account != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.googleDriveGreen),
          ),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.googleDriveGreen, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Terhubung sebagai ${account.displayName}',
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 12),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      _loadUserVideos();
    }
  }

  Future<void> _handleSignOut() async {
    AppHaptics.selection();
    final authService = GoogleDriveAuthService.instance;
    await authService.signOut();
    if (mounted) {
      setState(() {
        _userVideos = [];
      });
    }
  }

  Future<void> _handleSelectVideo(GoogleDriveVideo video) async {
    AppHaptics.selection();

    // If video already has public access, return it directly
    if (video.isPublic) {
      Navigator.of(context).pop(video);
      return;
    }

    // Video is private: prompt user to grant room access
    final bool? shouldShare = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _buildPermissionConfirmationSheet(video),
    );

    if (shouldShare == true && mounted) {
      _grantAccessAndPlay(video);
    }
  }

  Future<void> _grantAccessAndPlay(GoogleDriveVideo video) async {
    final authService = GoogleDriveAuthService.instance;
    final account = authService.currentAccount;
    final token = await authService.getValidAccessToken();

    // Show loading indicator dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.googleDriveGreen),
        ),
      ),
    );

    final success = await GoogleDriveService.makeFileAccessibleToRoom(
      video.id,
      accessToken: token,
      isMock: account?.isMock ?? false,
    );

    if (!mounted) return;
    Navigator.of(context).pop(); // dismiss loading dialog

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppColors.accentGreen),
          ),
          content: const Row(
            children: [
              Icon(Icons.lock_open_rounded,
                  color: AppColors.accentGreen, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Akses video berhasil dibuka untuk anggota room!',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );

      final updatedVideo = video.copyWith(isPublic: true);
      Navigator.of(context).pop(updatedVideo);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceElevated,
          content: Text(
            'Gagal mengubah izin file. Pastikan Anda pemilik file.',
            style: TextStyle(color: AppColors.accentRed, fontSize: 12),
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildPermissionConfirmationSheet(GoogleDriveVideo video) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accentYellow.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    color: AppColors.accentYellow,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Aktifkan Izin Room Nonton',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Video "${video.title}" saat ini masih berstatus privat di Google Drive Anda.',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppColors.secondaryNeon, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Agar semua peserta di room ini dapat menonton bersama, izin file akan diubah menjadi "Siapa saja yang memiliki link dapat melihat". Peserta lain tidak dapat mengedit atau menghapus file Anda.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.googleDriveGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text(
                      'Izinkan & Putar',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.add_to_drive_rounded,
                color: AppColors.googleDriveGreen, size: 22),
            SizedBox(width: 10),
            Text(
              'Google Drive Video',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.googleDriveGreen,
          indicatorWeight: 3,
          labelColor: AppColors.googleDriveGreen,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(
              icon: Icon(Icons.cloud_queue_rounded, size: 20),
              text: 'Drive Saya',
            ),
            Tab(
              icon: Icon(Icons.public_rounded, size: 20),
              text: 'Koleksi Publik',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUserDriveTab(),
          _buildPublicPresetsTab(),
        ],
      ),
    );
  }

  Widget _buildUserDriveTab() {
    return ListenableBuilder(
      listenable: GoogleDriveAuthService.instance,
      builder: (context, _) {
        final authService = GoogleDriveAuthService.instance;
        final account = authService.currentAccount;

        if (account == null) {
          return _buildConnectAccountCard(authService);
        }

        return Column(
          children: [
            _buildAccountHeader(account),
            _buildSearchBar(),
            Expanded(child: _buildUserVideoList()),
          ],
        );
      },
    );
  }

  Widget _buildConnectAccountCard(GoogleDriveAuthService authService) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.googleDriveGreen.withValues(alpha: 0.1),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.googleDriveGreen.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.googleDriveGreen.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.add_to_drive_rounded,
                  color: AppColors.googleDriveGreen,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Hubungkan Akun Google Drive',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Pilih dan tonton video MP4, MKV, atau MOV dari penyimpanan Google Drive Anda langsung di room bersama teman.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              if (authService.isLoading)
                const CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.googleDriveGreen),
                )
              else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.googleDriveGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _handleSignIn(forceMock: false),
                    icon: const Icon(Icons.login_rounded, size: 20),
                    label: const Text(
                      'Login dengan Google',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondaryNeon,
                      side: const BorderSide(color: AppColors.secondaryNeon),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _handleSignIn(forceMock: true),
                    icon: const Icon(Icons.science_outlined, size: 18),
                    label: const Text(
                      'Coba Mode Demo / Simulasi',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
              if (authService.errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accentRed.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.accentRed),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.accentRed, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Info: ${authService.errorMessage}',
                          style: const TextStyle(
                              color: AppColors.accentRed, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountHeader(GoogleDriveAccount account) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          ClipOval(
            child: Container(
              width: 36,
              height: 36,
              color: AppColors.surfaceHighlight,
              child: account.photoUrl != null && account.photoUrl!.isNotEmpty
                  ? Image.network(
                      account.photoUrl!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Center(
                        child: Text(
                          account.displayName.isNotEmpty
                              ? account.displayName[0].toUpperCase()
                              : 'G',
                          style: const TextStyle(
                            color: AppColors.googleDriveGreen,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        account.displayName.isNotEmpty
                            ? account.displayName[0].toUpperCase()
                            : 'G',
                        style: const TextStyle(
                          color: AppColors.googleDriveGreen,
                          fontWeight: FontWeight.bold,
                        ),
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
                    Flexible(
                      child: Text(
                        account.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: (account.isMock
                                ? AppColors.accentYellow
                                : AppColors.googleDriveGreen)
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: account.isMock
                              ? AppColors.accentYellow
                              : AppColors.googleDriveGreen,
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        account.isMock ? 'Demo' : 'Terhubung',
                        style: TextStyle(
                          color: account.isMock
                              ? AppColors.accentYellow
                              : AppColors.googleDriveGreen,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  account.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Keluar Akun Google Drive',
            icon: const Icon(Icons.logout_rounded,
                size: 18, color: AppColors.textSecondary),
            onPressed: _handleSignOut,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Cari video di Google Drive Anda...',
          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded,
              color: AppColors.textMuted, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded,
                      color: AppColors.textMuted, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _loadUserVideos();
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.surfaceElevated,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.googleDriveGreen),
          ),
        ),
        onSubmitted: (query) => _loadUserVideos(query),
      ),
    );
  }

  Widget _buildUserVideoList() {
    if (_isLoadingUserVideos) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.googleDriveGreen),
        ),
      );
    }

    if (_userVideosError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.accentRed, size: 36),
              const SizedBox(height: 10),
              Text(
                _userVideosError!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: AppColors.accentRed, fontSize: 12),
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surfaceHighlight,
                  foregroundColor: AppColors.textPrimary,
                ),
                onPressed: () => _loadUserVideos(),
                child: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }

    if (_userVideos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.video_collection_outlined,
                color: AppColors.textMuted, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Tidak ada video ditemukan di Google Drive',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Pastikan akun memiliki file berformat MP4, MKV, atau MOV.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () => _loadUserVideos(),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Muat Ulang'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.googleDriveGreen,
      backgroundColor: AppColors.surfaceElevated,
      onRefresh: () => _loadUserVideos(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        itemCount: _userVideos.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final video = _userVideos[index];
          return _buildVideoCard(video);
        },
      ),
    );
  }

  Widget _buildVideoCard(GoogleDriveVideo video) {
    return InkWell(
      onTap: () => _handleSelectVideo(video),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail / Icon box
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 96,
                    height: 64,
                    color: AppColors.surfaceHighlight,
                    child: video.thumbnailUrl.isNotEmpty
                        ? Image.network(
                            video.thumbnailUrl,
                            width: 96,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(
                                Icons.play_circle_fill_rounded,
                                color: AppColors.googleDriveGreen,
                                size: 28,
                              ),
                            ),
                          )
                        : const Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              color: AppColors.googleDriveGreen,
                              size: 28,
                            ),
                          ),
                  ),
                ),
                if (video.duration.isNotEmpty)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        video.duration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // Title & metadata
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${video.fileSize.isNotEmpty ? "${video.fileSize} • " : ""}${video.ownerName}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Permission status chip
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: video.isPublic
                          ? AppColors.accentGreen.withValues(alpha: 0.15)
                          : AppColors.accentYellow.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: video.isPublic
                            ? AppColors.accentGreen
                            : AppColors.accentYellow,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          video.isPublic
                              ? Icons.public_rounded
                              : Icons.lock_outline_rounded,
                          size: 11,
                          color: video.isPublic
                              ? AppColors.accentGreen
                              : AppColors.accentYellow,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          video.isPublic
                              ? 'Publik (Siap Tonton)'
                              : 'Privat (Perlu Izin)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: video.isPublic
                                ? AppColors.accentGreen
                                : AppColors.accentYellow,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.play_arrow_rounded,
              color: AppColors.secondaryNeon,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPublicPresetsTab() {
    return GenericMediaPickerScreen<GoogleDriveVideo>(
      config: GenericMediaPickerConfig<GoogleDriveVideo>(
        title: 'Koleksi Publik Google Drive',
        platformName: 'Google Drive',
        brandColor: AppColors.googleDriveGreen,
        brandIcon: Icons.add_to_drive_rounded,
        categories: const [
          'Film & Animasi Open Source',
          'Trailer & Demo 4K',
          'Dokumenter & Sains',
        ],
        categoryPresets: GoogleDriveService.categoryPresets,
        searchFunction: (query, _) async => GoogleDriveService.search(query),
        hasPagination: false,
        searchHint: 'Cari judul file atau tempel URL Google Drive...',
      ),
    );
  }
}
