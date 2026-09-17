import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class RoomLoadingView extends StatefulWidget {
  final String roomCode;
  final String? roomTitle;
  final VoidCallback? onCancel;

  const RoomLoadingView({
    super.key,
    required this.roomCode,
    this.roomTitle,
    this.onCancel,
  });

  @override
  State<RoomLoadingView> createState() => _RoomLoadingViewState();
}

class _RoomLoadingViewState extends State<RoomLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAnimation;

  Timer? _statusTimer;
  Timer? _timeoutTimer;
  int _currentStatusIndex = 0;
  bool _showCancelButton = false;

  final List<String> _statusMessages = [
    'Menghubungkan ke server room...',
    'Menyiapkan pemutar video...',
    'Menyinkronkan status nonton bareng...',
    'Memuat daftar peserta...',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _glowAnimation = Tween<double>(begin: 0.25, end: 0.65).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _statusTimer = Timer.periodic(const Duration(milliseconds: 2200), (timer) {
      if (mounted) {
        setState(() {
          _currentStatusIndex =
              (_currentStatusIndex + 1) % _statusMessages.length;
        });
      }
    });

    // Show safe cancel option after 7 seconds if connection is slow
    _timeoutTimer = Timer(const Duration(seconds: 7), () {
      if (mounted) {
        setState(() => _showCancelButton = true);
      }
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _timeoutTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated pulsing glowing icon container
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.primaryGradient,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryNeon.withValues(
                                  alpha: _glowAnimation.value,
                                ),
                                blurRadius: 36,
                                spreadRadius: 6,
                              ),
                              BoxShadow(
                                color: AppColors.secondaryNeon.withValues(
                                  alpha: _glowAnimation.value * 0.7,
                                ),
                                blurRadius: 24,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.play_arrow_rounded,
                              size: 50,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 36),

                  // Room title or default title
                  Text(
                    widget.roomTitle != null && widget.roomTitle!.isNotEmpty
                        ? widget.roomTitle!
                        : 'Menyiapkan Room',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Room Code Chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primaryNeon.withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryNeon.withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.tag_rounded,
                          size: 15,
                          color: AppColors.primaryNeon,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Kode: ${widget.roomCode}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: AppColors.primaryNeon,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Smooth horizontal progress bar
                  SizedBox(
                    width: 180,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(
                        minHeight: 4,
                        backgroundColor: AppColors.surfaceHighlight,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primaryNeon,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Animated status ticker message
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: Text(
                      _statusMessages[_currentStatusIndex],
                      key: ValueKey<int>(_currentStatusIndex),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),

                  // Timeout cancel button
                  if (_showCancelButton && widget.onCancel != null) ...[
                    const SizedBox(height: 32),
                    TextButton.icon(
                      onPressed: widget.onCancel,
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                      label: const Text(
                        'Koneksi lambat? Kembali ke Lobby',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        backgroundColor:
                            AppColors.surfaceElevated.withValues(alpha: 0.6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: AppColors.border),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
