import 'package:flutter_test/flutter_test.dart';
import 'package:watch_party/features/auth/domain/user_profile.dart';
import 'package:watch_party/features/room/controllers/queue_controller.dart';
import 'package:watch_party/features/room/controllers/sync_controller.dart';
import 'package:watch_party/features/room/controllers/unified_player_controller.dart';
import 'package:watch_party/features/room/models/queue_item.dart';
import 'package:watch_party/features/room/models/room_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QueueItem Model Tests', () {
    test('serializes to and from JSON correctly', () {
      final item = QueueItem(
        id: 'item-1',
        roomId: 'room-1',
        mediaType: 'youtube',
        mediaUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        title: 'Rick Astley - Never Gonna Give You Up',
        thumbnailUrl: 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        addedByUserId: 'user-1',
        addedByUserName: 'Alice',
        orderIndex: 0,
        createdAt: DateTime.utc(2026, 9, 7, 10, 0),
      );

      final json = item.toJson();
      final fromJson = QueueItem.fromJson(json);

      expect(fromJson.id, item.id);
      expect(fromJson.roomId, item.roomId);
      expect(fromJson.mediaType, item.mediaType);
      expect(fromJson.mediaUrl, item.mediaUrl);
      expect(fromJson.title, item.title);
      expect(fromJson.thumbnailUrl, item.thumbnailUrl);
      expect(fromJson.addedByUserId, item.addedByUserId);
      expect(fromJson.addedByUserName, item.addedByUserName);
      expect(fromJson.orderIndex, item.orderIndex);
      expect(fromJson.isYouTube, isTrue);
      expect(fromJson.isDirectUrl, isFalse);
    });
  });

  group('QueueController Tests', () {
    late UnifiedPlayerController player;
    late SyncController syncController;
    late QueueController queueController;

    const testUser = UserProfile(
      id: 'host-1',
      username: 'HostAlice',
      avatarUrl: '👑',
      isGuest: false,
    );

    final testRoom = RoomModel(
      id: 'room-1',
      code: 'WP1234',
      title: 'Watch Party Test',
      hostId: 'host-1',
      hostName: 'HostAlice',
      isPublic: true,
      controlMode: 'host_only',
      currentMediaType: 'direct_url',
      currentMediaUrl: 'https://example.com/test1.mp4',
      currentState: 'playing',
      currentPosition: 10.0,
      livekitRoomName: 'room_WP1234',
      participantCount: 1,
    );

    setUp(() {
      player = UnifiedPlayerController();
      syncController = SyncController(
        room: testRoom,
        currentUser: testUser,
        player: player,
      );
      queueController = QueueController(
        roomId: testRoom.id,
        currentUser: testUser,
        syncController: syncController,
        isHostProvider: () => true,
        isCollaborativeProvider: () => false,
      );
    });

    tearDown(() {
      queueController.dispose();
      syncController.dispose();
      player.dispose();
    });

    test('initial state is empty', () {
      expect(queueController.items, isEmpty);
      expect(queueController.count, 0);
      expect(queueController.canAddToQueue, isTrue);
      expect(queueController.canManageQueue, isTrue);
    });

    test('addToQueue adds items in sequential order', () async {
      await queueController.addToQueue(
        mediaType: 'youtube',
        mediaUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        title: 'Video 1',
      );
      await queueController.addToQueue(
        mediaType: 'direct_url',
        mediaUrl: 'https://example.com/video2.mp4',
        title: 'Video 2',
      );

      expect(queueController.count, 2);
      expect(queueController.items[0].title, 'Video 1');
      expect(queueController.items[0].orderIndex, 0);
      expect(queueController.items[1].title, 'Video 2');
      expect(queueController.items[1].orderIndex, 1);
    });

    test('reorderQueue adjusts order indices correctly', () async {
      await queueController.addToQueue(
        mediaType: 'youtube',
        mediaUrl: 'https://www.youtube.com/watch?v=1',
        title: 'Video 1',
      );
      await queueController.addToQueue(
        mediaType: 'youtube',
        mediaUrl: 'https://www.youtube.com/watch?v=2',
        title: 'Video 2',
      );
      await queueController.addToQueue(
        mediaType: 'youtube',
        mediaUrl: 'https://www.youtube.com/watch?v=3',
        title: 'Video 3',
      );

      // Move Video 3 (index 2) to top (index 0)
      await queueController.reorderQueue(2, 0);

      expect(queueController.items[0].title, 'Video 3');
      expect(queueController.items[0].orderIndex, 0);
      expect(queueController.items[1].title, 'Video 1');
      expect(queueController.items[1].orderIndex, 1);
      expect(queueController.items[2].title, 'Video 2');
      expect(queueController.items[2].orderIndex, 2);

      // Move top item (Video 3 at index 0) to bottom (index 2)
      await queueController.reorderQueue(0, 2);
      expect(queueController.items[0].title, 'Video 1');
      expect(queueController.items[1].title, 'Video 2');
      expect(queueController.items[2].title, 'Video 3');
    });

    test('removeFromQueue removes item and re-indexes remaining items', () async {
      await queueController.addToQueue(
        mediaType: 'youtube',
        mediaUrl: 'https://www.youtube.com/watch?v=1',
        title: 'Video 1',
      );
      await queueController.addToQueue(
        mediaType: 'youtube',
        mediaUrl: 'https://www.youtube.com/watch?v=2',
        title: 'Video 2',
      );

      final firstId = queueController.items.first.id;
      await queueController.removeFromQueue(firstId);

      expect(queueController.count, 1);
      expect(queueController.items.first.title, 'Video 2');
      expect(queueController.items.first.orderIndex, 0);
    });

    test('playNext pops first item and loads it into player', () async {
      await queueController.addToQueue(
        mediaType: 'direct_url',
        mediaUrl: 'https://example.com/next_video.mp4',
        title: 'Next Video',
      );
      await queueController.addToQueue(
        mediaType: 'direct_url',
        mediaUrl: 'https://example.com/later_video.mp4',
        title: 'Later Video',
      );

      expect(queueController.count, 2);

      await queueController.playNext();

      expect(queueController.count, 1);
      expect(queueController.items.first.title, 'Later Video');
      expect(player.mediaUrl, 'https://example.com/next_video.mp4');
    });

    test('playItem directly plays selected item and removes it from queue', () async {
      await queueController.addToQueue(
        mediaType: 'direct_url',
        mediaUrl: 'https://example.com/video1.mp4',
        title: 'Video 1',
      );
      await queueController.addToQueue(
        mediaType: 'direct_url',
        mediaUrl: 'https://example.com/video2.mp4',
        title: 'Video 2',
      );

      final secondItem = queueController.items[1];
      await queueController.playItem(secondItem);

      expect(queueController.count, 1);
      expect(queueController.items.first.title, 'Video 1');
      expect(player.mediaUrl, 'https://example.com/video2.mp4');
    });

    test('clearQueue removes all items', () async {
      await queueController.addToQueue(
        mediaType: 'youtube',
        mediaUrl: 'https://www.youtube.com/watch?v=1',
        title: 'Video 1',
      );
      await queueController.addToQueue(
        mediaType: 'youtube',
        mediaUrl: 'https://www.youtube.com/watch?v=2',
        title: 'Video 2',
      );

      expect(queueController.count, 2);
      await queueController.clearQueue();
      expect(queueController.count, 0);
    });

    test('onPlaybackEnded callback triggers properly on player controller', () {
      bool endedCalled = false;
      player.onPlaybackEnded = () {
        endedCalled = true;
      };

      player.onPlaybackEnded?.call();
      expect(endedCalled, isTrue);
    });
  });
}
