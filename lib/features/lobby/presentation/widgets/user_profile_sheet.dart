import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../auth/presentation/auth_controller.dart';

class UserProfileSheet extends ConsumerStatefulWidget {
  const UserProfileSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const UserProfileSheet(),
    );
  }

  @override
  ConsumerState<UserProfileSheet> createState() => _UserProfileSheetState();
}

class _UserProfileSheetState extends ConsumerState<UserProfileSheet> {
  late final TextEditingController _nameController;
  late String _selectedAvatar;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).asData?.value;
    _selectedAvatar = user?.avatarUrl ?? ApiConstants.presetAvatars.first;
    _nameController = TextEditingController(text: user?.username ?? 'Tamu');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Nama pengguna tidak boleh kosong');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final updated = await ref
          .read(authControllerProvider.notifier)
          .loginAsGuest(username: name, avatarUrl: _selectedAvatar);

      if (!mounted) return;
      setState(() => _isSaving = false);

      if (updated != null) {
        AppHaptics.light();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profil berhasil diperbarui'),
            backgroundColor: AppColors.surfaceElevated,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() => _errorMessage = 'Gagal menyimpan perubahan profil');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Terjadi kesalahan saat menyimpan';
      });
    }
  }

  Future<void> _handleLogout() async {
    final user = ref.read(authControllerProvider).asData?.value;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Keluar Akun?'),
        content: Text(
          'Yakin ingin keluar dari akun ${user?.username ?? 'kamu'}?',
          style: const TextStyle(color: AppColors.textSecondary),
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

    if (confirm == true && mounted) {
      Navigator.of(context).pop(); // Close sheet
      await ref.read(authControllerProvider.notifier).logout();
      if (mounted) {
        context.go('/');
      }
    }
  }

  Future<void> _handleDeleteAccount() async {
    final user = ref.read(authControllerProvider).asData?.value;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.accentRed, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Hapus Akun & Data?',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tindakan ini akan menghapus akun ${user?.username ?? 'kamu'} beserta seluruh riwayat profil dan room yang pernah kamu buat secara permanen.',
              style:
                  const TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'Data yang telah dihapus tidak dapat dipulihkan kembali.',
              style: TextStyle(
                color: AppColors.accentRed,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
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
            child: const Text('Hapus Akun'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      Navigator.of(context).pop(); // Close sheet
      await ref.read(authControllerProvider.notifier).deleteAccount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Akun dan data berhasil dihapus.'),
            backgroundColor: AppColors.surfaceElevated,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go('/');
      }
    }
  }

  void _showPrivacyPolicyDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.privacy_tip_outlined,
                color: AppColors.primaryNeon, size: 22),
            SizedBox(width: 8),
            Text('Kebijakan Privasi', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Nobarin menghargai privasi kamu. Berikut adalah ringkasan pengelolaan data kami:',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4),
                ),
                const SizedBox(height: 12),
                const Text(
                  '1. Data Akun & Profil',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      fontSize: 13),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Kami hanya menyimpan username dan pilihan avatar anonim. Tidak ada data pribadi sensitif yang dikumpulkan tanpa persetujuan.',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.4),
                ),
                const SizedBox(height: 10),
                const Text(
                  '2. Komunikasi Real-time & VoIP',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      fontSize: 13),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Obrolan suara (WebRTC) dan text chat ditransmisikan secara terenkripsi (DTLS/SRTP/WSS) dan tidak direkam di server secara permanen.',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.4),
                ),
                const SizedBox(height: 10),
                const Text(
                  '3. Hak Penghapusan Data',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      fontSize: 13),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Kamu berhak menghapus akun dan data kamu kapan saja melalui tombol "Hapus Akun & Data" di bawah atau via tautan web.',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.4),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'URL Kebijakan Privasi Lengkap:',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                      SizedBox(height: 4),
                      SelectableText(
                        ApiConstants.privacyPolicyUrl,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.primaryNeon,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppColors.border, width: 1.2)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sheet Handle Bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Title Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Profil Pengguna',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Avatar & Online Status Preview
              Center(
                child: Stack(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primaryNeon.withValues(alpha: 0.6),
                          width: 2,
                        ),
                        boxShadow: AppColors.neonVioletGlow,
                      ),
                      child: Center(
                        child: Text(
                          _selectedAvatar,
                          style: const TextStyle(fontSize: 40),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: AppColors.accentGreen,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.surfaceElevated,
                            width: 2.5,
                          ),
                          boxShadow: AppColors.voiceActiveGlow,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Nickname Input
              const Text(
                'Nama Pengguna',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                maxLength: 24,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Masukkan nama kamu...',
                  counterText: '',
                  prefixIcon: const Icon(Icons.person_outline_rounded,
                      color: AppColors.textSecondary, size: 20),
                  errorText: _errorMessage,
                ),
              ),
              const SizedBox(height: 18),

              // Avatar Selection Grid
              const Text(
                'Pilih Avatar Emoji',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: ApiConstants.presetAvatars.map((avatar) {
                  final isSelected = _selectedAvatar == avatar;
                  return InkWell(
                    onTap: () {
                      AppHaptics.selection();
                      setState(() => _selectedAvatar = avatar);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryNeon.withValues(alpha: 0.25)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryNeon
                              : AppColors.border,
                          width: isSelected ? 1.8 : 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          avatar,
                          style: TextStyle(
                            fontSize: isSelected ? 24 : 22,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Action Buttons
              ElevatedButton(
                onPressed: _isSaving ? null : _handleSave,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Simpan Profil'),
              ),
              const SizedBox(height: 6),

              // Privacy Policy Link
              Center(
                child: TextButton.icon(
                  onPressed: _showPrivacyPolicyDialog,
                  icon: const Icon(Icons.privacy_tip_outlined,
                      size: 15, color: AppColors.textSecondary),
                  label: const Text(
                    'Kebijakan Privasi & Ketentuan',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Account Actions (Logout & Delete Account)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(
                          color: AppColors.border,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _handleLogout,
                      icon: const Icon(Icons.logout_rounded, size: 16),
                      label: const Text('Keluar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accentRed,
                        side: BorderSide(
                          color: AppColors.accentRed.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _handleDeleteAccount,
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('Hapus Akun'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
