import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

enum MediaSourceType {
  youtube,
  googleDrive,
  dailymotion,
  bstation,
  localVideo,
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
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
          const SizedBox(height: 14),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
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

          const SizedBox(height: 14),

          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Source Cards
                  _SourceCard(
                    title: 'YouTube',
                    subtitle: 'Cari & tonton video YouTube',
                    icon: Icons.play_arrow_rounded,
                    iconColor: Colors.white,
                    iconBackground: const Color(0xFFFF0000),
                    onTap: () => onSourceSelected(MediaSourceType.youtube),
                  ),


                  const SizedBox(height: 10),

                  _SourceCard(
                    title: 'Google Drive',
                    subtitle: 'File video dari Google Drive',
                    icon: Icons.cloud_queue_rounded,
                    iconColor: Colors.white,
                    iconBackground: const Color(0xFF0F9D58),
                    onTap: () => onSourceSelected(MediaSourceType.googleDrive),
                  ),

                  const SizedBox(height: 10),

                  _SourceCard(
                    title: 'Dailymotion',
                    subtitle: 'Video trending & klip musik',
                    icon: Icons.play_circle_filled_rounded,
                    iconColor: Colors.white,
                    iconBackground: const Color(0xFF0066DC),
                    onTap: () => onSourceSelected(MediaSourceType.dailymotion),
                  ),

                  const SizedBox(height: 10),

                  _SourceCard(
                    title: 'Bstation (Bilibili)',
                    subtitle: 'Anime & kreator video Bilibili',
                    icon: Icons.smart_display_rounded,
                    iconColor: Colors.white,
                    iconBackground: const Color(0xFF00A1D6),
                    onTap: () => onSourceSelected(MediaSourceType.bstation),
                  ),

                  const SizedBox(height: 10),

                  _SourceCard(
                    title: 'Video Lokal (P2P Internet)',
                    subtitle: 'Streaming file video lokal via internet',
                    icon: Icons.wifi_tethering_rounded,
                    iconColor: Colors.white,
                    iconBackground: const Color(0xFF00B4D8),
                    onTap: () => onSourceSelected(MediaSourceType.localVideo),
                  ),

                  const SizedBox(height: 10),

                  _SourceCard(
                    title: 'Direct Video URL',
                    subtitle: 'Streaming link MP4, WebM, atau HLS',
                    icon: Icons.link_rounded,
                    iconColor: Colors.white,
                    iconBackground: AppColors.secondaryNeon,
                    onTap: () => onSourceSelected(MediaSourceType.directUrl),
                  ),
                ],
              ),
            ),
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
  final VoidCallback onTap;

  const _SourceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: iconBackground.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
