import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../auth/domain/user_profile.dart';
import '../../../chat/controllers/chat_controller.dart';
import '../../../voice/controllers/webrtc_voice_controller.dart';
import '../../../voice/presentation/speaking_avatar_indicator.dart';
import '../../controllers/room_controller.dart';
import 'participant_moderation_sheet.dart';

class ParticipantsTabView extends StatelessWidget {
  final List<UserProfile> participants;
  final String? hostId;
  final String? hostName;
  final String roomCode;
  final String roomTitle;
  final bool isHostOnly;
  final Set<String> speakingUserIds;
  final Set<String> mutedUserIds;
  final Set<String> coHostUserIds;
  final RoomController? roomController;
  final ChatController? chatController;
  final WebRtcVoiceController? voiceController;

  const ParticipantsTabView({
    super.key,
    required this.participants,
    this.hostId,
    this.hostName,
    required this.roomCode,
    required this.roomTitle,
    this.isHostOnly = false,
    this.speakingUserIds = const {},
    this.mutedUserIds = const {},
    this.coHostUserIds = const {},
    this.roomController,
    this.chatController,
    this.voiceController,
  });

  @override
  Widget build(BuildContext context) {
    final currentUserId = roomController?.currentUser.id;
    final currentUsername = roomController?.currentUser.username;

    // Sort participants: current user first, then host, then co-hosts, then alphabetical
    final sortedList = List<UserProfile>.from(participants);
    sortedList.sort((a, b) {
      final aIsMe = (currentUserId != null && a.id == currentUserId) ||
          (currentUsername != null && a.username == currentUsername);
      final bIsMe = (currentUserId != null && b.id == currentUserId) ||
          (currentUsername != null && b.username == currentUsername);
      if (aIsMe) return -1;
      if (bIsMe) return 1;

      final aIsHost = (hostId != null && a.id == hostId) ||
          (hostName != null && a.username == hostName);
      final bIsHost = (hostId != null && b.id == hostId) ||
          (hostName != null && b.username == hostName);
      if (aIsHost) return -1;
      if (bIsHost) return 1;

      final aIsCoHost = coHostUserIds.contains(a.id) ||
          coHostUserIds.contains(a.username);
      final bIsCoHost = coHostUserIds.contains(b.id) ||
          coHostUserIds.contains(b.username);
      if (aIsCoHost && !bIsCoHost) return -1;
      if (!aIsCoHost && bIsCoHost) return 1;

      return a.username.toLowerCase().compareTo(b.username.toLowerCase());
    });

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        // Voice VoIP Status Banner if available
        if (voiceController != null)
          ListenableBuilder(
            listenable: voiceController!,
            builder: (context, _) {
              final status = voiceController!.status;
              final isSpeaking = voiceController!.isLocalSpeaking;
              final activeSpeakerCount = voiceController!.activeSpeakerIds.length +
                  (isSpeaking ? 1 : 0);

              Color dotColor = AppColors.accentGreen;
              String statusTitle = 'Voice Chat Terhubung';
              if (status == VoiceStatus.connecting) {
                dotColor = AppColors.accentYellow;
                statusTitle = 'Menghubungkan ke Voice...';
              } else if (status == VoiceStatus.error) {
                dotColor = AppColors.accentRed;
                statusTitle = 'Koneksi Voice Gagal';
              } else if (status == VoiceStatus.disconnected) {
                dotColor = AppColors.textMuted;
                statusTitle = 'Voice Chat Nonaktif';
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: dotColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: dotColor.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                        boxShadow: [
                          BoxShadow(
                            color: dotColor.withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusTitle,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: dotColor,
                            ),
                          ),
                          if (status == VoiceStatus.connected)
                            Text(
                              activeSpeakerCount > 0
                                  ? '$activeSpeakerCount peserta sedang berbicara'
                                  : 'Hening (tidak ada yang berbicara)',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (status == VoiceStatus.error)
                      TextButton.icon(
                        onPressed: () {
                          AppHaptics.selection();
                          voiceController!.reconnect();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 14),
                        label: const Text('Coba Lagi', style: TextStyle(fontSize: 11)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.accentRed,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

        // Section Title
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              const Icon(Icons.people_alt_rounded,
                  size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                'PESERTA AKTIF (${participants.length})',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),

        // Participants List Items
        ...sortedList.map((user) {
          final isMe = (currentUserId != null && user.id == currentUserId) ||
              (currentUsername != null && user.username == currentUsername);
          final isHost = (hostId != null && hostId!.isNotEmpty && user.id == hostId) ||
              (hostName != null &&
                  hostName!.isNotEmpty &&
                  hostName != 'Host' &&
                  user.username == hostName);
          final isCoHost = coHostUserIds.contains(user.id) ||
              coHostUserIds.contains(user.username);
          final isSpeaking = speakingUserIds.contains(user.id);
          final isMuted = mutedUserIds.contains(user.id);

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: isMe
                  ? AppColors.primaryNeon.withValues(alpha: 0.06)
                  : AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isMe
                    ? AppColors.primaryNeon.withValues(alpha: 0.3)
                    : AppColors.borderLight,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              leading: SpeakingAvatarIndicator(
                avatar: user.avatarUrl,
                name: user.username,
                isSpeaking: isSpeaking,
                isMuted: isMuted,
                isHost: isHost,
                isCoHost: isCoHost,
                showName: false,
                size: 38,
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      user.username,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isMe ? FontWeight.bold : FontWeight.w600,
                        color: isMe
                            ? AppColors.primaryNeon
                            : AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.primaryNeon.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Kamu',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryNeon,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Row(
                children: [
                  if (isHost)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.accentYellow.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.accentYellow.withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('👑', style: TextStyle(fontSize: 10)),
                          SizedBox(width: 3),
                          Text(
                            'Host',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.accentYellow,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isCoHost)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.secondaryNeon.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.secondaryNeon.withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('⭐', style: TextStyle(fontSize: 10)),
                          SizedBox(width: 3),
                          Text(
                            'Co-Host',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.secondaryNeon,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const Text(
                      'Peserta',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Audio status badge
                  Icon(
                    isMuted
                        ? Icons.mic_off_rounded
                        : (isSpeaking
                            ? Icons.graphic_eq_rounded
                            : Icons.mic_none_rounded),
                    size: 17,
                    color: isMuted
                        ? AppColors.textMuted
                        : (isSpeaking
                            ? AppColors.accentGreen
                            : AppColors.textSecondary),
                  ),

                  // Moderation button
                  if (roomController != null && (!isMe || roomController!.isHost))
                    IconButton(
                      icon: const Icon(Icons.more_vert_rounded, size: 18),
                      color: AppColors.textSecondary,
                      onPressed: () {
                        AppHaptics.selection();
                        ParticipantModerationSheet.show(
                          context,
                          targetUser: user,
                          roomController: roomController!,
                          chatController: chatController,
                          isSpeaking: isSpeaking,
                          isMuted: isMuted,
                        );
                      },
                    ),
                ],
              ),
              onTap: roomController != null
                  ? () {
                      AppHaptics.light();
                      ParticipantModerationSheet.show(
                        context,
                        targetUser: user,
                        roomController: roomController!,
                        chatController: chatController,
                        isSpeaking: isSpeaking,
                        isMuted: isMuted,
                      );
                    }
                  : null,
              ),
            ),
          );
        }),
      ],
    );
  }
}
