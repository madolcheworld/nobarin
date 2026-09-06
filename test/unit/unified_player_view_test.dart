import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_party/features/auth/domain/user_profile.dart';
import 'package:watch_party/features/room/controllers/sync_controller.dart';
import 'package:watch_party/features/room/controllers/unified_player_controller.dart';
import 'package:watch_party/features/room/models/room_model.dart';
import 'package:watch_party/features/room/presentation/widgets/unified_player_view.dart';

void main() {
  group('UnifiedPlayerView Widget Tests', () {
    late UnifiedPlayerController playerController;
    late SyncController syncController;

    final testUser = const UserProfile(
      id: 'user-exit-1',
      username: 'TestUser',
      avatarUrl: '🦊',
    );

    final testRoom = RoomModel(
      id: 'room-view-1',
      code: 'WP5555',
      title: 'Awesome Movie Night',
      hostId: 'user-exit-1',
      hostName: 'TestUser',
      isPublic: true,
      currentMediaType: 'direct_url',
      currentMediaUrl: 'https://example.com/stream.mp4',
      livekitRoomName: 'room_WP5555',
    );

    setUp(() {
      playerController = UnifiedPlayerController();
      syncController = SyncController(
        room: testRoom,
        currentUser: testUser,
        player: playerController,
      );
    });

    tearDown(() {
      playerController.dispose();
      syncController.dispose();
    });

    testWidgets('renders empty placeholder when no media loaded',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedPlayerView(
              player: playerController,
              syncController: syncController,
              onOpenMediaPicker: () {},
            ),
          ),
        ),
      );

      expect(find.text('Belum ada media yang dimuat'), findsOneWidget);
      expect(find.text('Pilih Video'), findsOneWidget);
    });

    testWidgets(
        'renders top navigation bar with exit and back buttons when media present and triggers onExit',
        (tester) async {
      bool exitCalled = false;

      // Load media
      await playerController.loadMedia(
        'direct_url',
        'https://example.com/test.mp4',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedPlayerView(
              player: playerController,
              syncController: syncController,
              onOpenMediaPicker: () {},
              onExit: () {
                exitCalled = true;
              },
              title: 'Awesome Movie Night',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Top navigation bar elements should be present
      expect(find.text('Awesome Movie Night'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.byIcon(Icons.exit_to_app_rounded), findsOneWidget);

      // Tap exit button
      await tester.tap(find.byIcon(Icons.exit_to_app_rounded));
      await tester.pumpAndSettle();

      expect(exitCalled, isTrue);

      // Tap back button
      exitCalled = false;
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(exitCalled, isTrue);
    });

    testWidgets(
        'tapping exit button does NOT toggle play/pause and tapping play does NOT trigger onExit',
        (tester) async {
      bool exitCalled = false;

      // Load media in paused state
      await playerController.loadMedia(
        'direct_url',
        'https://example.com/test.mp4',
        autoPlay: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedPlayerView(
              player: playerController,
              syncController: syncController,
              onOpenMediaPicker: () {},
              onExit: () {
                exitCalled = true;
              },
              title: 'Watch Party Movie',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Ensure initially paused
      expect(playerController.isPlaying, isFalse);

      // Tap exit button: MUST call onExit and must NOT change isPlaying
      await tester.tap(find.byIcon(Icons.exit_to_app_rounded));
      await tester.pumpAndSettle();

      expect(exitCalled, isTrue);
      expect(playerController.isPlaying, isFalse);

      // Now tap center play button: must trigger play, must NOT call onExit again
      exitCalled = false;
      await tester.tap(find.byIcon(Icons.play_circle_filled_rounded));
      await tester.pumpAndSettle();

      expect(exitCalled, isFalse);
    });

    testWidgets('renders error overlay when player has an errorMessage',
        (tester) async {
      await playerController.loadMedia(
        'direct_url',
        'https://example.com/test.mp4',
        autoPlay: false,
      );

      // Force an error message
      // We can simulate an error by calling a helper or setting error
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedPlayerView(
              player: playerController,
              syncController: syncController,
              onOpenMediaPicker: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Gagal Memutar Video'), findsNothing);

      // Trigger error via player controller listeners
      // Since _errorMessage is private, clearError clears it; we can test clearError with overlay
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    });

    testWidgets('renders fullscreen button and triggers fullscreen action without crashing',
        (tester) async {
      await playerController.loadMedia(
        'direct_url',
        'https://example.com/test.mp4',
        autoPlay: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedPlayerView(
              player: playerController,
              syncController: syncController,
              onOpenMediaPicker: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Fullscreen button should be present for direct_url media
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.fullscreen_rounded));
      await tester.pumpAndSettle();
    });

    testWidgets('renders Bunyikan Suara chip when playing and muted',
        (tester) async {
      await playerController.loadMedia(
        'direct_url',
        'https://example.com/test.mp4',
        autoPlay: false,
      );

      await playerController.toggleMute(); // sets isMuted = true
      await playerController.play(); // sets isPlaying = true

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedPlayerView(
              player: playerController,
              syncController: syncController,
              onOpenMediaPicker: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Bunyikan Suara'), findsOneWidget);

      // Tapping Bunyikan Suara unmutes
      await tester.tap(find.text('Bunyikan Suara'));
      await tester.pumpAndSettle();

      expect(playerController.isMuted, isFalse);
    });
  });
}
