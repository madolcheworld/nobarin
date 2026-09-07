import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../auth/domain/user_profile.dart';
import '../../../chat/controllers/chat_controller.dart';
import '../../controllers/room_controller.dart';
import '../../../voice/presentation/speaking_avatar_indicator.dart';
import 'participant_moderation_sheet.dart';

class ParticipantsHeader extends StatelessWidget {
  final List<UserProfile> participants;
  final String? hostId;
  final String? hostName;
  final Set<String> speakingUserIds;
  final Set<String> mutedUserIds;
  final Set<String> coHostUserIds;
  final RoomController? roomController;
  final ChatController? chatController;

  const ParticipantsHeader({
    super.key,
    required this.participants,
    this.hostId,
    this.hostName,
    this.speakingUserIds = const {},
    this.mutedUserIds = const {},
    this.coHostUserIds = const {},
    this.roomController,
    this.chatController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          // Viewers label
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.people_alt_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Peserta (${participants.length})',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(width: 10),

          // Avatars list
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: participants.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final user = participants[index];
                final isHost = (hostId != null && hostId!.isNotEmpty && user.id == hostId) ||
                    (hostName != null &&
                        hostName!.isNotEmpty &&
                        hostName != 'Host' &&
                        user.username == hostName);
                final isCoHost = coHostUserIds.contains(user.id) ||
                    coHostUserIds.contains(user.username);
                final isSpeaking = speakingUserIds.contains(user.id);
                final isMuted = mutedUserIds.contains(user.id);

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: roomController != null
                        ? () {
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
                    child: Tooltip(
                      message:
                          '${user.username}${isHost ? ' (Host)' : (isCoHost ? ' (Co-Host)' : '')}${isMuted ? ' (Muted)' : ''}',
                      child: SpeakingAvatarIndicator(
                        avatar: user.avatarUrl,
                        name: user.username,
                        isSpeaking: isSpeaking,
                        isMuted: isMuted,
                        isHost: isHost,
                        isCoHost: isCoHost,
                        showName: false,
                        size: 34,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
