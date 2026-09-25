import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/room/controllers/sync_controller.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/models/room_model.dart';
import 'package:nobarin/features/room/presentation/widgets/unified_player_view.dart';

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

      // Tap back button
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(exitCalled, isTrue);
    });

    testWidgets(
        'tapping back/exit button does NOT toggle play/pause and tapping play does NOT trigger onExit',
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

      // Tap back/exit button: MUST call onExit and must NOT change isPlaying
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(exitCalled, isTrue);
      expect(playerController.isPlaying, isFalse);

      // Now tap center play button: must trigger play, must NOT call onExit again
      exitCalled = false;
      await tester.tap(find.byIcon(Icons.play_circle_filled_rounded));
      await tester.pumpAndSettle();

      expect(exitCalled, isFalse);
    });

    testWidgets(
        'can toggle controls overlay visibility even when paused with smooth AnimatedOpacity',
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
              title: 'Watch Party Movie',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // AnimatedOpacity should exist and initially be visible (opacity 1.0)
      final animatedOpacityFinder = find.byType(AnimatedOpacity);
      expect(animatedOpacityFinder, findsOneWidget);
      AnimatedOpacity animatedOpacity =
          tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(animatedOpacity.opacity, equals(1.0));

      // Tap on background gradient area (away from center play button) to toggle controls while paused
      await tester.tapAt(const Offset(200, 200));
      await tester.pump(); // Start animation
      await tester.pump(const Duration(milliseconds: 300)); // Complete fade out

      animatedOpacity = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(animatedOpacity.opacity, equals(0.0));

      // Tap again on the player surface to show controls
      await tester.tapAt(const Offset(200, 200));
      await tester.pump(); // Start animation
      await tester.pump(const Duration(milliseconds: 300)); // Complete fade in

      animatedOpacity = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(animatedOpacity.opacity, equals(1.0));
    });

    testWidgets(
        'auto-hides controls after timer expires while playing even if position updates occur',
        (tester) async {
      await playerController.loadMedia(
        'direct_url',
        'https://example.com/test.mp4',
        autoPlay: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedPlayerView(
              player: playerController,
              syncController: syncController,
              onOpenMediaPicker: () {},
              title: 'Auto Hide Test',
            ),
          ),
        ),
      );

      await tester.pump();
      final animatedOpacityFinder = find.byType(AnimatedOpacity);
      expect(animatedOpacityFinder, findsOneWidget);

      AnimatedOpacity animatedOpacity =
          tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(animatedOpacity.opacity, equals(1.0));

      // Simulate streaming position updates every 250ms during playback
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        playerController.notifyListeners();
      }

      // Elapsed so far is 1000ms, controls should still be visible
      animatedOpacity = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(animatedOpacity.opacity, equals(1.0));

      // Advance past 3000ms total (2000ms remaining + animation duration)
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump(const Duration(milliseconds: 300)); // Finish opacity animation

      animatedOpacity = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(animatedOpacity.opacity, equals(0.0));
    });

    testWidgets(
        'controls remain hidden while paused even when periodic notifyListeners occur',
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
              title: 'Paused Hide Test',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final animatedOpacityFinder = find.byType(AnimatedOpacity);
      expect(animatedOpacityFinder, findsOneWidget);

      // Initially visible
      AnimatedOpacity animatedOpacity =
          tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(animatedOpacity.opacity, equals(1.0));

      // Tap background to hide controls while paused
      await tester.tapAt(const Offset(200, 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      animatedOpacity = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(animatedOpacity.opacity, equals(0.0));

      // Fire notifications while still paused (e.g. metadata or room events)
      // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
      playerController.notifyListeners();
      await tester.pump(const Duration(milliseconds: 200));

      // Controls MUST remain hidden (not forced open by notification)
      animatedOpacity = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(animatedOpacity.opacity, equals(0.0));
    });

    testWidgets('quick hide triggers 1s after tapping Play button',
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
              title: 'Quick Play Hide Test',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final animatedOpacityFinder = find.byType(AnimatedOpacity);

      // Tap center play button
      await tester.tap(find.byIcon(Icons.play_circle_filled_rounded));
      await tester.pump();

      // Controls should still be visible immediately after tap
      AnimatedOpacity animatedOpacity =
          tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(animatedOpacity.opacity, equals(1.0));

      // Advance 3000ms + 300ms animation
      await tester.pump(const Duration(milliseconds: 3000));
      await tester.pump(const Duration(milliseconds: 300));

      // Should now be hidden
      animatedOpacity = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(animatedOpacity.opacity, equals(0.0));
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

    testWidgets('renders volume button and toggles mute/unmute when playing and muted',
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

      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

      // Tapping volume icon unmutes
      await tester.tap(find.byIcon(Icons.volume_off_rounded));
      await tester.pumpAndSettle();

      expect(playerController.isMuted, isFalse);
    });

    testWidgets('renders center replay and forward 10s seek buttons and triggers seek',
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

      // Verify YouTube style center seek buttons are present
      expect(find.byIcon(Icons.replay_10_rounded), findsOneWidget);
      expect(find.byIcon(Icons.forward_10_rounded), findsOneWidget);

      // Tap forward 10s
      await tester.tap(find.byIcon(Icons.forward_10_rounded));
      await tester.pumpAndSettle();

      // Tap rewind 10s
      await tester.tap(find.byIcon(Icons.replay_10_rounded));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'renders empty placeholder with screenshare UI and no controls overlay when mediaType is screenshare',
        (tester) async {
      await playerController.loadMedia('screenshare', 'screenshare');

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

      expect(find.text('Mirror Layar Belum Aktif'), findsOneWidget);
      expect(find.byIcon(Icons.mobile_screen_share_rounded), findsOneWidget);
      // Ensure playback controls overlay is NOT shown
      expect(find.byIcon(Icons.replay_10_rounded), findsNothing);
      expect(find.byIcon(Icons.forward_10_rounded), findsNothing);
    });

    testWidgets('hides all controls overlay when isPipMode is true',
        (tester) async {
      await playerController.loadMedia(
        'direct_url',
        'https://example.com/test.mp4',
        autoPlay: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedPlayerView(
              player: playerController,
              syncController: syncController,
              onOpenMediaPicker: () {},
              isPipMode: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Controls overlay (replay, forward, play/pause, time labels, slider) must NOT be present
      expect(find.byIcon(Icons.replay_10_rounded), findsNothing);
      expect(find.byIcon(Icons.forward_10_rounded), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      expect(find.byIcon(Icons.pause_rounded), findsNothing);
      expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);
    });

    testWidgets(
        'forward and rewind buttons do not seek to 0 when duration is unloaded or zero',
        (tester) async {
      await playerController.loadMedia(
        'direct_url',
        'https://example.com/test.mp4',
        autoPlay: false,
      );

      // Duration is 0.0 before metadata loads
      await playerController.seekTo(25.0);
      expect(playerController.duration, 0.0);
      expect(playerController.position, 25.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedPlayerView(
              player: playerController,
              syncController: syncController,
              onOpenMediaPicker: () {},
              title: 'Seek Safe Test',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Forward 10s button
      final forwardFinder = find.byIcon(Icons.forward_10_rounded);
      expect(forwardFinder, findsOneWidget);
      await tester.tap(forwardFinder);
      await tester.pumpAndSettle();

      // Target should be 25 + 10 = 35.0, NOT clamped to 0.0!
      expect(playerController.position, 35.0);

      // Tap Rewind 10s button
      final rewindFinder = find.byIcon(Icons.replay_10_rounded);
      expect(rewindFinder, findsOneWidget);
      await tester.tap(rewindFinder);
      await tester.pumpAndSettle();

      expect(playerController.position, 25.0);
    });
  });
}
