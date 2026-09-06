import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
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
              statusText = isMuted ? 'Mic Mati' : 'Mic Aktif (P2P)';
              statusColor =
                  isMuted ? AppColors.textSecondary : AppColors.accentGreen;
            }
            break;
          case VoiceStatus.connecting:
            statusText = 'Menghubungkan WebRTC...';
            statusColor = AppColors.accentYellow;
            break;
          case VoiceStatus.unconfigured:
            statusText =
                isMuted ? 'Voice Chat (Lokal)' : 'Voice Aktif (Lokal)';
            statusColor =
                isMuted ? AppColors.textMuted : AppColors.secondaryNeon;
            break;
          case VoiceStatus.error:
            statusText = 'Voice Offline';
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
              InkWell(
                onTap: () => voiceController.toggleMic(),
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isMuted
                        ? AppColors.surfaceHighlight
                        : AppColors.accentGreen.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isMuted
                          ? AppColors.border
                          : AppColors.accentGreen,
                      width: 1.5,
                    ),
                    boxShadow: !isMuted
                        ? [
                            BoxShadow(
                              color:
                                  AppColors.accentGreen.withValues(alpha: 0.4),
                              blurRadius: isSpeaking ? 14 : 8,
                              spreadRadius: isSpeaking ? 2 : 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isMuted
                            ? Icons.mic_off_rounded
                            : (isSpeaking
                                ? Icons.graphic_eq_rounded
                                : Icons.mic_rounded),
                        color: isMuted
                            ? AppColors.textSecondary
                            : AppColors.accentGreen,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isMuted ? 'Buka Mic' : 'Mic Nyala',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isMuted
                              ? AppColors.textSecondary
                              : AppColors.accentGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Status Dot
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                  boxShadow: status == VoiceStatus.connected && !isMuted
                      ? [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.5),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 6),

              // Status Text (takes all available remaining space and truncates if needed)
              Expanded(
                child: Text(
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
                    ? 'Batal Tuli: Dengar suara teman'
                    : 'Tuli: Matikan suara semua teman',
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
                  onPressed: () => voiceController.toggleDeafen(),
                ),
              ),

              const SizedBox(width: 2),

              // Audio Ducking Switch
              Tooltip(
                message:
                    'Audio Ducking: Otomatis mengecilkan video saat ada teman berbicara',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.hearing_rounded,
                      size: 13,
                      color: voiceController.isDucking
                          ? AppColors.secondaryNeon
                          : (voiceController.isAudioDuckingEnabled
                              ? AppColors.textSecondary
                              : AppColors.textMuted),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      'Duck',
                      style: TextStyle(
                        fontSize: 10,
                        color: voiceController.isDucking
                            ? AppColors.secondaryNeon
                            : (voiceController.isAudioDuckingEnabled
                                ? AppColors.textSecondary
                                : AppColors.textMuted),
                        fontWeight: voiceController.isDucking
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    Transform.scale(
                      scale: 0.6,
                      child: Switch(
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        value: voiceController.isAudioDuckingEnabled,
                        activeThumbColor: AppColors.secondaryNeon,
                        onChanged: (_) => voiceController.toggleAudioDucking(),
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
}
