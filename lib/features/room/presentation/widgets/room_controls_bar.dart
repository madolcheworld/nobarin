import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
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
    AppHaptics.selection();
    Clipboard.setData(ClipboardData(text: roomController.currentRoom.code));
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
              'Kode room ${roomController.currentRoom.code} berhasil disalin!',
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

  void _showShareModal(BuildContext context) {
    AppHaptics.light();
    final currentRoom = roomController.currentRoom;
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
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
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
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => Navigator.of(bottomSheetContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Room Code Card
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.secondaryNeon.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'KODE ROOM',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            currentRoom.code,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 3.0,
                              color: AppColors.secondaryNeon,
                            ),
                          ),
                        ],
                      ),
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
                        _copyRoomCode(context);
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
                      // Left: Change / Select Media button (or Host Only indicator if !canControl)
                      if (canControl)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.surfaceElevated,
                            foregroundColor: AppColors.secondaryNeon,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
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
                        )
                      else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.accentYellow
                                  .withValues(alpha: 0.3),
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

                      // Controls: Screen Share, Share Room, Settings
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (screenShareController != null) ...[
                            _buildScreenShareButton(
                                context, screenShareController!),
                            const SizedBox(width: 4),
                          ],

                          // Polished Share Room Button
                          Tooltip(
                            message:
                                'Bagikan Room (${roomController.currentRoom.code})',
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: AppColors.surfaceElevated,
                                foregroundColor: AppColors.secondaryNeon,
                                side: const BorderSide(
                                    color: AppColors.border),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () => _showShareModal(context),
                              onLongPress: () => _copyRoomCode(context),
                              icon: const Icon(Icons.share_rounded, size: 15),
                              label: const Text(
                                'Bagikan',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),

                          // Host Settings: Switch between Host-Only and Collaborative
                          if (isHost) ...[
                            const SizedBox(width: 4),
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: PopupMenuButton<String>(
                                icon: const Icon(
                                  Icons.settings_outlined,
                                  size: 16,
                                  color: AppColors.textSecondary,
                                ),
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(
                                    minWidth: 32, minHeight: 32),
                                tooltip: 'Pengaturan Kontrol',
                                color: AppColors.surfaceElevated,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side:
                                      const BorderSide(color: AppColors.border),
                                ),
                                onSelected: (mode) {
                                  roomController.setControlMode(mode);
                                },
                                itemBuilder: (context) => [
                                  CheckedPopupMenuItem(
                                    value: 'host_only',
                                    checked:
                                        roomController.currentRoom.isHostOnly,
                                    child: const Text('👑 Host Only'),
                                  ),
                                  CheckedPopupMenuItem(
                                    value: 'collaborative',
                                    checked: roomController
                                        .currentRoom.isCollaborative,
                                    child: const Text('🤝 Kolaboratif'),
                                  ),
                                ],
                              ),
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onPressed: () {
          AppHaptics.medium();
          controller.stopScreenShare();
        },
        icon: const Icon(Icons.stop_screen_share_rounded, size: 15),
        label: const Text(
          'Hentikan Layar',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );
    }

    if (controller.isScreenSharingActive) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surfaceElevated,
          foregroundColor: AppColors.secondaryNeon,
          side: const BorderSide(color: AppColors.secondaryNeon),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onPressed: () {
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
        icon: const Icon(Icons.personal_video_rounded, size: 15),
        label: Text(
          'Layar: ${controller.sharerName ?? "Aktif"}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );
    }

    final bool canShare = controller.canShareScreen;

    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.surfaceElevated,
        foregroundColor:
            canShare ? AppColors.textSecondary : AppColors.textMuted,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      onPressed: canShare
          ? () async {
              AppHaptics.medium();
              final success = await controller.startScreenShare();
              if (!success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.surfaceElevated,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: AppColors.accentRed),
                    ),
                    content: Text(
                      controller.errorMessage ??
                          'Tidak dapat memulai berbagi layar.',
                      style: const TextStyle(
                          color: AppColors.accentRed, fontSize: 12),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }
          : () {
              AppHaptics.selection();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.surfaceElevated,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: AppColors.accentYellow),
                  ),
                  content: const Row(
                    children: [
                      Icon(Icons.lock_rounded,
                          color: AppColors.accentYellow, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Hanya Host yang dapat membagikan layar pada mode Host Only.',
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
      icon: Icon(
        canShare ? Icons.screen_share_rounded : Icons.lock_outline_rounded,
        size: 15,
      ),
      label: const Text(
        'Bagi Layar',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

