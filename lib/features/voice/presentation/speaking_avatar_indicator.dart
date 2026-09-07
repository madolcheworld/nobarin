import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

/// Visual avatar indicator that displays a participant's avatar, host status,
/// microphone mute badge, and a reactive neon glow when speaking.
class SpeakingAvatarIndicator extends StatelessWidget {
  final String avatar;
  final String name;
  final bool isSpeaking;
  final bool isMuted;
  final bool isHost;
  final bool isCoHost;
  final bool showName;
  final double size;

  const SpeakingAvatarIndicator({
    super.key,
    required this.avatar,
    required this.name,
    required this.isSpeaking,
    this.isMuted = false,
    this.isHost = false,
    this.isCoHost = false,
    this.showName = true,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final avatarWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        // Avatar circular container with animated neon glow
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surfaceElevated,
            border: Border.all(
              color: isSpeaking
                  ? AppColors.accentGreen
                  : (isHost
                      ? AppColors.accentYellow
                      : (isCoHost ? AppColors.secondaryNeon : AppColors.border)),
              width: isSpeaking ? 2.5 : ((isHost || isCoHost) ? 1.8 : 1.2),
            ),
            boxShadow: isSpeaking
                ? [
                    BoxShadow(
                      color: AppColors.accentGreen.withValues(alpha: 0.6),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ]
                : (isCoHost
                    ? [
                        BoxShadow(
                          color: AppColors.secondaryNeon.withValues(alpha: 0.25),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ]
                    : null),
          ),
          child: Center(
            child: Text(
              avatar,
              style: TextStyle(fontSize: size * 0.45),
            ),
          ),
        ),

        // Crown badge for Room Host / Star badge for Co-Host
        if (isHost)
          Positioned(
            top: -6,
            right: -3,
            child: Text(
              '👑',
              style: TextStyle(fontSize: size * 0.3),
            ),
          )
        else if (isCoHost)
          Positioned(
            top: -6,
            right: -3,
            child: Text(
              '⭐',
              style: TextStyle(fontSize: size * 0.3),
            ),
          ),

        // Speaking indicator dot
        if (isSpeaking)
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: const BoxDecoration(
                color: AppColors.accentGreen,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.volume_up_rounded,
                size: size * 0.2,
                color: Colors.black,
              ),
            ),
          )
        else if (isMuted)
          // Mute badge when not speaking
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: const BoxDecoration(
                color: AppColors.surfaceHighlight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mic_off_rounded,
                size: size * 0.18,
                color: AppColors.textMuted,
              ),
            ),
          ),
      ],
    );

    if (!showName) {
      return avatarWidget;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        avatarWidget,
        const SizedBox(height: 4),
        Text(
          name,
          style: TextStyle(
            fontSize: 10,
            color: isSpeaking ? AppColors.accentGreen : AppColors.textSecondary,
            fontWeight: isSpeaking ? FontWeight.bold : FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
