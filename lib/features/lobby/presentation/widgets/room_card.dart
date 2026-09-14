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
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.borderLight,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 16:9 Thumbnail Section with Overlays
                _buildThumbnail(context, source, isPlaying),

                // 2. Info Content Section
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Room Title
                      Text(
                        room.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      // Room Description (if available)
                      if (room.description != null &&
                          room.description!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          room.description!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Bottom Row: Host info, Mode, & Room Code
                      Row(
                        children: [
                          // Left side: Host and Control Mode pills
                          Expanded(
                            child: Row(
                              children: [
                                // Host Pill
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3.5),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppColors.border,
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text('👑',
                                            style: TextStyle(fontSize: 10)),
                                        const SizedBox(width: 4),
                                        Flexible(
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
                                ),

                                const SizedBox(width: 5),

                                // Control Mode Pill
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: room.isHostOnly
                                        ? AppColors.accentYellow
                                            .withValues(alpha: 0.12)
                                        : AppColors.secondaryNeon
                                            .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: room.isHostOnly
                                          ? AppColors.accentYellow
                                              .withValues(alpha: 0.3)
                                          : AppColors.secondaryNeon
                                              .withValues(alpha: 0.3),
                                      width: 0.6,
                                    ),
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
                              ],
                            ),
                          ),

                          const SizedBox(width: 6),

                          // Room Code Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3.5),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.primaryNeon.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.primaryNeon
                                    .withValues(alpha: 0.4),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(
    BuildContext context,
    ({String label, IconData icon, Color color}) source,
    bool isPlaying,
  ) {
    final thumbUrl = room.thumbnailUrl;
    final hasThumb = thumbUrl != null && thumbUrl.isNotEmpty;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Background Image or Fallback Graphic
          if (hasThumb)
            Image.network(
              thumbUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: AppColors.surface,
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryNeon,
                      ),
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return _buildFallbackThumbnail(source);
              },
            )
          else
            _buildFallbackThumbnail(source),

          // 2. Top Vignette Overlay (for contrast with badges)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 55,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.75),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 3. Bottom Vignette Overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 45,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.75),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),


          // 5. Top-Left: Media Platform Badge
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: source.color.withValues(alpha: 0.7),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(source.icon, size: 13, color: source.color),
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
          ),

          // 6. Top-Right: Live Status + Viewer Count
          Positioned(
            top: 10,
            right: 10,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Live / Paused Status
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (isPlaying
                              ? AppColors.accentGreen
                              : AppColors.accentYellow)
                          .withValues(alpha: 0.7),
                      width: 0.8,
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
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 4),
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

                const SizedBox(width: 6),

                // Viewers count pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.borderLight,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.people_alt_rounded,
                        size: 12,
                        color: AppColors.secondaryNeon,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${room.participantCount}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 7. Active Playback Neon Progress Line
          if (isPlaying)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 2.5,
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFallbackThumbnail(
    ({String label, IconData icon, Color color}) source,
  ) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF15132A),
            source.color.withValues(alpha: 0.16),
            const Color(0xFF0D101C),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: source.color.withValues(alpha: 0.12),
                border: Border.all(
                  color: source.color.withValues(alpha: 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: source.color.withValues(alpha: 0.15),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Icon(
                source.icon,
                size: 26,
                color: source.color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              source.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: source.color.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
