import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/browser/presentation/web_browser_sheet.dart';
import 'package:nobarin/features/room/controllers/queue_controller.dart';
import 'package:nobarin/features/room/controllers/sync_controller.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/controllers/web_browser_player_controller.dart';
import 'package:nobarin/features/room/models/queue_item.dart';
import 'package:nobarin/features/room/models/room_model.dart';
import 'package:nobarin/features/room/models/video_quality.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('WebBrowserMode Enum & Candidate Tests', () {
    test('enum has all required modes', () {
      expect(WebBrowserMode.values, contains(WebBrowserMode.general));
      expect(WebBrowserMode.values, contains(WebBrowserMode.queueOnly));
      expect(WebBrowserMode.values, contains(WebBrowserMode.createRoom));
      expect(WebBrowserMode.values, contains(WebBrowserMode.watchNow));
    });

    test('DetectedWebVideoCandidate resolutionLabel formats correctly', () {
      const html5Cand = DetectedWebVideoCandidate(
        id: 'c1',
        mediaType: 'web_browser',
        url: 'https://anime.example.com/ep1',
        label: 'Web Player',
        badge: 'Web Player',
        height: 1080,
      );
      expect(html5Cand.resolutionLabel, equals('1080p'));

      const streamCand = DetectedWebVideoCandidate(
        id: 'c2',
        mediaType: 'direct_url',
        url: 'https://cdn.example.com/master.m3u8',
        label: 'Stream Langsung',
        badge: 'HLS .m3u8',
      );
      expect(streamCand.resolutionLabel, isNull);
    });
  });

  group('WebBrowserPlayerController State & Normalization Tests', () {
    test('normalizes URLs including webbrowser:// scheme', () {
      expect(
        WebBrowserPlayerController.normalizeWebUrl(
            'webbrowser://https://example.com/watch/1'),
        equals('https://example.com/watch/1'),
      );
      expect(
        WebBrowserPlayerController.normalizeWebUrl('example.com/watch/1'),
        equals('https://example.com/watch/1'),
      );
    });

    test('playback control methods update state and notify listeners accurately',
        () async {
      final ctrl = WebBrowserPlayerController();
      int notifyCount = 0;
      ctrl.addListener(() => notifyCount++);

      await ctrl.play();
      expect(ctrl.isPlaying, isTrue);
      expect(notifyCount, equals(1));

      await ctrl.pause();
      expect(ctrl.isPlaying, isFalse);
      expect(notifyCount, equals(2));

      await ctrl.seekTo(90.0);
      expect(ctrl.position, equals(90.0));
      expect(notifyCount, equals(3));

      await ctrl.setVolume(0.5);
      expect(ctrl.volume, equals(0.5));
      expect(ctrl.isMuted, isFalse);
      expect(notifyCount, equals(4));

      await ctrl.toggleMute();
      expect(ctrl.isMuted, isTrue);
      expect(notifyCount, equals(5));

      await ctrl.toggleMute();
      expect(ctrl.isMuted, isFalse);
      expect(notifyCount, equals(6));

      await ctrl.setPlaybackSpeed(1.25);
      expect(ctrl.playbackSpeed, equals(1.25));
      expect(notifyCount, equals(7));

      ctrl.dispose();
    });
  });

  group('UnifiedPlayerController Web Browser URL Detection & Model Tests', () {
    test('detects webbrowser:// scheme URLs as web_browser mediaType', () {
      final detected = UnifiedPlayerController.detectMediaFromUrl(
        'webbrowser://https://anime.example.com/episode-1',
      );
      expect(detected, isNotNull);
      expect(detected!.mediaType, equals('web_browser'));
      expect(detected.isWebBrowser, isTrue);
      expect(detected.mediaUrl, equals('https://anime.example.com/episode-1'));
      expect(detected.title, contains('anime.example.com'));
    });

    test('QueueItem recognizes web_browser mediaType', () {
      final item = QueueItem(
        id: 'q-web-1',
        roomId: 'room1',
        mediaType: 'web_browser',
        mediaUrl: 'https://anime.example.com/episode-1',
        title: 'Episode 1 Sub Indo',
        addedByUserId: 'u1',
        addedByUserName: 'Alice',
        createdAt: DateTime.now(),
      );
      expect(item.isWebBrowser, isTrue);
      expect(item.isYouTube, isFalse);
      expect(item.isDirectUrl, isFalse);
    });

    test('VideoQuality.webBrowser constructs quality metadata properly', () {
      final qAuto = VideoQuality.webBrowser(id: 'auto', label: 'Auto');
      expect(qAuto.isAuto, isTrue);
      expect(qAuto.mode, equals(QualityControlMode.webviewBridge));

      final q720 = VideoQuality.webBrowser(
        id: '720p',
        label: '720p HD',
        height: 720,
      );
      expect(q720.shortLabel, equals('720p'));
      expect(q720.height, equals(720));
    });
  });

  group('WebBrowserSheet Widget & Mode Tests', () {
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
      currentMediaType: 'web_browser',
      currentMediaUrl: 'https://example.com/watch',
      currentState: 'playing',
      currentPosition: 10.0,
      livekitRoomName: 'room_WP1234',
      participantCount: 1,
    );

    late UnifiedPlayerController player;
    late SyncController syncController;
    late QueueController queueController;

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

    testWidgets('renders fallback UI with queueOnly mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WebBrowserSheet(
              mode: WebBrowserMode.queueOnly,
              queueController: queueController,
            ),
          ),
        ),
      );

      expect(find.text('Web Browser • Tambah Antrean'), findsOneWidget);
      expect(find.text('+ Tambahkan ke Antrean'), findsOneWidget);
    });

    testWidgets('renders fallback UI with createRoom mode and triggers onVideoSelected',
        (tester) async {
      String? selectedType;
      String? selectedUrl;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WebBrowserSheet(
              mode: WebBrowserMode.createRoom,
              onVideoSelected: (type, url, title) {
                selectedType = type;
                selectedUrl = url;
              },
            ),
          ),
        ),
      );

      expect(find.text('Web Browser • Buat Room'), findsOneWidget);
      expect(find.text('Buka Room dengan Video Ini'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).last,
        'https://anime.example.com/watch/ep-1',
      );
      await tester.tap(find.text('Buka Room dengan Video Ini'));
      await tester.pumpAndSettle();

      expect(selectedType, equals('web_browser'));
      expect(selectedUrl, equals('https://anime.example.com/watch/ep-1'));
    });

    testWidgets('queueOnly mode adds web_browser item to queue on fallback submit',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WebBrowserSheet(
              mode: WebBrowserMode.queueOnly,
              queueController: queueController,
            ),
          ),
        ),
      );

      const testUrl = 'https://anime.example.com/watch/episode-2';
      await tester.enterText(find.byType(TextField).last, testUrl);
      await tester.tap(find.text('+ Tambahkan ke Antrean'));
      await tester.pumpAndSettle();

      expect(queueController.items.length, equals(1));
      expect(queueController.items.first.mediaType, equals('web_browser'));
      expect(queueController.items.first.mediaUrl, equals(testUrl));
    });
  });
}
