import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../screenshare/controllers/webrtc_screenshare_controller.dart';
import '../../controllers/queue_controller.dart';
import '../../controllers/room_controller.dart';
import '../../controllers/sync_controller.dart';
import '../../controllers/unified_player_controller.dart';

class RoomControlsBar extends StatelessWidget {
  final SyncController syncController;
  final UnifiedPlayerController player;
  final RoomController roomController;
  final QueueController? queueController;
  final WebRtcScreenShareController? screenShareController;
  final VoidCallback onOpenMediaPicker;
  final VoidCallback? onOpenQueue;

  const RoomControlsBar({
    super.key,
    required this.syncController,
    required this.player,
    required this.roomController,
    this.queueController,
    this.screenShareController,
    required this.onOpenMediaPicker,
    this.onOpenQueue,
  });

  void _copyRoomCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: roomController.currentRoom.code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Kode room disalin!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canControl = syncController.canControl;
    final isHost = roomController.isHost;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([
          syncController,
          player,
          ?queueController,
          ?screenShareController,
        ]),
        builder: (context, _) {
          final bool hasMedia = player.mediaUrl.isNotEmpty;

          return LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Playback Controls (if permitted)
                      if (canControl) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasMedia) ...[
                              // Seek -10s
                              IconButton(
                                icon: const Icon(Icons.replay_10_rounded, size: 22),
                                tooltip: 'Mundur 10 detik',
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                                onPressed: () {
                                  final target =
                                      (player.position - 10).clamp(0.0, player.duration);
                                  syncController.requestSeek(target);
                                },
                              ),
                              const SizedBox(width: 4),

                              // Play / Pause button
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryNeon.withValues(alpha: 0.18),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primaryNeon.withValues(alpha: 0.6),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primaryNeon.withValues(alpha: 0.25),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  shape: const CircleBorder(),
                                  clipBehavior: Clip.hardEdge,
                                  child: IconButton(
                                    icon: Icon(
                                      player.isPlaying
                                          ? Icons.pause_circle_filled_rounded
                                          : Icons.play_circle_filled_rounded,
                                      size: 28,
                                      color: AppColors.primaryNeon,
                                    ),
                                    tooltip: player.isPlaying ? 'Jeda' : 'Putar',
                                    padding: const EdgeInsets.all(6),
                                    constraints: const BoxConstraints(
                                      minWidth: 44,
                                      minHeight: 44,
                                    ),
                                    onPressed: () {
                                      if (player.isPlaying) {
                                        syncController.requestPause();
                                      } else {
                                        syncController.requestPlay();
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),

                              // Seek +10s
                              IconButton(
                                icon: const Icon(Icons.forward_10_rounded, size: 22),
                                tooltip: 'Maju 10 detik',
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                                onPressed: () {
                                  final target =
                                      (player.position + 10).clamp(0.0, player.duration);
                                  syncController.requestSeek(target);
                                },
                              ),
                              const SizedBox(width: 8),
                            ],

                            // Change / Select Media button
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.surfaceElevated,
                                foregroundColor: AppColors.secondaryNeon,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: const BorderSide(color: AppColors.border),
                                ),
                              ),
                              onPressed: onOpenMediaPicker,
                              icon: Icon(
                                hasMedia
                                    ? Icons.video_library_outlined
                                    : Icons.add_link_rounded,
                                size: 15,
                              ),
                              label: Text(
                                hasMedia ? 'Ganti Video' : 'Pilih Video',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.accentYellow.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lock_rounded,
                                size: 14,
                                color: AppColors.accentYellow,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Mode Host Only',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.accentYellow,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(width: 8),

                      // Room Code & Invite button + Settings
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (screenShareController != null) ...[
                            _buildScreenShareButton(context, screenShareController!),
                            const SizedBox(width: 4),
                          ],
                          if (onOpenQueue != null || queueController != null) ...[
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: AppColors.surfaceElevated,
                                foregroundColor: AppColors.primaryNeon,
                                side: const BorderSide(color: AppColors.border),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: onOpenQueue,
                              icon: Badge(
                                isLabelVisible:
                                    (queueController?.count ?? 0) > 0,
                                label: Text(
                                  '${queueController?.count ?? 0}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                backgroundColor: AppColors.primaryNeon,
                                textColor: Colors.black,
                                child: const Icon(Icons.queue_music_rounded,
                                    size: 16),
                              ),
                              label: Text(
                                (queueController?.count ?? 0) > 0
                                    ? 'Antrean (${queueController?.count})'
                                    : 'Antrean',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          IconButton(
                            icon: const Icon(Icons.share_rounded, size: 18),
                            tooltip: 'Salin Kode Room',
                            color: AppColors.secondaryNeon,
                            padding: const EdgeInsets.all(6),
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            onPressed: () => _copyRoomCode(context),
                          ),

                          // Host Settings: Switch between Host-Only and Collaborative
                          if (isHost) ...[
                            const SizedBox(width: 2),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.settings_outlined, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Pengaturan Kontrol',
                              color: AppColors.surfaceElevated,
                              onSelected: (mode) {
                                roomController.setControlMode(mode);
                              },
                              itemBuilder: (context) => [
                                CheckedPopupMenuItem(
                                  value: 'host_only',
                                  checked: roomController.currentRoom.isHostOnly,
                                  child: const Text('👑 Host Only'),
                                ),
                                CheckedPopupMenuItem(
                                  value: 'collaborative',
                                  checked: roomController.currentRoom.isCollaborative,
                                  child: const Text('🤝 Kolaboratif'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildScreenShareButton(
    BuildContext context,
    WebRtcScreenShareController controller,
  ) {
    if (controller.isSharing) {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentRed,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onPressed: () => controller.stopScreenShare(),
        icon: const Icon(Icons.stop_screen_share_rounded, size: 15),
        label: const Text('Hentikan Layar', style: TextStyle(fontSize: 12)),
      );
    }

    if (controller.isScreenSharingActive) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surfaceElevated,
          foregroundColor: AppColors.secondaryNeon,
          side: const BorderSide(color: AppColors.secondaryNeon),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${controller.sharerName ?? "Peserta"} sedang berbagi layar.',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        icon: const Icon(Icons.personal_video_rounded, size: 15),
        label: Text(
          'Layar: ${controller.sharerName ?? "Aktif"}',
          style: const TextStyle(fontSize: 12),
        ),
      );
    }

    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.surfaceElevated,
        foregroundColor: AppColors.textSecondary,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      onPressed: controller.canShareScreen
          ? () async {
              final success = await controller.startScreenShare();
              if (!success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Tidak dapat memulai berbagi layar.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            }
          : () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Hanya Host yang dapat membagikan layar pada mode Host Only.',
                  ),
                  duration: Duration(seconds: 2),
                ),
              );
            },
      icon: const Icon(Icons.screen_share_rounded, size: 15),
      label: const Text('Bagi Layar', style: TextStyle(fontSize: 12)),
    );
  }
}
