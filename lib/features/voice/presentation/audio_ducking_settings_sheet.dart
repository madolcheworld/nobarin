import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../controllers/webrtc_voice_controller.dart';

/// Modal bottom sheet to customize Smart Audio Ducking settings
class AudioDuckingSettingsSheet extends StatelessWidget {
  final WebRtcVoiceController voiceController;

  const AudioDuckingSettingsSheet({
    super.key,
    required this.voiceController,
  });

  /// Displays [AudioDuckingSettingsSheet] as a modern styled modal bottom sheet
  static Future<void> show(
    BuildContext context, {
    required WebRtcVoiceController voiceController,
  }) {
    AppHaptics.medium();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AudioDuckingSettingsSheet(
        voiceController: voiceController,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: voiceController,
      builder: (context, _) {
        final config = voiceController.duckingConfig;
        final isEnabled = config.enabled;
        final currentFactor = config.duckingFactor;
        final isCurrentlyDucking = voiceController.isDucking;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: AppColors.border, width: 1.2),
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                10,
                20,
                24 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 4, bottom: 12),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.textSecondary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.secondaryNeon.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.hearing_rounded,
                            color: AppColors.secondaryNeon,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Smart Audio Ducking',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Redam suara video saat mengobrol',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Real-time Status Card
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: !isEnabled
                            ? AppColors.surfaceElevated
                            : (isCurrentlyDucking
                                ? AppColors.primaryNeon.withValues(alpha: 0.15)
                                : AppColors.surfaceElevated),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: !isEnabled
                              ? AppColors.border
                              : (isCurrentlyDucking
                                  ? AppColors.primaryNeon
                                  : AppColors.border),
                          width: isCurrentlyDucking ? 1.4 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            !isEnabled
                                ? Icons.volume_off_rounded
                                : (isCurrentlyDucking
                                    ? Icons.graphic_eq_rounded
                                    : Icons.volume_up_rounded),
                            size: 18,
                            color: !isEnabled
                                ? AppColors.textMuted
                                : (isCurrentlyDucking
                                    ? AppColors.primaryNeon
                                    : AppColors.secondaryNeon),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              !isEnabled
                                  ? 'Status: Audio Ducking Nonaktif'
                                  : (isCurrentlyDucking
                                      ? 'Sedang meredam suara video (ke ${(currentFactor * 100).round()}%)'
                                      : 'Siaga: Suara video normal (100%)'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: !isEnabled
                                    ? AppColors.textMuted
                                    : (isCurrentlyDucking
                                        ? AppColors.primaryNeon
                                        : AppColors.textPrimary),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Master Toggle
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Aktifkan Audio Ducking',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Turunkan volume video otomatis saat bicara',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: isEnabled,
                            activeThumbColor: AppColors.primaryNeon,
                            onChanged: (val) {
                              AppHaptics.selection();
                              voiceController.toggleAudioDucking();
                            },
                          ),
                        ],
                      ),
                    ),

                    if (isEnabled) ...[
                      const SizedBox(height: 18),

                      // Preset Selector Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Tingkat Suara Video Saat Obrolan',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            '${(currentFactor * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.secondaryNeon,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Presets Grid / Row
                      Row(
                        children: DuckingPreset.values.map((preset) {
                          final isSelected =
                              (currentFactor - preset.factor).abs() < 0.05;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: InkWell(
                                onTap: () {
                                  AppHaptics.selection();
                                  voiceController
                                      .setDuckingFactor(preset.factor);
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primaryNeon
                                            .withValues(alpha: 0.18)
                                        : AppColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.primaryNeon
                                          : AppColors.border,
                                      width: isSelected ? 1.4 : 1.0,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        preset.label.split(' ')[0],
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: isSelected
                                              ? AppColors.primaryNeon
                                              : AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${(preset.factor * 100).round()}%',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected
                                              ? AppColors.textPrimary
                                              : AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 10),

                      // Continuous Volume Slider
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: AppColors.primaryNeon,
                          inactiveTrackColor: AppColors.surfaceHighlight,
                          thumbColor: AppColors.primaryNeon,
                          overlayColor:
                              AppColors.primaryNeon.withValues(alpha: 0.2),
                          trackHeight: 4,
                        ),
                        child: Slider(
                          value: currentFactor,
                          min: 0.0,
                          max: 0.8,
                          divisions: 16,
                          onChanged: (val) {
                            voiceController.setDuckingFactor(val);
                          },
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Advanced Options: Duck When I Speak
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Kecilkan saat saya berbicara',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Cegah suara speaker video masuk ke mic kamu',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: config.duckWhenSpeakingLocally,
                              activeThumbColor: AppColors.secondaryNeon,
                              onChanged: (val) {
                                AppHaptics.selection();
                                voiceController.setDuckWhenSpeakingLocally(val);
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Advanced Options: Smooth Transition (Fade in / out)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Transisi Suara Halus (Smooth Fade)',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Perubahan volume perlahan dan nyaman di telinga',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: config.smoothTransition,
                              activeThumbColor: AppColors.secondaryNeon,
                              onChanged: (val) {
                                AppHaptics.selection();
                                voiceController.updateDuckingConfig(
                                  config.copyWith(smoothTransition: val),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
