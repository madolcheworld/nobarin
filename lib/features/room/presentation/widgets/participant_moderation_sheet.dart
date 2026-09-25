import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../auth/domain/user_profile.dart';
import '../../../chat/controllers/chat_controller.dart';
import '../../controllers/room_controller.dart';
import '../../../../features/voice/presentation/speaking_avatar_indicator.dart';

/// Bottom sheet dialog for inspecting participant details and performing
/// moderation actions (Kick, Remote Mute, Co-Host promotion/demotion, Transfer Host).
class ParticipantModerationSheet extends StatelessWidget {
  final UserProfile targetUser;
  final RoomController roomController;
  final ChatController? chatController;
  final bool isSpeaking;
  final bool isMuted;

  const ParticipantModerationSheet({
    super.key,
    required this.targetUser,
    required this.roomController,
    this.chatController,
    this.isSpeaking = false,
    this.isMuted = false,
  });

  static Future<void> show(
    BuildContext context, {
    required UserProfile targetUser,
    required RoomController roomController,
    ChatController? chatController,
    bool isSpeaking = false,
    bool isMuted = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ParticipantModerationSheet(
        targetUser: targetUser,
        roomController: roomController,
        chatController: chatController,
        isSpeaking: isSpeaking,
        isMuted: isMuted,
      ),
    );
  }

  static void _showProcessingDialog(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primaryNeon,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = roomController.currentUser;
    final isSelf = targetUser.id == currentUser.id ||
        targetUser.username == currentUser.username;
    final isTargetHost = roomController.isUserHost(targetUser.id) ||
        (roomController.currentRoom.hostName != null &&
            roomController.currentRoom.hostName != 'Host' &&
            roomController.currentRoom.hostName == targetUser.username);
    final isTargetCoHost = roomController.isCoHost(targetUser.id);
    final isCurrentHost = roomController.isHost;
    final canModerate = roomController.canModerateUser(targetUser.id) ||
        roomController.canModerateUser(targetUser.username);

    return Material(
      color: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: AppColors.border, width: 1.5),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: AppColors.textMuted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // User info header
          Row(
            children: [
              SpeakingAvatarIndicator(
                avatar: targetUser.avatarUrl,
                name: targetUser.username,
                isSpeaking: isSpeaking,
                isMuted: isMuted,
                isHost: isTargetHost,
                isCoHost: isTargetCoHost,
                showName: false,
                size: 52,
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
                            targetUser.username,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSelf) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryNeon.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Kamu',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryNeon,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Role badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isTargetHost
                                ? AppColors.accentYellow.withValues(alpha: 0.2)
                                : (isTargetCoHost
                                    ? AppColors.secondaryNeon.withValues(alpha: 0.2)
                                    : AppColors.surfaceHighlight),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isTargetHost
                                  ? AppColors.accentYellow
                                  : (isTargetCoHost
                                      ? AppColors.secondaryNeon
                                      : AppColors.border),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            isTargetHost
                                ? '👑 Host'
                                : (isTargetCoHost ? '⭐ Co-Host' : '👤 Peserta'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isTargetHost
                                  ? AppColors.accentYellow
                                  : (isTargetCoHost
                                      ? AppColors.secondaryNeon
                                      : AppColors.textSecondary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Mic status
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isMuted
                                  ? Icons.mic_off_rounded
                                  : Icons.mic_rounded,
                              size: 13,
                              color: isMuted
                                  ? AppColors.accentRed
                                  : AppColors.accentGreen,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isMuted ? 'Mic Mati' : 'Mic Aktif',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isMuted
                                    ? AppColors.accentRed
                                    : AppColors.accentGreen,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),

          // Actions list
          if (isSelf)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Ini adalah profil kamu di room ini.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            )
          else if (!canModerate)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Hanya Host atau Co-Host yang dapat mengelola peserta.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            )
          else ...[
            // Mute participant microphone
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.mic_off_rounded,
                  color: AppColors.accentYellow,
                  size: 20,
                ),
              ),
              title: const Text(
                'Matikan Mikrofon',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await roomController.forceMuteParticipant(
                  targetUser,
                  chatController: chatController,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Mikrofon ${targetUser.username} telah dimatikan.'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),

            // Promote or Demote Co-Host (Host only)
            if (isCurrentHost)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHighlight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isTargetCoHost
                        ? Icons.star_border_rounded
                        : Icons.star_rounded,
                    color: AppColors.secondaryNeon,
                    size: 20,
                  ),
                ),
                title: Text(
                  isTargetCoHost ? 'Cabut Peran Co-Host' : 'Jadikan Co-Host',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await roomController.toggleCoHost(
                    targetUser,
                    chatController: chatController,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isTargetCoHost
                              ? '${targetUser.username} bukan lagi Co-Host.'
                              : '${targetUser.username} sekarang menjadi Co-Host! ⭐',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),

            // Transfer Host Ownership (Host only)
            if (isCurrentHost)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHighlight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.amberAccent,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Alihkan Peran Host',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Alihkan Peran Host?'),
                      content: Text(
                        'Apakah kamu yakin ingin menyerahkan kepemilikan Host room ini kepada ${targetUser.username}?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Batal'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryNeon,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Ya, Alihkan'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true && context.mounted) {
                    Navigator.of(context).pop();
                    _showProcessingDialog(context, 'Mengalihkan Host...');
                    try {
                      await roomController.promoteToHost(
                        targetUser,
                        chatController: chatController,
                      );
                    } finally {
                      if (context.mounted) {
                        Navigator.of(context, rootNavigator: true).pop();
                      }
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '👑 Peran Host dialihkan ke ${targetUser.username}.',
                          ),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  }
                },
              ),

            // Kick Participant
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accentRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.person_remove_rounded,
                  color: AppColors.accentRed,
                  size: 20,
                ),
              ),
              title: const Text(
                'Keluarkan dari Room',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.accentRed,
                ),
              ),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Keluarkan Peserta?'),
                    content: Text(
                      'Yakin ingin mengeluarkan ${targetUser.username} dari room?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Batal'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentRed,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Keluarkan'),
                      ),
                    ],
                  ),
                );

                if (confirm == true && context.mounted) {
                  Navigator.of(context).pop();
                  _showProcessingDialog(
                    context,
                    'Mengeluarkan ${targetUser.username}...',
                  );
                  try {
                    await roomController.kickParticipant(
                      targetUser,
                      chatController: chatController,
                    );
                  } finally {
                    if (context.mounted) {
                      Navigator.of(context, rootNavigator: true).pop();
                    }
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '🚫 ${targetUser.username} telah dikeluarkan dari room.',
                        ),
                        backgroundColor: AppColors.accentRed,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ],
      ),
    ),
  ),
);
  }
}
