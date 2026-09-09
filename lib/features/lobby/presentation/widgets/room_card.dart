import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../room/models/room_model.dart';

class RoomCard extends StatelessWidget {
  final RoomModel room;
  final VoidCallback onTap;

  const RoomCard({
    super.key,
    required this.room,
    required this.onTap,
  });

  ({String label, IconData icon, Color color}) _getSourceInfo(String? type) {
    switch (type) {
      case 'youtube':
        return (
          label: 'YouTube',
          icon: Icons.play_circle_filled_rounded,
          color: AppColors.youtubeRed,
        );
      case 'twitch':
        return (
          label: 'Twitch',
          icon: Icons.live_tv_rounded,
          color: AppColors.twitchPurple,
        );
      case 'vimeo':
        return (
          label: 'Vimeo',
          icon: Icons.video_collection_rounded,
          color: AppColors.vimeoBlue,
        );
      case 'bstation':
      case 'bilibili':
        return (
          label: 'Bstation',
          icon: Icons.smart_display_rounded,
          color: AppColors.bstationBlue,
        );
      case 'google_drive':
        return (
          label: 'Google Drive',
          icon: Icons.cloud_queue_rounded,
          color: AppColors.googleDriveGreen,
        );
      case 'dailymotion':
        return (
          label: 'Dailymotion',
          icon: Icons.play_circle_filled_rounded,
          color: AppColors.dailymotionBlue,
        );
      default:
        return (
          label: 'Direct URL',
          icon: Icons.videocam_rounded,
          color: AppColors.secondaryNeon,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isPlaying = room.isPlaying;
    final source = _getSourceInfo(room.currentMediaType);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AppHaptics.light();
          onTap();
        },
        borderRadius: BorderRadius.circular(18),
        splashColor: AppColors.primaryNeonGlow,
        highlightColor: AppColors.surfaceHighlight,
        child: Ink(
          decoration: BoxDecoration(
            gradient: AppColors.cardGradient,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.borderLight,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Media Badge + Live Status + Viewer Count
                Row(
                  children: [
                    // Media Platform Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: source.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: source.color.withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(source.icon, size: 14, color: source.color),
                          const SizedBox(width: 5),
                          Text(
                            source.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: source.color,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Playing / Paused Pulse Indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (isPlaying
                                ? AppColors.accentGreen
                                : AppColors.accentYellow)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (isPlaying
                                  ? AppColors.accentGreen
                                  : AppColors.accentYellow)
                              .withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isPlaying
                                  ? AppColors.accentGreen
                                  : AppColors.accentYellow,
                              boxShadow: isPlaying
                                  ? [
                                      BoxShadow(
                                        color: AppColors.accentGreen
                                            .withValues(alpha: 0.8),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      )
                                    ]
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isPlaying ? 'LIVE' : 'JEDA',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: isPlaying
                                  ? AppColors.accentGreen
                                  : AppColors.accentYellow,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Viewers count pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.people_alt_rounded,
                            size: 13,
                            color: AppColors.secondaryNeon,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${room.participantCount}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Title
                Text(
                  room.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                if (room.description != null &&
                    room.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    room.description!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: 16),

                // Bottom Row: Host info, Mode, & Room code
                Row(
                  children: [
                    // Host Pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('👑', style: TextStyle(fontSize: 11)),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 100),
                            child: Text(
                              room.hostName ?? 'Host',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 6),

                    // Control Mode Pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: room.isHostOnly
                            ? AppColors.accentYellow.withValues(alpha: 0.12)
                            : AppColors.secondaryNeon.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        room.isHostOnly ? 'Host-Only' : 'Kolaboratif',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: room.isHostOnly
                              ? AppColors.accentYellow
                              : AppColors.secondaryNeon,
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Room Code Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryNeon.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.primaryNeon.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        room.code,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryNeon,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
