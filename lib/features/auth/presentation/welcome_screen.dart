import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/app_haptics.dart';
import 'auth_controller.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final TextEditingController _nameController = TextEditingController();
  String _selectedAvatar = ApiConstants.presetAvatars.first;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Prefill if there's already a profile loaded
    final profile = ref.read(authControllerProvider).asData?.value;
    if (profile != null) {
      _nameController.text = profile.username;
      _selectedAvatar = profile.avatarUrl;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleStart() async {
    AppHaptics.medium();
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      AppHaptics.heavy();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Silakan masukkan nama atau nickname kamu'),
            ],
          ),
          backgroundColor: AppColors.surfaceElevated,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final profile = await ref.read(authControllerProvider.notifier).loginAsGuest(
          username: name,
          avatarUrl: _selectedAvatar,
        );
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (profile != null) {
      final targetRoom = GoRouterState.of(context).uri.queryParameters['room'];
      if (targetRoom != null && targetRoom.isNotEmpty) {
        context.go('/room/$targetRoom');
      } else {
        context.go('/lobby');
      }
    } else {
      AppHaptics.heavy();
      final authError = ref.read(authControllerProvider).error;
      final errorMsg = authError?.toString() ?? 'Gagal membuat profil. Silakan coba lagi.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: AppColors.accentRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF090B14),
              Color(0xFF141829),
              Color(0xFF0D0E15),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // App Logo & Branding
                    Center(
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.primaryGradient,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryNeon.withValues(alpha: 0.4),
                              blurRadius: 28,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 54,
                          color: Colors.white,
                        ),
                      ),
                    ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),

                    const SizedBox(height: 24),

                    // Title
                    ShaderMask(
                      shaderCallback: (bounds) =>
                          AppColors.primaryGradient.createShader(bounds),
                      child: const Text(
                        'Nobarin',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                          color: Colors.white,
                        ),
                      ),
                    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2, end: 0),

                    const SizedBox(height: 8),

                    const Text(
                      'Nonton bareng video YouTube & Stream dengan sinkronisasi real-time & Voice Chat.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ).animate().fadeIn(delay: 300.ms),

                    const SizedBox(height: 18),

                    // Feature highlights chips
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFeatureBadge('⚡ Sinkron Real-time', AppColors.primaryNeon),
                        _buildFeatureBadge('🎙️ VoIP Live Suara', AppColors.accentGreen),
                        _buildFeatureBadge('📺 YouTube & Stream', AppColors.secondaryNeon),
                      ],
                    ).animate().fadeIn(delay: 350.ms),

                    const SizedBox(height: 28),

                    // Card Form Container
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppColors.borderLight,
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Avatar Selection Header with Randomizer
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Pilih Avatar',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  AppHaptics.selection();
                                  final others = ApiConstants.presetAvatars
                                      .where((a) => a != _selectedAvatar)
                                      .toList();
                                  others.shuffle();
                                  setState(() {
                                    _selectedAvatar = others.first;
                                  });
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Text('🎲', style: TextStyle(fontSize: 14)),
                                      SizedBox(width: 4),
                                      Text(
                                        'Acak',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.secondaryNeon,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Avatar Grid/Row
                          SizedBox(
                            height: 62,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: ApiConstants.presetAvatars.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                final avatar = ApiConstants.presetAvatars[index];
                                final isSelected = avatar == _selectedAvatar;
                                return GestureDetector(
                                  onTap: () {
                                    AppHaptics.selection();
                                    setState(() {
                                      _selectedAvatar = avatar;
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.primaryNeon.withValues(alpha: 0.25)
                                          : AppColors.surfaceElevated,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected
                                            ? AppColors.primaryNeon
                                            : AppColors.border,
                                        width: isSelected ? 2.5 : 1,
                                      ),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: AppColors.primaryNeon
                                                    .withValues(alpha: 0.5),
                                                blurRadius: 12,
                                              )
                                            ]
                                          : null,
                                    ),
                                    child: Center(
                                      child: Text(
                                        avatar,
                                        style: const TextStyle(fontSize: 26),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Name Input
                          const Text(
                            'Nama / Nickname Kamu',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),

                          TextField(
                            controller: _nameController,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Misal: Alex, PopcornMaster',
                              prefixIcon: const Icon(
                                Icons.person_outline_rounded,
                                color: AppColors.secondaryNeon,
                              ),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () => _nameController.clear(),
                              ),
                            ),
                            onSubmitted: (_) => _handleStart(),
                          ),

                          const SizedBox(height: 28),

                          // Start Button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primaryNeon.withValues(alpha: 0.35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _isLoading ? null : _handleStart,
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Mulai Nonton',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 20,
                                            color: Colors.white,
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1, end: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
