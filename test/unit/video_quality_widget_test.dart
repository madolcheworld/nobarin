import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/room/controllers/sync_controller.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/models/room_model.dart';
import 'package:nobarin/features/room/models/video_quality.dart';
import 'package:nobarin/features/room/presentation/widgets/unified_player_view.dart';

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
      currentMediaType: 'direct_url',
      currentMediaUrl: 'https://example.com/movie.mp4',
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

    testWidgets(
        '1. Bottom bar displays quality pill and opens VideoQualitySheet for single-track and multi-quality videos',
        (tester) async {
      await player.loadMedia(
        'direct_url',
        'https://example.com/movie.mp4',
        autoPlay: false,
      );

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

      // Tap on the quality button/pill
      await tester.tap(find.byIcon(Icons.tune_rounded).first);
      await tester.pumpAndSettle();

      // Single-track MP4 must show single-resolution notice and original quality tile
      expect(find.text('Kualitas Video'), findsOneWidget);
      expect(find.text('Resolusi tunggal'), findsOneWidget);
      expect(find.text('Resolusi Asli Video (Single Track)'), findsOneWidget);

      // Simulate multi-quality stream detected (e.g. HLS manifest parsed)
      player.setAvailableQualitiesForTesting([
        const VideoQuality.auto(),
        const VideoQuality(id: '1080', label: '1080p', height: 1080),
        const VideoQuality(id: '720', label: '720p', height: 720),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('2 resolusi tersedia'), findsOneWidget);
      expect(find.text('Auto (Otomatis)'), findsOneWidget);
      expect(find.text('1080p'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);
    });

    testWidgets('2. Selecting VideoQuality updates controller state',
        (tester) async {
      await player.loadMedia(
        'direct_url',
        'https://example.com/movie.mp4',
        autoPlay: false,
      );

      const customQuality = VideoQuality(
        id: '720',
        label: '720p HD',
        height: 720,
      );

      await player.setVideoQuality(customQuality);
      expect(player.selectedQuality?.id, equals('720'));
      expect(player.currentQualityLabel, equals('720p'));
    });
  });
}
