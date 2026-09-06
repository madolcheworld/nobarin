import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../controllers/room_controller.dart';
import '../../controllers/sync_controller.dart';
import '../../controllers/unified_player_controller.dart';

class RoomControlsBar extends StatelessWidget {
  final SyncController syncController;
  final UnifiedPlayerController player;
  final RoomController roomController;
  final VoidCallback onOpenMediaPicker;

  const RoomControlsBar({
    super.key,
    required this.syncController,
    required this.player,
    required this.roomController,
    required this.onOpenMediaPicker,
  });

  void _copyRoomCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: roomController.currentRoom.code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Kode room ${roomController.currentRoom.code} disalin ke clipboard!',
        ),
        duration: const Duration(seconds: 2),
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
        listenable: Listenable.merge([syncController, player]),
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
                                icon: const Icon(Icons.replay_10_rounded, size: 20),
                                tooltip: 'Mundur 10 detik',
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  final target =
                                      (player.position - 10).clamp(0.0, player.duration);
                                  syncController.requestSeek(target);
                                },
                              ),
                              const SizedBox(width: 4),

                              // Play / Pause button
                              IconButton(
                                icon: Icon(
                                  player.isPlaying
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_filled_rounded,
                                  size: 24,
                                  color: AppColors.primaryNeon,
                                ),
                                tooltip: player.isPlaying ? 'Jeda' : 'Putar',
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  if (player.isPlaying) {
                                    syncController.requestPause();
                                  } else {
                                    syncController.requestPlay();
                                  }
                                },
                              ),
                              const SizedBox(width: 4),

                              // Seek +10s
                              IconButton(
                                icon: const Icon(Icons.forward_10_rounded, size: 20),
                                tooltip: 'Maju 10 detik',
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  final target =
                                      (player.position + 10).clamp(0.0, player.duration);
                                  syncController.requestSeek(target);
                                },
                              ),
                              const SizedBox(width: 6),
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
                        Flexible(
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
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
                                Flexible(
                                  child: Text(
                                    'Mode Host (Hanya host yang dapat mengontrol)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(width: 8),

                      // Room Code & Invite button + Settings
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              visualDensity: VisualDensity.compact,
                              side: const BorderSide(color: AppColors.border),
                            ),
                            onPressed: () => _copyRoomCode(context),
                            icon: const Icon(Icons.share_rounded, size: 13),
                            label: Text(
                              roomController.currentRoom.code,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),

                          // Host Settings: Switch between Host-Only and Collaborative
                          if (isHost) ...[
                            const SizedBox(width: 4),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.settings_outlined, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Pengaturan Kontrol Room',
                              color: AppColors.surfaceElevated,
                              onSelected: (mode) {
                                roomController.setControlMode(mode);
                              },
                              itemBuilder: (context) => [
                                CheckedPopupMenuItem(
                                  value: 'host_only',
                                  checked: roomController.currentRoom.isHostOnly,
                                  child: const Text('Mode: Host-Only (👑 Host Saja)'),
                                ),
                                CheckedPopupMenuItem(
                                  value: 'collaborative',
                                  checked: roomController.currentRoom.isCollaborative,
                                  child: const Text('Mode: Kolaboratif (🤝 Semua Kontrol)'),
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
}
