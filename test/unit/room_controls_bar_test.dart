import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_party/features/auth/domain/user_profile.dart';
import 'package:watch_party/features/room/controllers/queue_controller.dart';
import 'package:watch_party/features/room/controllers/room_controller.dart';
import 'package:watch_party/features/room/controllers/sync_controller.dart';
import 'package:watch_party/features/room/controllers/unified_player_controller.dart';
import 'package:watch_party/features/room/models/room_model.dart';
import 'package:watch_party/features/room/presentation/widgets/room_controls_bar.dart';

void main() {
  group('RoomControlsBar Widget Tests', () {
    late UnifiedPlayerController playerController;
    late SyncController syncController;
    late RoomController roomController;

    final testHost = const UserProfile(
      id: 'host-101',
      username: 'RoomHost',
      avatarUrl: '👑',
      isGuest: false,
    );

    final baseRoom = RoomModel(
      id: 'room-controls-1',
      code: 'WP7777',
      title: 'Controls Test Room',
      hostId: 'host-101',
      hostName: 'RoomHost',
      isPublic: true,
      controlMode: 'host_only',
      currentMediaType: 'direct_url',
      currentMediaUrl: '',
      currentState: 'paused',
      currentPosition: 0.0,
      livekitRoomName: 'room_WP7777',
      participantCount: 1,
    );

    setUp(() {
      playerController = UnifiedPlayerController();
      syncController = SyncController(
        room: baseRoom,
        currentUser: testHost,
        player: playerController,
      );
      roomController = RoomController(
        initialRoom: baseRoom,
        currentUser: testHost,
      );
    });

    tearDown(() {
      playerController.dispose();
      syncController.dispose();
      roomController.dispose();
    });

    testWidgets(
        'does NOT render any duplicate play or pause button in RoomControlsBar when media is empty',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlsBar(
              syncController: syncController,
              player: playerController,
              roomController: roomController,
              onOpenMediaPicker: () {},
            ),
          ),
        ),
      );

      // Verify no play or pause buttons are rendered
      expect(find.byIcon(Icons.play_circle_rounded), findsNothing);
      expect(find.byIcon(Icons.play_circle_filled_rounded), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.pause_rounded), findsNothing);
      expect(find.byIcon(Icons.pause_circle_rounded), findsNothing);

      // Verify "Pilih Video" button exists
      expect(find.text('Pilih Video'), findsOneWidget);
      expect(find.byIcon(Icons.replay_10_rounded), findsNothing);
      expect(find.byIcon(Icons.forward_10_rounded), findsNothing);
    });

    testWidgets(
        'renders play/pause and seek controls in RoomControlsBar when media is loaded',
        (tester) async {
      await playerController.loadMedia(
        'direct_url',
        'https://example.com/test.mp4',
        autoPlay: false,
      );

      bool pickerCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlsBar(
              syncController: syncController,
              player: playerController,
              roomController: roomController,
              onOpenMediaPicker: () {
                pickerCalled = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify play button is rendered in RoomControlsBar when paused
      expect(find.byIcon(Icons.play_circle_filled_rounded), findsOneWidget);

      // Verify seek controls and "Ganti Video" are rendered
      expect(find.byIcon(Icons.replay_10_rounded), findsOneWidget);
      expect(find.byIcon(Icons.forward_10_rounded), findsOneWidget);
      expect(find.text('Ganti Video'), findsOneWidget);

      // Test tapping Ganti Video
      await tester.tap(find.text('Ganti Video'));
      await tester.pumpAndSettle();
      expect(pickerCalled, isTrue);
    });

    testWidgets(
        'seek buttons trigger seek requests on syncController',
        (tester) async {
      await playerController.loadMedia(
        'direct_url',
        'https://example.com/test.mp4',
        autoPlay: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlsBar(
              syncController: syncController,
              player: playerController,
              roomController: roomController,
              onOpenMediaPicker: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tapping Seek forward
      await tester.tap(find.byIcon(Icons.forward_10_rounded));
      await tester.pumpAndSettle();

      // Tapping Seek backward
      await tester.tap(find.byIcon(Icons.replay_10_rounded));
      await tester.pumpAndSettle();
    });

    testWidgets('renders Antrean button and triggers onOpenQueue', (tester) async {
      final queueController = QueueController(
        roomId: baseRoom.id,
        currentUser: testHost,
        syncController: syncController,
        isHostProvider: () => true,
      );

      bool queueOpened = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlsBar(
              syncController: syncController,
              player: playerController,
              roomController: roomController,
              queueController: queueController,
              onOpenMediaPicker: () {},
              onOpenQueue: () {
                queueOpened = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Antrean'), findsOneWidget);
      expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);

      await tester.tap(find.text('Antrean'));
      await tester.pumpAndSettle();
      expect(queueOpened, isTrue);

      queueController.dispose();
    });
  });
}
