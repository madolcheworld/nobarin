import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/room/controllers/room_controller.dart';
import 'package:nobarin/features/room/controllers/sync_controller.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/models/room_model.dart';

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

    group('Host Moderation & Co-Host Feature Tests', () {
      final coHostUser = const UserProfile(
        id: 'cohost-789',
        username: 'CharlieCoHost',
        avatarUrl: '⭐',
        isGuest: false,
      );

      final viewerUser = const UserProfile(
        id: 'viewer-999',
        username: 'DavidViewer',
        avatarUrl: '👤',
        isGuest: true,
      );

      test('canModerateUser enforces hierarchy (Host > CoHost > Viewer)', () {
        final hostController = RoomController(
          initialRoom: testRoom,
          currentUser: hostUser,
        );
        // Host can moderate co-host and viewer, but cannot moderate themselves
        expect(hostController.canModerateUser(hostUser.id), isFalse);
        expect(hostController.canModerateUser(coHostUser.id), isTrue);
        expect(hostController.canModerateUser(viewerUser.id), isTrue);

        final coHostController = RoomController(
          initialRoom: testRoom,
          currentUser: coHostUser,
        );
        // Promote coHostUser to co-host locally
        coHostController.handleCoHostUpdated({
          'target_user_id': coHostUser.id,
          'is_co_host': true,
        });
        expect(coHostController.isCurrentUserCoHost, isTrue);

        // Co-Host can moderate viewers
        expect(coHostController.canModerateUser(viewerUser.id), isTrue);
        // Co-Host cannot moderate host
        expect(coHostController.canModerateUser(hostUser.id), isFalse);
        // Co-Host cannot moderate themselves or another co-host
        expect(coHostController.canModerateUser(coHostUser.id), isFalse);
        coHostController.handleCoHostUpdated({
          'target_user_id': 'other-cohost',
          'is_co_host': true,
        });
        expect(coHostController.canModerateUser('other-cohost'), isFalse);

        final viewerController = RoomController(
          initialRoom: testRoom,
          currentUser: viewerUser,
        );
        // Viewer cannot moderate anyone
        expect(viewerController.canModerateUser(hostUser.id), isFalse);
        expect(viewerController.canModerateUser(coHostUser.id), isFalse);
        expect(viewerController.canModerateUser(viewerUser.id), isFalse);
        expect(viewerController.canModerateUser('anyone'), isFalse);
      });

      test('toggleCoHost adds and removes co-host role for host only', () async {
        final hostController = RoomController(
          initialRoom: testRoom,
          currentUser: hostUser,
        );

        expect(hostController.isCoHost(participantUser.id), isFalse);

        await hostController.toggleCoHost(participantUser);
        expect(hostController.isCoHost(participantUser.id), isTrue);
        expect(hostController.coHostUserIds.contains(participantUser.id), isTrue);

        await hostController.toggleCoHost(participantUser);
        expect(hostController.isCoHost(participantUser.id), isFalse);
        expect(hostController.coHostUserIds.contains(participantUser.id), isFalse);

        // Viewer cannot toggle co-host
        final viewerController = RoomController(
          initialRoom: testRoom,
          currentUser: viewerUser,
        );
        await viewerController.toggleCoHost(participantUser);
        expect(viewerController.isCoHost(participantUser.id), isFalse);
      });

      test('canControlMedia permits Host and Co-Host in host_only mode, but blocks Viewers', () {
        final hostController = RoomController(
          initialRoom: testRoom.copyWith(controlMode: 'host_only'),
          currentUser: hostUser,
        );
        expect(hostController.canControlMedia, isTrue);

        final coHostController = RoomController(
          initialRoom: testRoom.copyWith(controlMode: 'host_only'),
          currentUser: coHostUser,
        );
        expect(coHostController.canControlMedia, isFalse);
        coHostController.handleCoHostUpdated({
          'target_user_id': coHostUser.id,
          'is_co_host': true,
        });
        expect(coHostController.canControlMedia, isTrue);

        final viewerController = RoomController(
          initialRoom: testRoom.copyWith(controlMode: 'host_only'),
          currentUser: viewerUser,
        );
        expect(viewerController.canControlMedia, isFalse);

        // In collaborative mode, everyone can control
        final viewerCollabController = RoomController(
          initialRoom: testRoom.copyWith(controlMode: 'collaborative'),
          currentUser: viewerUser,
        );
        expect(viewerCollabController.canControlMedia, isTrue);
      });

      test('handleKickParticipant marks room closed and invokes onKicked if target is current user', () {
        final participantController = RoomController(
          initialRoom: testRoom,
          currentUser: participantUser,
        );

        String? kickedReason;
        participantController.onKicked = (reason) {
          kickedReason = reason;
        };

        participantController.handleKickParticipant({
          'target_user_id': participantUser.id,
          'reason': 'Spamming media',
        });

        expect(participantController.isRoomClosed, isTrue);
        expect(kickedReason, 'Spamming media');
      });

      test('handleKickParticipant removes participant and records kicked ID for other participants', () {
        final hostController = RoomController(
          initialRoom: testRoom,
          currentUser: hostUser,
        );

        String? noticeReceived;
        hostController.onModerationNotice = (notice) {
          noticeReceived = notice;
        };

        hostController.handleKickParticipant({
          'target_user_id': viewerUser.id,
          'target_username': viewerUser.username,
        });

        expect(hostController.kickedUserIds.contains(viewerUser.id), isTrue);
        expect(noticeReceived, contains(viewerUser.username));
      });

      test('handleForceMuteParticipant triggers callback on target and notice on others', () {
        final targetController = RoomController(
          initialRoom: testRoom,
          currentUser: viewerUser,
        );

        bool muteReceived = false;
        targetController.onForceMuteReceived = () {
          muteReceived = true;
        };

        targetController.handleForceMuteParticipant({
          'target_user_id': viewerUser.id,
          'target_username': viewerUser.username,
        });

        expect(muteReceived, isTrue);

        final otherController = RoomController(
          initialRoom: testRoom,
          currentUser: hostUser,
        );

        String? otherNotice;
        otherController.onModerationNotice = (notice) {
          otherNotice = notice;
        };

        otherController.handleForceMuteParticipant({
          'target_user_id': viewerUser.id,
          'target_username': viewerUser.username,
        });

        expect(otherNotice, contains('Mikrofon ${viewerUser.username} telah dimatikan'));
      });

      test('handleCoHostUpdated adds and removes co-hosts and triggers notices', () {
        final controller = RoomController(
          initialRoom: testRoom,
          currentUser: hostUser,
        );

        String? noticeReceived;
        controller.onModerationNotice = (notice) {
          noticeReceived = notice;
        };

        // Promotion
        controller.handleCoHostUpdated({
          'target_user_id': coHostUser.id,
          'target_username': coHostUser.username,
          'is_co_host': true,
        });
        expect(controller.isCoHost(coHostUser.id), isTrue);
        expect(noticeReceived, contains('Co-Host'));

        // Demotion
        controller.handleCoHostUpdated({
          'target_user_id': coHostUser.id,
          'target_username': coHostUser.username,
          'is_co_host': false,
        });
        expect(controller.isCoHost(coHostUser.id), isFalse);
        expect(noticeReceived, contains('tidak lagi menjadi Co-Host'));
      });

      test('SyncController allows Co-Host to control media via canControlProvider in host_only mode', () {
        final player = UnifiedPlayerController();

        bool isCoHost = false;
        final syncController = SyncController(
          room: testRoom.copyWith(controlMode: 'host_only'),
          currentUser: participantUser,
          player: player,
          canControlProvider: () => isCoHost,
        );

        // Initially participant is not co-host
        expect(syncController.canControl, isFalse);

        // User becomes Co-Host
        isCoHost = true;
        expect(syncController.canControl, isTrue);

        syncController.dispose();
        player.dispose();
      });

      test('promoteToHost updates state and notifies callbacks', () async {
        final controller = RoomController(
          initialRoom: testRoom,
          currentUser: hostUser,
        );

        String? changedHostId;
        String? changedHostName;
        controller.onHostChanged = (id, name) {
          changedHostId = id;
          changedHostName = name;
        };

        await controller.promoteToHost(participantUser);

        expect(controller.state.room.hostId, participantUser.id);
        expect(controller.state.room.hostName, participantUser.username);
        expect(changedHostId, participantUser.id);
        expect(changedHostName, participantUser.username);

        controller.dispose();
      });
    });
  });
}
