import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/room/controllers/sync_controller.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/models/room_model.dart';
import 'package:nobarin/features/room/presentation/widgets/media_source_picker.dart';
import 'package:nobarin/features/screenshare/controllers/webrtc_screenshare_controller.dart';

class _FakeVideoRenderer implements RTCVideoRenderer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('MediaSourcePicker Widget Tests', () {
    late UnifiedPlayerController playerController;
    late SyncController syncController;

    final testHost = const UserProfile(
      id: 'host-101',
      username: 'RoomHost',
      avatarUrl: '👑',
      isGuest: false,
    );

    final baseRoom = RoomModel(
      id: 'room-picker-1',
      code: 'WP8888',
      title: 'Picker Test Room',
      hostId: 'host-101',
      hostName: 'RoomHost',
      isPublic: true,
      controlMode: 'host_only',
      currentMediaType: 'direct_url',
      currentMediaUrl: '',
      currentState: 'paused',
      currentPosition: 0.0,
      livekitRoomName: 'room_WP8888',
      participantCount: 1,
    );

    setUp(() {
      playerController = UnifiedPlayerController();
      syncController = SyncController(
        room: baseRoom,
        currentUser: testHost,
        player: playerController,
      );
    });

    tearDown(() {
      playerController.dispose();
      syncController.dispose();
    });

    testWidgets(
        'renders Mirror Layar / Bagikan Layar card when screenShareController is provided',
        (tester) async {
      final screenShare = WebRtcScreenShareController(
        roomId: baseRoom.id,
        userId: testHost.id,
        userName: testHost.username,
        rendererFactory: () => _FakeVideoRenderer(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaSourcePicker(
              syncController: syncController,
              screenShareController: screenShare,
              isAddingToQueueInitial: false,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Mirror Layar card must be visible in MediaSourcePicker
      expect(find.text('Mirror Layar / Bagikan Layar'), findsOneWidget);
      expect(
        find.text('Siarkan layar perangkat Anda secara langsung via WebRTC'),
        findsOneWidget,
      );

      screenShare.dispose();
    });

    testWidgets(
        'does NOT render Mirror Layar card when isAddingToQueueInitial is true',
        (tester) async {
      final screenShare = WebRtcScreenShareController(
        roomId: baseRoom.id,
        userId: testHost.id,
        userName: testHost.username,
        rendererFactory: () => _FakeVideoRenderer(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaSourcePicker(
              syncController: syncController,
              screenShareController: screenShare,
              isAddingToQueueInitial: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Mirror Layar should not be in queue picker
      expect(find.text('Mirror Layar / Bagikan Layar'), findsNothing);

      screenShare.dispose();
    });

    testWidgets(
        'does NOT render Mirror Layar card when screenShareController is null',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaSourcePicker(
              syncController: syncController,
              screenShareController: null,
              isAddingToQueueInitial: false,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Mirror Layar / Bagikan Layar'), findsNothing);
    });

    testWidgets(
        'does NOT render tempel link or URL fields when isAddingToQueueInitial is true',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaSourcePicker(
              syncController: syncController,
              isAddingToQueueInitial: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Video sources and header should be available in queue
      expect(find.text('Tambah ke Antrean'), findsOneWidget);
      expect(find.text('Cari di YouTube'), findsOneWidget);

      // Tempel link and its inputs/buttons must NOT be rendered in queue mode
      expect(find.text('atau tempel link'), findsNothing);
      expect(find.text('Link Video / Stream'), findsNothing);
      expect(find.text('Tempel tautan video di sini...'), findsNothing);
      expect(find.text('Putar Sekarang'), findsNothing);
    });

    testWidgets(
        'renders tempel link section and Putar Sekarang button when isAddingToQueueInitial is false',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaSourcePicker(
              syncController: syncController,
              isAddingToQueueInitial: false,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // In change source mode, tempel link is available for direct playback
      expect(find.text('Ganti Sumber Video'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('atau tempel link'), findsOneWidget);
      expect(find.text('Link Video / Stream'), findsOneWidget);
      expect(find.text('Putar Sekarang'), findsOneWidget);
      expect(find.text('Tambahkan ke Antrean Saja'), findsNothing);
    });
  });
}
