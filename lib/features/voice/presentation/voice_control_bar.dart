import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import 'package:nobarin/core/utils/app_haptics.dart';
import '../controllers/webrtc_voice_controller.dart';

class VoiceControlBar extends StatelessWidget {
  final WebRtcVoiceController voiceController;

  const VoiceControlBar({super.key, required this.voiceController});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: voiceController,
      builder: (context, _) {
        final isMuted = voiceController.isMicMuted;
        final isDeafened = voiceController.isDeafened;
        final isSpeaking = voiceController.isLocalSpeaking;
        final status = voiceController.status;

        String statusText;
        Color statusColor;
        switch (status) {
          case VoiceStatus.connected:
            if (isSpeaking) {
              statusText = 'Berbicara...';
              statusColor = AppColors.accentGreen;
            } else {
              statusText = isMuted ? 'Mic Mati' : 'Mic Aktif';
              statusColor =
                  isMuted ? AppColors.textSecondary : AppColors.accentGreen;
            }
            break;
          case VoiceStatus.connecting:
            statusText = 'Menghubungkan...';
            statusColor = AppColors.accentYellow;
            break;
          case VoiceStatus.unconfigured:
            statusText = isMuted ? 'Voice Siap' : 'Voice Aktif';
            statusColor =
                isMuted ? AppColors.textMuted : AppColors.secondaryNeon;
            break;
          case VoiceStatus.error:
            statusText = 'Voice Gagal (Coba Lagi)';
            statusColor = AppColors.accentRed;
            break;
          case VoiceStatus.disconnected:
            statusText = 'Voice Terputus';
            statusColor = AppColors.textMuted;
            break;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: const BoxDecoration(
            color: AppColors.surfaceElevated,
            border: Border(
              top: BorderSide(color: AppColors.border),
            ),
          ),
          child: Row(
            children: [
              // Mic Toggle Button
              Tooltip(
                message: isMuted ? 'Nyalakan Mikrofon' : 'Matikan Mikrofon',
                child: InkWell(
                  onTap: () {
                    AppHaptics.medium();
                    voiceController.toggleMic();
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: isMuted
                          ? AppColors.surfaceHighlight
                          : AppColors.accentGreen.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isMuted
                            ? AppColors.border
                            : AppColors.accentGreen,
                        width: 1.5,
                      ),
                      boxShadow: !isMuted
                          ? [
                              BoxShadow(
                                color: AppColors.accentGreen
                                    .withValues(alpha: 0.4),
                                blurRadius: isSpeaking ? 14 : 8,
                                spreadRadius: isSpeaking ? 2 : 1,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      isMuted
                          ? Icons.mic_off_rounded
                          : (isSpeaking
                              ? Icons.graphic_eq_rounded
                              : Icons.mic_rounded),
                      color: isMuted
                          ? AppColors.textSecondary
                          : AppColors.accentGreen,
                      size: 17,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Status Text
              Expanded(
                child: status == VoiceStatus.error
                    ? InkWell(
                        onTap: () => voiceController.reconnect(),
                        borderRadius: BorderRadius.circular(4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                statusText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.refresh_rounded,
                              size: 13,
                              color: AppColors.accentRed,
                            ),
                          ],
                        ),
                      )
                    : Text(
                        statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: statusColor,
                        ),
                      ),
              ),

              const SizedBox(width: 4),

              // Deafen Toggle Button
              Tooltip(
                message: isDeafened
                    ? 'Batal Bungkam Audio Teman'
                    : 'Bungkam Audio Teman',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(
                    isDeafened
                        ? Icons.headset_off_rounded
                        : Icons.headset_rounded,
                    size: 18,
                    color: isDeafened
                        ? AppColors.accentRed
                        : AppColors.textSecondary,
                  ),
                  onPressed: () {
                    AppHaptics.selection();
                    voiceController.toggleDeafen();
                  },
                ),
              ),

              const SizedBox(width: 2),

              // Audio Ducking Toggle Button (Consistent IconButton)
              Tooltip(
                message: voiceController.isAudioDuckingEnabled
                    ? 'Audio Ducking: Aktif'
                    : 'Audio Ducking: Nonaktif',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(
                    Icons.hearing_rounded,
                    size: 18,
                    color: voiceController.isAudioDuckingEnabled
                        ? AppColors.secondaryNeon
                        : AppColors.textSecondary,
                  ),
                  onPressed: () {
                    AppHaptics.selection();
                    voiceController.toggleAudioDucking();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
