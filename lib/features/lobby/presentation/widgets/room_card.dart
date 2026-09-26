import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../core/utils/time_formatter.dart';
import '../../../../core/widgets/frosted_glass_box.dart';
import '../../../room/controllers/unified_player_controller.dart';
import '../../../room/models/room_model.dart';

class RoomCard extends StatelessWidget {
  final RoomModel room;
  final VoidCallback onTap;

  const RoomCard({
    super.key,
    required this.room,
    required this.onTap,
  });

  ({String label, IconData icon, Color color}) _getSourceInfo(String? type, [String? url]) {
    if (type == 'screenshare') {
      return (
        label: 'Mirror Layar',
        icon: Icons.mobile_screen_share_rounded,
        color: AppColors.secondaryNeon,
      );
    }
    if (type == 'youtube') {
      return (
        label: 'YouTube',
        icon: Icons.smart_display_rounded,
        color: AppColors.youtubeRed,
      );
    }
    if (type == 'bstation' || type == 'bilibili') {
      return (
        label: 'Bstation',
        icon: Icons.tv_rounded,
        color: AppColors.bstationBlue,
      );
    }
    if (type == 'dailymotion') {
      return (
        label: 'Dailymotion',
        icon: Icons.play_circle_filled_rounded,
        color: AppColors.dailymotionBlue,
      );
    }
    if (type == 'google_drive' || type == 'gdrive') {
      return (
        label: 'Google Drive',
        icon: Icons.add_to_drive_rounded,
        color: AppColors.googleDriveGreen,
      );
    }
    if (type == 'web_browser') {
      return (
        label: 'Web Browser',
        icon: Icons.public_rounded,
        color: AppColors.webBrowserTeal,
      );
    }
    if (type == 'direct_url') {
      if (url != null &&
          (url.startsWith('p2p://') ||
           UnifiedPlayerController.isLocalFilePath(url) ||
           url.contains(':8080') ||
           url.contains('/stream'))) {
        return (
          label: 'File P2P',
          icon: Icons.folder_special_rounded,
          color: Colors.purpleAccent,
        );
      }
      return (
        label: 'Direct URL',
        icon: Icons.videocam_rounded,
        color: AppColors.secondaryNeon,
      );
    }
    return (
      label: 'Room',
      icon: Icons.meeting_room_rounded,
      color: AppColors.primaryNeon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isPlaying = room.isPlaying;
    final source = _getSourceInfo(room.currentMediaType, room.currentMediaUrl);
    final timeAgo = TimeFormatter.formatTimeAgo(room.createdAt);

    return FrostedGlassBox.card(
      onTap: () {
        AppHaptics.light();
        onTap();
      },
      borderRadius: BorderRadius.circular(18),
      isHighlighted: isPlaying,
      highlightColor: AppColors.primaryNeon,
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Left Thumbnail (16:9 ratio, fixed width)
          SizedBox(
            width: 124,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildThumbnail(context, source, isPlaying),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // 2. Right Info Section
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title
                Text(
                  room.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 6),

                // Host & Time row
                Row(
                  children: [
                    // Host icon + name
                    const Text('👑', style: TextStyle(fontSize: 10)),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        room.hostName ?? 'Host',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Time ago
                    if (timeAgo.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        timeAgo,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 8),

                // Badges row: Control Mode & Source pill
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Mode Control Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.glassFillLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.glassBorder,
                          width: 0.9,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            room.isHostOnly
                                ? Icons.lock_rounded
                                : Icons.group_rounded,
                            size: 10.5,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            room.isHostOnly ? 'Host' : 'Bebas',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Source platform indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: source.color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: source.color.withValues(alpha: 0.35),
                          width: 0.9,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(source.icon,
                              size: 10.5, color: source.color),
                          const SizedBox(width: 4),
                          Text(
                            source.label,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: source.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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

    return Stack(
      fit: StackFit.expand,
      children: [
        // Image or fallback
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
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: AppColors.primaryNeon,
                    ),
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) =>
                _buildFallbackThumbnail(source),
          )
        else
          _buildFallbackThumbnail(source),

        // Gradient overlay
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.5),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.65),
                ],
              ),
            ),
          ),
        ),

        // Top-Left: LIVE or PAUSED badge
        Positioned(
          top: 5,
          left: 5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: (isPlaying
                        ? AppColors.accentGreen
                        : AppColors.accentYellow)
                    .withValues(alpha: 0.8),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isPlaying
                        ? AppColors.accentGreen
                        : AppColors.accentYellow,
                    boxShadow: isPlaying
                        ? [
                            BoxShadow(
                              color: AppColors.accentGreen.withValues(alpha: 0.9),
                              blurRadius: 4,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  isPlaying ? 'LIVE' : 'JEDA',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    color: isPlaying
                        ? AppColors.accentGreen
                        : AppColors.accentYellow,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Bottom-Right: Viewer count pill
        Positioned(
          bottom: 5,
          right: 5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderLight, width: 0.6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.people_alt_rounded,
                  size: 9.5,
                  color: AppColors.secondaryNeon,
                ),
                const SizedBox(width: 3),
                Text(
                  '${room.participantCount}',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Active Playback Neon Line at bottom
        if (isPlaying)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 2,
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
              ),
            ),
          ),
      ],
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
            AppColors.surfaceElevated,
            source.color.withValues(alpha: 0.18),
            AppColors.background,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          source.icon,
          size: 24,
          color: source.color.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}
