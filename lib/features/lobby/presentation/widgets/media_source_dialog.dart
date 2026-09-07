import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

enum MediaSourceType {
  youtube,
  disney,
  netflix,
  directUrl,
}

class MediaSourceDialog extends StatelessWidget {
  final ValueChanged<MediaSourceType> onSourceSelected;

  const MediaSourceDialog({
    super.key,
    required this.onSourceSelected,
  });

  static Future<MediaSourceType?> show(BuildContext context) {
    return showModalBottomSheet<MediaSourceType>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => MediaSourceDialog(
        onSourceSelected: (source) => Navigator.of(ctx).pop(source),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.video_collection_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Pilih Sumber Media',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Source Cards
          _SourceCard(
            title: 'YouTube',
            subtitle: 'Jelajahi & tonton video YouTube bersama',
            icon: Icons.play_arrow_rounded,
            iconColor: Colors.white,
            iconBackground: const Color(0xFFFF0000),
            badgeText: 'Populer',
            badgeColor: AppColors.secondaryNeon,
            isAvailable: true,
            onTap: () => onSourceSelected(MediaSourceType.youtube),
          ),

          const SizedBox(height: 12),

          _SourceCard(
            title: 'Disney+',
            subtitle: 'Film Disney, Marvel, Pixar & serial',
            icon: Icons.movie_filter_rounded,
            iconColor: Colors.white,
            iconBackground: const Color(0xFF113CCF),
            badgeText: 'Segera Hadir',
            badgeColor: Colors.amber,
            isAvailable: false,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Dukungan Disney+ segera hadir!'),
                  backgroundColor: Color(0xFF113CCF),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          _SourceCard(
            title: 'Netflix',
            subtitle: 'Film & serial bioskop pilihan',
            icon: Icons.tv_rounded,
            iconColor: const Color(0xFFE50914),
            iconBackground: const Color(0xFF1A1A1A),
            badgeText: 'Segera Hadir',
            badgeColor: Colors.amber,
            isAvailable: false,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Dukungan Netflix segera hadir!'),
                  backgroundColor: Color(0xFFE50914),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          _SourceCard(
            title: 'Direct Video URL',
            subtitle: 'Streaming file MP4, WebM, atau HLS (.m3u8)',
            icon: Icons.link_rounded,
            iconColor: Colors.white,
            iconBackground: AppColors.secondaryNeon,
            badgeText: 'URL',
            badgeColor: AppColors.primaryNeon,
            isAvailable: true,
            onTap: () => onSourceSelected(MediaSourceType.directUrl),
          ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String badgeText;
  final Color badgeColor;
  final bool isAvailable;
  final VoidCallback onTap;

  const _SourceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.badgeText,
    required this.badgeColor,
    required this.isAvailable,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isAvailable
                ? AppColors.border
                : AppColors.border.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(12),
                boxShadow: isAvailable
                    ? [
                        BoxShadow(
                          color: iconBackground.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isAvailable
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: badgeColor.withValues(alpha: 0.4),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isAvailable
                          ? AppColors.textSecondary
                          : AppColors.textSecondary.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isAvailable ? Icons.chevron_right_rounded : Icons.lock_outline_rounded,
              color: isAvailable
                  ? AppColors.textSecondary
                  : AppColors.textSecondary.withValues(alpha: 0.4),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
