import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

/// Floating Picture-in-Picture (PiP) badge displayed when the current user
/// is actively broadcasting their device screen outside the Nobarin app.
///
/// Prevents recursive screen-mirror tunneling inside the small PiP window and
/// provides an unmistakable live broadcast indicator with a quick stop action.
class ScreenSharePipIndicator extends StatefulWidget {
  final String roomTitle;
  final VoidCallback? onStop;

  const ScreenSharePipIndicator({
    super.key,
    required this.roomTitle,
    this.onStop,
  });

  @override
  State<ScreenSharePipIndicator> createState() =>
      _ScreenSharePipIndicatorState();
}

class _ScreenSharePipIndicatorState extends State<ScreenSharePipIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(
          color: AppColors.secondaryNeon.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background atmospheric glow
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.9,
                  colors: [
                    AppColors.secondaryNeon.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Top row: Pulsing live tag + Nobarin branding
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, _) {
                        return Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.accentRed,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accentRed.withValues(
                                  alpha: _pulseAnimation.value * 0.8,
                                ),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'LIVE BERBAGI LAYAR',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accentRed,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Center Icon + Room title
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.secondaryNeon.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.secondaryNeon.withValues(alpha: 0.4),
                          width: 1.0,
                        ),
                      ),
                      child: const Icon(
                        Icons.mobile_screen_share_rounded,
                        color: AppColors.secondaryNeon,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.roomTitle,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Subtitle
                const Text(
                  'Layar HP Anda sedang disiarkan',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),

                // Action button: Stop screen sharing
                if (widget.onStop != null)
                  SizedBox(
                    height: 26,
                    child: OutlinedButton.icon(
                      onPressed: widget.onStop,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accentRed,
                        side: BorderSide(
                          color: AppColors.accentRed.withValues(alpha: 0.6),
                          width: 0.9,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 0,
                        ),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        backgroundColor: Colors.black.withValues(alpha: 0.35),
                      ),
                      icon: const Icon(
                        Icons.stop_circle_outlined,
                        size: 13,
                        color: AppColors.accentRed,
                      ),
                      label: const Text(
                        'Hentikan Layar',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
