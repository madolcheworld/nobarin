import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../controllers/unified_player_controller.dart';
import '../../models/video_quality.dart';

/// Bottom Sheet untuk memilih kualitas/resolusi video secara lokal di WatchParty.
class VideoQualitySheet extends StatelessWidget {
  final UnifiedPlayerController player;

  const VideoQualitySheet({
    super.key,
    required this.player,
  });

  /// Menampilkan modal bottom sheet pilihan kualitas video.
  static Future<void> show(
    BuildContext context, {
    required UnifiedPlayerController player,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => VideoQualitySheet(player: player),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final qualities = player.availableQualities;
        final selected = player.selectedQuality;
        final isAuto = selected == null || selected.isAuto;
        final mediaType = player.mediaType;

        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: AppColors.border, width: 1),
            ),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
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
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Kualitas Video',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getSourceColor(mediaType)
                                    .withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: _getSourceColor(mediaType)
                                      .withValues(alpha: 0.5),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                _getSourceLabel(mediaType),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _getSourceColor(mediaType),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Aktif: ${player.currentQualityLabel}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Content: List of Qualities or Informational Notice
              if (player.supportsQualitySelection) ...[
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: qualities.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final q = qualities[index];
                      final bool isItemActive = isAuto
                          ? q.isAuto
                          : (selected.id == q.id);

                      return _QualityTile(
                        quality: q,
                        isSelected: isItemActive,
                        onTap: () async {
                          AppHaptics.selection();
                          await player.setVideoQuality(q);
                          if (context.mounted) {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppColors.accentGreen,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Kualitas video disetel ke ${q.shortLabel}',
                                    ),
                                  ],
                                ),
                                duration: const Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: _getSourceColor(mediaType),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Menu Kualitas Bawaan ${_getSourceLabel(mediaType)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Untuk pemutar video ${_getSourceLabel(mediaType)}, resolusi dapat Anda pilih langsung melalui ikon gerigi pengaturan pada tampilan pemutar video.',
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Local Preference Footer Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.border.withValues(alpha: 0.5),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.devices_rounded,
                      size: 15,
                      color: AppColors.textMuted,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pengaturan ini berlaku khusus di perangkat Anda tanpa memengaruhi penonton lain.',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Color _getSourceColor(String type) {
    switch (type) {
      case 'youtube':
        return AppColors.youtubeRed;
      case 'twitch':
        return AppColors.twitchPurple;
      case 'vimeo':
        return AppColors.vimeoBlue;
      case 'dailymotion':
        return AppColors.dailymotionBlue;
      case 'bstation':
      case 'bilibili':
        return AppColors.bstationBlue;
      case 'google_drive':
        return AppColors.googleDriveGreen;
      default:
        return AppColors.primaryNeon;
    }
  }

  static String _getSourceLabel(String type) {
    switch (type) {
      case 'youtube':
        return 'YouTube';
      case 'twitch':
        return 'Twitch';
      case 'vimeo':
        return 'Vimeo';
      case 'dailymotion':
        return 'Dailymotion';
      case 'bstation':
      case 'bilibili':
        return 'Bstation';
      case 'google_drive':
        return 'Google Drive';
      case 'direct_url':
        return 'Direct URL / HLS';
      default:
        return type.toUpperCase();
    }
  }
}

class _QualityTile extends StatelessWidget {
  final VideoQuality quality;
  final bool isSelected;
  final VoidCallback onTap;

  const _QualityTile({
    required this.quality,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color activeColor = AppColors.primaryNeon;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.12)
                : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.8)
                  : AppColors.border,
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? activeColor.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.05),
                ),
                child: Icon(
                  quality.isAuto
                      ? Icons.auto_awesome_rounded
                      : (quality.height != null && quality.height! >= 720
                          ? Icons.hd_rounded
                          : Icons.video_settings_rounded),
                  size: 18,
                  color: isSelected ? activeColor : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),

              // Title and Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          quality.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                        ),
                        if (quality.height != null && quality.height! >= 1080) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryNeon.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'HD',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: AppColors.secondaryNeon,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (quality.badgeDescription.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        quality.badgeDescription,
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected
                              ? activeColor.withValues(alpha: 0.9)
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Radio / Checkmark
              if (isSelected)
                Icon(
                  Icons.check_circle_rounded,
                  color: activeColor,
                  size: 20,
                )
              else
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.textMuted.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
