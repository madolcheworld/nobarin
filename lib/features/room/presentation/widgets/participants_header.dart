import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../auth/domain/user_profile.dart';
import '../../../voice/presentation/speaking_avatar_indicator.dart';

class ParticipantsHeader extends StatelessWidget {
  final List<UserProfile> participants;
  final String? hostId;
  final String? hostName;
  final Set<String> speakingUserIds;
  final Set<String> mutedUserIds;

  const ParticipantsHeader({
    super.key,
    required this.participants,
    this.hostId,
    this.hostName,
    this.speakingUserIds = const {},
    this.mutedUserIds = const {},
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
                final isSpeaking = speakingUserIds.contains(user.id);
                final isMuted = mutedUserIds.contains(user.id);

                return Tooltip(
                  message:
                      '${user.username}${isHost ? ' (Host)' : ''}${isMuted ? ' (Muted)' : ''}',
                  child: SpeakingAvatarIndicator(
                    avatar: user.avatarUrl,
                    name: user.username,
                    isSpeaking: isSpeaking,
                    isMuted: isMuted,
                    isHost: isHost,
                    showName: false,
                    size: 34,
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
