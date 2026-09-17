import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/room/controllers/queue_controller.dart';
import 'package:nobarin/features/room/controllers/room_controller.dart';
import 'package:nobarin/features/room/controllers/sync_controller.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/models/room_model.dart';
import 'package:nobarin/features/room/presentation/widgets/room_controls_bar.dart';

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
        'renders clean status indicator in RoomControlsBar when media is empty without redundant play or pick button',
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

      // Verify no duplicate "Pilih Video" in controls bar (it is on the player stage)
      expect(find.text('Pilih Video'), findsNothing);
      // Verify redundant "Panggung Siap" badge is eliminated
      expect(find.text('Panggung Siap'), findsNothing);
      // Verify control mode pill is present
      expect(find.text('👑 Host Only'), findsOneWidget);
    });

    testWidgets(
        'renders compact Ganti button and media badge in RoomControlsBar without duplicate playback controls when media is loaded',
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

      // Playback controls are centered on video overlay, not duplicated in RoomControlsBar
      expect(find.byIcon(Icons.play_circle_filled_rounded), findsNothing);
      expect(find.byIcon(Icons.replay_10_rounded), findsNothing);
      expect(find.byIcon(Icons.forward_10_rounded), findsNothing);
      expect(find.text('Ganti'), findsOneWidget);

      // Test tapping Ganti
      await tester.tap(find.text('Ganti'));
      await tester.pumpAndSettle();
      expect(pickerCalled, isTrue);
    });

    testWidgets('does NOT render duplicate Antrean button in controls bar',
        (tester) async {
      final queueController = QueueController(
        roomId: baseRoom.id,
        currentUser: testHost,
        syncController: syncController,
        isHostProvider: () => true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomControlsBar(
              syncController: syncController,
              player: playerController,
              roomController: roomController,
              queueController: queueController,
              onOpenMediaPicker: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Antrean button is omitted from controls bar to avoid duplication with Social Hub tab
      expect(find.text('Antrean'), findsNothing);
      expect(find.byIcon(Icons.queue_music_rounded), findsNothing);

      queueController.dispose();
    });

    testWidgets('RoomControlsBar.showShareModal opens bottom sheet with room code and copy action',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => RoomControlsBar.showShareModal(context, baseRoom),
                child: const Text('Open Share'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Share'));
      await tester.pumpAndSettle();

      // Verify share modal contents
      expect(find.text('Bagikan Room'), findsOneWidget);
      expect(find.text(baseRoom.code), findsOneWidget);
      expect(find.text('Salin'), findsOneWidget);
      expect(find.text('Salin Teks Undangan Lengkap'), findsOneWidget);
    });

    testWidgets('RoomControlsBar.copyRoomCode copies code and shows SnackBar',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => RoomControlsBar.copyRoomCode(context, baseRoom.code),
                child: const Text('Copy Code'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Copy Code'));
      await tester.pump();

      // Verify SnackBar appears
      expect(
        find.text('Kode room ${baseRoom.code} berhasil disalin!'),
        findsOneWidget,
      );
    });

    testWidgets('renders interactive control mode pill for Host',
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

      await tester.pumpAndSettle();

      // Verify Host Only pill is rendered
      expect(find.text('👑 Host Only'), findsOneWidget);
    });
  });
}

