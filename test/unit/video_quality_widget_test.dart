import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_party/features/auth/domain/user_profile.dart';
import 'package:watch_party/features/room/controllers/sync_controller.dart';
import 'package:watch_party/features/room/controllers/unified_player_controller.dart';
import 'package:watch_party/features/room/models/room_model.dart';
import 'package:watch_party/features/room/presentation/widgets/unified_player_view.dart';
import 'package:watch_party/features/room/presentation/widgets/video_quality_sheet.dart';

void main() {
  group('Video Quality Fast & Accurate UI Flow Tests', () {
    late UnifiedPlayerController player;
    late SyncController syncController;

    const testUser = UserProfile(
      id: 'tester-1',
      username: 'Tester',
      avatarUrl: '🚀',
    );

    final testRoom = RoomModel(
      id: 'room-quality-1',
      code: 'WP7777',
      title: 'Quality Test Room',
      hostId: 'tester-1',
      hostName: 'Tester',
      isPublic: true,
      currentMediaType: 'youtube',
      currentMediaUrl: 'https://youtu.be/dQw4w9WgXcQ',
      livekitRoomName: 'room_WP7777',
    );

    setUp(() {
      player = UnifiedPlayerController();
      syncController = SyncController(
        room: testRoom,
        currentUser: testUser,
        player: player,
      );
    });

    tearDown(() {
      player.dispose();
      syncController.dispose();
    });

    testWidgets('1. Bottom bar displays quality pill and opens VideoQualitySheet on tap', (tester) async {
      await player.loadMedia('direct_url', 'https://example.com/movie.mp4', autoPlay: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedPlayerView(
              player: player,
              syncController: syncController,
              onOpenMediaPicker: () {},
              title: 'Quality Test Room',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the quality pill in the player controls
      expect(find.byIcon(Icons.tune_rounded), findsWidgets);
      expect(find.text('Auto'), findsWidgets);

      // Tap on the quality button/pill
      await tester.tap(find.byIcon(Icons.tune_rounded).first);
      await tester.pumpAndSettle();

      // Sheet must be open with title and Auto option
      expect(find.text('Kualitas Video'), findsOneWidget);
      expect(find.text('Auto (Otomatis)'), findsOneWidget);
    });

    testWidgets('2. Vimeo quality presets rendered and selectable', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await player.loadMedia('vimeo', 'https://vimeo.com/76979871', autoPlay: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoQualitySheet(player: player),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1080p Full HD'), findsOneWidget);
      expect(find.text('720p HD'), findsOneWidget);
      expect(find.text('540p'), findsOneWidget);
      expect(find.text('360p Hemat Kuota'), findsOneWidget);

      await tester.tap(find.text('720p HD'));
      await tester.pumpAndSettle();

      expect(player.selectedQuality?.id, '720p');
      expect(player.currentQualityLabel, '720p');
    });

    testWidgets('3. Dailymotion quality presets rendered and selectable', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await player.loadMedia('dailymotion', 'https://www.dailymotion.com/video/x8bgd2b', autoPlay: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoQualitySheet(player: player),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1080p Full HD'), findsOneWidget);
      expect(find.text('720p HD'), findsOneWidget);
      expect(find.text('480p SD'), findsOneWidget);
      expect(find.text('380p'), findsOneWidget);
      expect(find.text('240p Hemat Kuota'), findsOneWidget);

      await tester.tap(find.text('480p SD'));
      await tester.pumpAndSettle();

      expect(player.selectedQuality?.id, '480');
      expect(player.currentQualityLabel, '480p');
    });

    testWidgets('4. Twitch web source shows in-player gear guide notice', (tester) async {
      await player.loadMedia('twitch', 'https://www.twitch.tv/riotgames', autoPlay: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoQualitySheet(player: player),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Guide for Twitch web player
      expect(find.text('Menu Kualitas Bawaan Twitch'), findsOneWidget);
      expect(find.textContaining('ikon gerigi pengaturan'), findsOneWidget);
    });
  });
}
