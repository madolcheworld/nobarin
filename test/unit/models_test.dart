import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/chat/models/chat_message.dart';
import 'package:nobarin/features/room/models/room_model.dart';

void main() {
  group('Domain Models Tests', () {
    test('UserProfile serialization and equality', () {
      const profile = UserProfile(
        id: 'u1',
        username: 'Alex',
        avatarUrl: '🚀',
        isGuest: true,
      );

      final json = profile.toJson();
      expect(json['id'], 'u1');
      expect(json['username'], 'Alex');
      expect(json['avatar_url'], '🚀');
      expect(json['is_guest'], true);

      final reconstructed = UserProfile.fromJson(json);
      expect(reconstructed, profile);
    });

    test('RoomModel JSON mapping and control getters', () {
      final now = DateTime.now();
      final room = RoomModel(
        id: 'r1',
        code: 'WP7890',
        title: 'Movie Night',
        hostId: 'u1',
        hostName: 'Alex',
        isPublic: true,
        controlMode: 'host_only',
        currentMediaType: 'youtube',
        currentMediaUrl: 'https://youtube.com/watch?v=abc',
        currentState: 'playing',
        currentPosition: 30.5,
        livekitRoomName: 'room_WP7890',
        participantCount: 5,
        createdAt: now,
      );

      expect(room.isHostOnly, isTrue);
      expect(room.isCollaborative, isFalse);
      expect(room.isPlaying, isTrue);

      final json = room.toJson();
      expect(json['host_name'], 'Alex');

      final reconstructed = RoomModel.fromJson(json);
      expect(reconstructed.id, 'r1');
      expect(reconstructed.code, 'WP7890');
      expect(reconstructed.title, 'Movie Night');
      expect(reconstructed.hostName, 'Alex');
      expect(reconstructed.isHostOnly, isTrue);
    });

    test('RoomModel parses host metadata from description when host_name is null', () {
      final json = {
        'id': 'r2',
        'code': 'WP5555',
        'title': 'Metadata Room',
        'description': '[HOST:name=QueenHost;id=host-queen-99] Nonton seru!',
        'host_id': null,
        'host_name': null,
        'is_public': true,
      };

      final room = RoomModel.fromJson(json);
      expect(room.hostName, 'QueenHost');
      expect(room.hostId, 'host-queen-99');
      expect(room.description, 'Nonton seru!');
    });

    test('ChatMessage type flags and mapping', () {
      final now = DateTime.now();
      final textMsg = ChatMessage(
        id: 'm1',
        roomId: 'r1',
        userId: 'u1',
        username: 'Alex',
        content: 'Halo kawan-kawan!',
        type: 'text',
        createdAt: now,
      );
      expect(textMsg.isText, isTrue);
      expect(textMsg.isSystem, isFalse);
      expect(textMsg.isReaction, isFalse);

      final rxMsg = ChatMessage(
        id: 'm2',
        roomId: 'r1',
        userId: 'u1',
        content: '🔥',
        type: 'emoji_reaction',
        createdAt: now,
      );
      expect(rxMsg.isReaction, isTrue);
      expect(rxMsg.isText, isFalse);

      final sysMsg = ChatMessage(
        id: 'm3',
        roomId: 'r1',
        content: 'Alex bergabung ke room',
        type: 'system',
        createdAt: now,
      );
      expect(sysMsg.isSystem, isTrue);
    });
  });
}
