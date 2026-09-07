import 'package:flutter_test/flutter_test.dart';
import 'package:watch_party/features/auth/domain/user_profile.dart';
import 'package:watch_party/features/room/controllers/room_controller.dart';
import 'package:watch_party/features/room/controllers/sync_controller.dart';
import 'package:watch_party/features/room/controllers/unified_player_controller.dart';
import 'package:watch_party/features/room/models/room_model.dart';

void main() {
  group('RoomController Unit Tests', () {
    final hostUser = const UserProfile(
      id: 'host-123',
      username: 'AliceHost',
      avatarUrl: '🦊',
      isGuest: false,
    );

    final participantUser = const UserProfile(
      id: 'guest-456',
      username: 'BobGuest',
      avatarUrl: '🐱',
      isGuest: true,
    );

    final testRoom = RoomModel(
      id: 'room-test-1',
      code: 'WP9999',
      title: 'Exciting Watch Party',
      hostId: 'host-123',
      hostName: 'AliceHost',
      isPublic: true,
      controlMode: 'host_only',
      currentMediaType: 'direct_url',
      currentMediaUrl: 'https://example.com/video.mp4',
      currentState: 'paused',
      currentPosition: 0.0,
      livekitRoomName: 'room_WP9999',
      participantCount: 1,
      createdAt: DateTime.now(),
    );

    test('isHost correctly identifies host vs participant', () {
      final hostController = RoomController(
        initialRoom: testRoom,
        currentUser: hostUser,
      );
      expect(hostController.isHost, isTrue);
      expect(hostController.currentUser.id, 'host-123');
      expect(hostController.isRoomClosed, isFalse);

      final participantController = RoomController(
        initialRoom: testRoom,
        currentUser: participantUser,
      );
      expect(participantController.isHost, isFalse);
      expect(participantController.currentUser.id, 'guest-456');
    });

    test('closeOrDeleteRoom marks room as closed for host', () async {
      final hostController = RoomController(
        initialRoom: testRoom,
        currentUser: hostUser,
      );

      expect(hostController.isRoomClosed, isFalse);

      await hostController.closeOrDeleteRoom();

      expect(hostController.isRoomClosed, isTrue);
      expect(hostController.state.isRoomClosed, isTrue);
      expect(hostController.state.closedReason, contains('ditutup'));
    });

    test('closeOrDeleteRoom does nothing for non-host', () async {
      final participantController = RoomController(
        initialRoom: testRoom,
        currentUser: participantUser,
      );

      await participantController.closeOrDeleteRoom();

      expect(participantController.isRoomClosed, isFalse);
      expect(participantController.state.isRoomClosed, isFalse);
    });

    test('setControlMode updates mode only if host', () async {
      final hostController = RoomController(
        initialRoom: testRoom,
        currentUser: hostUser,
      );
      await hostController.setControlMode('collaborative');
      expect(hostController.currentRoom.controlMode, 'collaborative');

      final guestController = RoomController(
        initialRoom: testRoom,
        currentUser: participantUser,
      );
      await guestController.setControlMode('collaborative');
      // Should not change because guest is not host, so remains 'host_only'
      expect(guestController.currentRoom.controlMode, 'host_only');
    });

    test('isHost fallback correctly recognizes host by hostName when hostId is null or differs', () {
      final roomWithNullHostId = testRoom.copyWith(
        hostId: null,
        hostName: 'AliceHost',
      );
      final controllerNullId = RoomController(
        initialRoom: roomWithNullHostId,
        currentUser: hostUser,
      );
      expect(controllerNullId.isHost, isTrue);

      final roomWithDiffHostId = testRoom.copyWith(
        hostId: 'other-id-999',
        hostName: 'AliceHost',
      );
      final controllerDiffId = RoomController(
        initialRoom: roomWithDiffHostId,
        currentUser: hostUser,
      );
      expect(controllerDiffId.isHost, isTrue);
    });

    test('Guest with username Host cannot hijack room when hostId is null and hostName is default Host', () {
      final defaultRoom = testRoom.copyWith(
        hostId: null,
        hostName: 'Host',
      );
      final guestNamedHost = const UserProfile(
        id: 'guest-impostor',
        username: 'Host',
        avatarUrl: '🐱',
        isGuest: true,
      );
      final controller = RoomController(
        initialRoom: defaultRoom,
        currentUser: guestNamedHost,
      );
      expect(controller.isHost, isFalse);
    });

    test('closeOrDeleteRoom handles non-UUID room IDs cleanly without throwing', () async {
      final nonUuidRoom = testRoom.copyWith(
        id: 'demo-room-non-uuid',
        code: 'WP9999',
      );
      final controller = RoomController(
        initialRoom: nonUuidRoom,
        currentUser: hostUser,
      );
      await controller.closeOrDeleteRoom();
      expect(controller.isRoomClosed, isTrue);
    });

    test('dispose cancels timers cleanly without errors', () {
      final guestController = RoomController(
        initialRoom: testRoom,
        currentUser: participantUser,
      );
      expect(() => guestController.dispose(), returnsNormally);
    });

    test('SyncController canControl allows host by hostId or hostName and blocks guest unless collaborative', () {
      final player = UnifiedPlayerController();

      // 1. Host by hostId
      final syncHostById = SyncController(
        room: testRoom,
        currentUser: hostUser,
        player: player,
      );
      expect(syncHostById.canControl, isTrue);

      // 2. Host by hostName when hostId is null
      final syncHostByName = SyncController(
        room: testRoom.copyWith(hostId: null, hostName: 'AliceHost'),
        currentUser: hostUser,
        player: player,
      );
      expect(syncHostByName.canControl, isTrue);

      // 3. Guest in host_only mode
      final syncGuest = SyncController(
        room: testRoom,
        currentUser: participantUser,
        player: player,
      );
      expect(syncGuest.canControl, isFalse);

      // 4. Guest in collaborative mode
      final syncCollaborative = SyncController(
        room: testRoom.copyWith(controlMode: 'collaborative'),
        currentUser: participantUser,
        player: player,
      );
      expect(syncCollaborative.canControl, isTrue);

      // 5. Impostor guest named 'Host' when hostName is default 'Host'
      final syncImpostor = SyncController(
        room: testRoom.copyWith(hostId: null, hostName: 'Host'),
        currentUser: const UserProfile(id: 'guest-imp', username: 'Host', isGuest: true),
        player: player,
      );
      expect(syncImpostor.canControl, isFalse);
    });

    test('promoteToHost transfers host role and updates room model and isHost flag', () async {
      final guestController = RoomController(
        initialRoom: testRoom,
        currentUser: participantUser,
      );
      expect(guestController.isHost, isFalse);

      String? notifiedHostId;
      String? notifiedHostName;
      guestController.onHostChanged = (id, name) {
        notifiedHostId = id;
        notifiedHostName = name;
      };

      await guestController.promoteToHost(participantUser);

      expect(guestController.isHost, isTrue);
      expect(guestController.currentRoom.hostId, participantUser.id);
      expect(guestController.currentRoom.hostName, participantUser.username);
      expect(notifiedHostId, participantUser.id);
      expect(notifiedHostName, participantUser.username);
    });

    test('transferHostAndLeave promotes new host without closing room', () async {
      final hostController = RoomController(
        initialRoom: testRoom,
        currentUser: hostUser,
      );
      expect(hostController.isHost, isTrue);
      expect(hostController.isRoomClosed, isFalse);

      await hostController.transferHostAndLeave(nextHost: participantUser);

      // Room remains open
      expect(hostController.isRoomClosed, isFalse);
      // Former host is no longer host
      expect(hostController.isHost, isFalse);
    });

    test('promoteToHost triggers onSystemNotice with departure and promotion info', () async {
      final guestController = RoomController(
        initialRoom: testRoom.copyWith(hostName: 'AliceOldHost'),
        currentUser: participantUser,
      );

      String? systemNotice;
      guestController.onSystemNotice = (msg) {
        systemNotice = msg;
      };

      await guestController.promoteToHost(participantUser);

      expect(systemNotice, contains('AliceOldHost (Host) keluar'));
      expect(systemNotice, contains(participantUser.username));
    });
  });
}
