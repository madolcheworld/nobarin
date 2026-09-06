import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../room/models/room_model.dart';

class RoomCard extends StatelessWidget {
  final RoomModel room;
  final VoidCallback onTap;

  const RoomCard({
    super.key,
    required this.room,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isYouTube = room.currentMediaType == 'youtube';
    final bool isPlaying = room.isPlaying;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: AppColors.primaryNeonGlow,
        highlightColor: AppColors.surfaceHighlight,
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.border,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Media Badge + Status + Viewer Count
                Row(
                  children: [
                    // Media Type Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isYouTube
                            ? const Color(0x33EF4444)
                            : const Color(0x3306B6D4),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isYouTube
                              ? AppColors.accentRed
                              : AppColors.secondaryNeon,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isYouTube
                                ? Icons.play_circle_filled_rounded
                                : Icons.videocam_rounded,
                            size: 14,
                            color: isYouTube
                                ? AppColors.accentRed
                                : AppColors.secondaryNeon,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isYouTube ? 'YouTube' : 'Direct URL',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isYouTube
                                  ? AppColors.accentRed
                                  : AppColors.secondaryNeon,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // State Indicator (Playing / Paused)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isPlaying
                            ? AppColors.accentGreen
                            : AppColors.accentYellow,
                        boxShadow: [
                          BoxShadow(
                            color: (isPlaying
                                    ? AppColors.accentGreen
                                    : AppColors.accentYellow)
                                .withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isPlaying ? 'Memutar' : 'Jeda',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isPlaying
                            ? AppColors.accentGreen
                            : AppColors.accentYellow,
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Viewers count
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.people_outline_rounded,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${room.participantCount}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

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
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: 16),

                // Bottom Row: Host info & Room code
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.surfaceElevated,
                      child: Text('👑', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        room.hostName ?? 'Host',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Room Code chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primaryNeon.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.primaryNeon.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        room.code,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryNeon,
                          letterSpacing: 0.5,
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
