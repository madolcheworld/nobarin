import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../screenshare/controllers/webrtc_screenshare_controller.dart';
import '../../../voice/controllers/webrtc_voice_controller.dart';
import '../../../voice/presentation/audio_ducking_settings_sheet.dart';
import '../../controllers/queue_controller.dart';
import '../../controllers/room_controller.dart';
import '../../controllers/sync_controller.dart';
import '../../controllers/unified_player_controller.dart';
import '../../models/room_model.dart';

class RoomControlsBar extends StatelessWidget {
  final SyncController syncController;
  final UnifiedPlayerController player;
  final RoomController roomController;
  final QueueController? queueController;
  final WebRtcScreenShareController? screenShareController;
  final WebRtcVoiceController? voiceController;
  final VoidCallback onOpenMediaPicker;
  final VoidCallback? onOpenQueue;

  const RoomControlsBar({
    super.key,
    required this.syncController,
    required this.player,
    required this.roomController,
    this.queueController,
    this.screenShareController,
    this.voiceController,
    required this.onOpenMediaPicker,
    this.onOpenQueue,
  });

  static void copyRoomCode(BuildContext context, String code) {
    AppHaptics.selection();
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.secondaryNeon),
        ),
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.secondaryNeon,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              'Kode room $code berhasil disalin!',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static void showShareModal(BuildContext context, RoomModel currentRoom) {
    AppHaptics.light();
    final inviteText =
        'Yuk nonton bareng "${currentRoom.title}" di Nobarin!\nKode Room: ${currentRoom.code}';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: AppColors.atmosphericCardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Indicator Bar
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryNeon.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.share_rounded,
                      color: AppColors.secondaryNeon,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bagikan Room',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentRoom.title,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                    onPressed: () => Navigator.of(bottomSheetContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Room Code Card with Copy Action
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.secondaryNeon.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'KODE ROOM',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currentRoom.code,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppColors.secondaryNeon,
                            letterSpacing: 3,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.secondaryNeon,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        copyRoomCode(context, currentRoom.code);
                        Navigator.of(bottomSheetContext).pop();
                      },
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: const Text(
                        'Salin',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Copy Invite Message Full Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.surfaceElevated,
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    AppHaptics.selection();
                    Clipboard.setData(ClipboardData(text: inviteText));
                    Navigator.of(bottomSheetContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppColors.surfaceElevated,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(
                              color: AppColors.secondaryNeon),
                        ),
                        content: const Row(
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.secondaryNeon,
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Pesan undangan berhasil disalin!',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 16,
                    color: AppColors.secondaryNeon,
                  ),
                  label: const Text(
                    'Salin Teks Undangan Lengkap',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canControl = syncController.canControl;
    final isHost = roomController.isHost;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassFillHeavy,
        border: Border(
          bottom: BorderSide(color: AppColors.glassBorder, width: 0.8),
        ),
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([
          syncController,
          player,
          ?queueController,
          ?screenShareController,
          ?voiceController,
        ]),
        builder: (context, _) {
          final bool hasMedia = player.mediaUrl.isNotEmpty;

          return SizedBox(
            height: 44,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 1. Unified Voice Capsule (Mic + Deafen + Audio Ducking)
                  if (voiceController != null) ...[
                    _buildVoiceCapsule(context, voiceController!),
                    const SizedBox(width: 8),
                    Container(
                      height: 18,
                      width: 1,
                      color: AppColors.borderLight.withValues(alpha: 0.3),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // 2. Media Action Button: Ganti Video (when media is loaded or screen share is active, and canControl)
                  if ((hasMedia || (screenShareController?.isScreenSharingActive == true)) && canControl) ...[
                    _buildMediaActionButton(),
                    const SizedBox(width: 8),
                  ],

                  // 3. Screen Share Active Capsule (Only shown when a screen share session is currently active)
                  if (screenShareController != null &&
                      screenShareController!.isScreenSharingActive) ...[
                    _buildScreenShareButton(context, screenShareController!),
                    const SizedBox(width: 8),
                  ],

                  // 4. Room Control Mode Pill
                  _buildControlModePill(context, isHost),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVoiceCapsule(BuildContext context, WebRtcVoiceController voice) {
    final isMuted = voice.isMicMuted;
    final isSpeaking = voice.isLocalSpeaking;
    final isDeafened = voice.isDeafened;
    final status = voice.status;

    String label;
    if (status == VoiceStatus.connecting) {
      label = 'Koneksi...';
    } else if (status == VoiceStatus.error) {
      label = 'Error';
    } else if (isSpeaking) {
      label = 'Bicara...';
    } else {
      label = isMuted ? 'Mic Mati' : 'Mic Aktif';
    }

    final Color statusColor = isMuted
        ? AppColors.accentRed
        : (status == VoiceStatus.error
            ? AppColors.accentRed
            : (status == VoiceStatus.connecting
                ? AppColors.accentYellow
                : AppColors.accentGreen));

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: isMuted
            ? AppColors.accentRed.withValues(alpha: 0.10)
            : AppColors.accentGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMuted
              ? AppColors.accentRed.withValues(alpha: 0.35)
              : AppColors.accentGreen.withValues(alpha: 0.5),
          width: 1.0,
        ),
        boxShadow: !isMuted && isSpeaking
            ? [
                BoxShadow(
                  color: AppColors.accentGreen.withValues(alpha: 0.35),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Mic Button with status label
          Tooltip(
            message: isMuted ? 'Nyalakan Mikrofon' : 'Matikan Mikrofon',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  AppHaptics.medium();
                  voice.toggleMic();
                },
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(16)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isMuted
                            ? Icons.mic_off_rounded
                            : (isSpeaking
                                ? Icons.graphic_eq_rounded
                                : Icons.mic_rounded),
                        size: 15,
                        color: statusColor,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isMuted ? FontWeight.w600 : FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Divider inside voice capsule
          Container(
            width: 1,
            height: 16,
            color: isMuted
                ? AppColors.accentRed.withValues(alpha: 0.25)
                : AppColors.accentGreen.withValues(alpha: 0.3),
          ),

          // 2. Deafen Button (headset)
          Tooltip(
            message: isDeafened
                ? 'Batal Bungkam Audio Teman'
                : 'Bungkam Audio Teman',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  AppHaptics.selection();
                  voice.toggleDeafen();
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Icon(
                    isDeafened
                        ? Icons.headset_off_rounded
                        : Icons.headset_rounded,
                    size: 15,
                    color: isDeafened
                        ? AppColors.accentRed
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),

          // 3. Audio Ducking / Voice Settings Button
          Tooltip(
            message: voice.isAudioDuckingEnabled
                ? 'Audio Ducking: Aktif (${(voice.duckingFactor * 100).round()}%)\nTap untuk buka pengaturan suara'
                : 'Pengaturan Suara & Audio Ducking',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  AppHaptics.selection();
                  AudioDuckingSettingsSheet.show(
                    context,
                    voiceController: voice,
                  );
                },
                borderRadius:
                    const BorderRadius.horizontal(right: Radius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.only(
                      left: 4, right: 9, top: 6, bottom: 6),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        Icons.hearing_rounded,
                        size: 15,
                        color: voice.isAudioDuckingEnabled
                            ? AppColors.secondaryNeon
                            : AppColors.textMuted,
                      ),
                      if (voice.isAudioDuckingEnabled && voice.isDucking)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primaryNeon,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaActionButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AppHaptics.light();
          onOpenMediaPicker();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.secondaryNeon.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.secondaryNeon.withValues(alpha: 0.45),
              width: 0.8,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_horiz_rounded,
                  size: 14, color: AppColors.secondaryNeon),
              SizedBox(width: 4),
              Text(
                'Ganti',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.secondaryNeon,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlModePill(BuildContext context, bool isHost) {
    final isHostOnly = roomController.currentRoom.isHostOnly;

    if (!isHost) {
      return Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: AppColors.glassFillLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isHostOnly
                ? AppColors.accentYellow.withValues(alpha: 0.45)
                : AppColors.secondaryNeon.withValues(alpha: 0.45),
            width: 0.9,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isHostOnly ? Icons.lock_rounded : Icons.group_rounded,
              size: 12,
              color:
                  isHostOnly ? AppColors.accentYellow : AppColors.secondaryNeon,
            ),
            const SizedBox(width: 4),
            Text(
              isHostOnly ? 'Host Only' : 'Kolaboratif',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isHostOnly
                    ? AppColors.accentYellow
                    : AppColors.secondaryNeon,
              ),
            ),
          ],
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Ubah Mode Kontrol',
      color: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      onSelected: (mode) {
        AppHaptics.selection();
        roomController.setControlMode(mode);
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: 'host_only',
          checked: isHostOnly,
          child: const Text('👑 Host Only (Hanya host yang kontrol)'),
        ),
        CheckedPopupMenuItem(
          value: 'collaborative',
          checked: !isHostOnly,
          child: const Text('🤝 Kolaboratif (Semua peserta kontrol)'),
        ),
      ],
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: AppColors.glassFillLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isHostOnly
                ? AppColors.accentYellow.withValues(alpha: 0.45)
                : AppColors.secondaryNeon.withValues(alpha: 0.45),
            width: 0.9,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isHostOnly ? '👑 Host Only' : '🤝 Kolaboratif',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: isHostOnly
                    ? AppColors.accentYellow
                    : AppColors.secondaryNeon,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 15,
              color:
                  isHostOnly ? AppColors.accentYellow : AppColors.secondaryNeon,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScreenShareButton(
    BuildContext context,
    WebRtcScreenShareController controller,
  ) {
    if (controller.isSharing) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            AppHaptics.medium();
            controller.stopScreenShare();
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: AppColors.accentRed.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.accentRed.withValues(alpha: 0.6),
                width: 0.8,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.stop_screen_share_rounded,
                    size: 14, color: AppColors.accentRed),
                SizedBox(width: 4),
                Text(
                  'Hentikan Layar',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accentRed,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (controller.isScreenSharingActive) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            AppHaptics.selection();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppColors.surfaceElevated,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: AppColors.secondaryNeon),
                ),
                content: Row(
                  children: [
                    const Icon(Icons.personal_video_rounded,
                        color: AppColors.secondaryNeon, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${controller.sharerName ?? "Peserta"} sedang berbagi layar.',
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.secondaryNeon.withValues(alpha: 0.5),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.personal_video_rounded,
                    size: 14, color: AppColors.secondaryNeon),
                const SizedBox(width: 4),
                Text(
                  'Layar: ${controller.sharerName ?? "Aktif"}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondaryNeon,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
