import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/browser/presentation/dailymotion_browser_sheet.dart';
import 'package:nobarin/features/room/controllers/queue_controller.dart';
import 'package:nobarin/features/room/controllers/sync_controller.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/models/room_model.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('DailymotionBrowserMode Enum Tests', () {
    test('enum has all required modes', () {
      expect(DailymotionBrowserMode.values,
          contains(DailymotionBrowserMode.general));
      expect(DailymotionBrowserMode.values,
          contains(DailymotionBrowserMode.queueOnly));
      expect(DailymotionBrowserMode.values,
          contains(DailymotionBrowserMode.createRoom));
      expect(DailymotionBrowserMode.values,
          contains(DailymotionBrowserMode.watchNow));
    });
  });

  group('UnifiedPlayerController Dailymotion URL Detection Tests', () {
    test('detects dailymotion.com/video URLs properly', () {
      final detected = UnifiedPlayerController.detectMediaFromUrl(
        'https://www.dailymotion.com/video/x7tgad0',
      );
      expect(detected, isNotNull);
      expect(detected!.mediaType, equals('dailymotion'));
      expect(detected.isDailymotion, isTrue);
      expect(detected.isYouTube, isFalse);
      expect(detected.isBstation, isFalse);
      expect(detected.mediaId, equals('x7tgad0'));
    });

    test('detects dai.ly short URLs properly', () {
      final detected = UnifiedPlayerController.detectMediaFromUrl(
        'https://dai.ly/x7tgad0',
      );
      expect(detected, isNotNull);
      expect(detected!.mediaType, equals('dailymotion'));
      expect(detected.mediaId, equals('x7tgad0'));
    });

    test('detects geo.dailymotion.com embed player URLs properly', () {
      final detected = UnifiedPlayerController.detectMediaFromUrl(
        'https://geo.dailymotion.com/player.html?video=x7tgad0',
      );
      expect(detected, isNotNull);
      expect(detected!.mediaType, equals('dailymotion'));
      expect(detected.mediaId, equals('x7tgad0'));
    });
  });

  group('DailymotionBrowserSheet Widget & Mode Tests', () {
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
      currentMediaType: 'direct_url',
      currentMediaUrl: 'https://example.com/test1.mp4',
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
            body: DailymotionBrowserSheet(
              mode: DailymotionBrowserMode.queueOnly,
              queueController: queueController,
            ),
          ),
        ),
      );

      // Verify mode title in top bar
      expect(find.text('Tambah ke Antrean'), findsOneWidget);
      // Verify fallback button has + Tambahkan ke Antrean
      expect(find.text('+ Tambahkan ke Antrean'), findsOneWidget);
    });

    testWidgets('renders fallback UI with createRoom mode', (tester) async {
      String? selectedUrl;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailymotionBrowserSheet(
              mode: DailymotionBrowserMode.createRoom,
              onVideoSelected: (type, url, title) {
                selectedUrl = url;
              },
            ),
          ),
        ),
      );

      // Verify mode title in top bar
      expect(find.text('Pilih Video Dailymotion'), findsOneWidget);
      // Verify fallback button has Buka Room dengan Video Ini
      expect(find.text('Buka Room dengan Video Ini'), findsOneWidget);

      // Enter a valid URL in fallback
      await tester.enterText(
        find.byType(TextField),
        'https://www.dailymotion.com/video/x7tgad0',
      );
      await tester.tap(find.text('Buka Room dengan Video Ini'));
      await tester.pumpAndSettle();

      expect(selectedUrl, equals('https://www.dailymotion.com/video/x7tgad0'));
    });

    testWidgets('renders fallback UI with watchNow mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailymotionBrowserSheet(
              mode: DailymotionBrowserMode.watchNow,
              syncController: syncController,
            ),
          ),
        ),
      );

      // Verify mode title in top bar
      expect(find.text('Ganti Video Room'), findsOneWidget);
      // Verify fallback button has Putar Sekarang di Room
      expect(find.text('Tonton Video Ini'), findsNothing);
      expect(find.text('+ Tambahkan ke Antrean'), findsNothing);
    });

    testWidgets('queueOnly mode adds to queue on fallback submit',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailymotionBrowserSheet(
              mode: DailymotionBrowserMode.queueOnly,
              queueController: queueController,
            ),
          ),
        ),
      );

      expect(queueController.items.isEmpty, isTrue);

      await tester.enterText(
        find.byType(TextField),
        'https://www.dailymotion.com/video/x7tgad0',
      );
      await tester.tap(find.text('+ Tambahkan ke Antrean'));
      await tester.pumpAndSettle();

      expect(queueController.items.length, equals(1));
      expect(queueController.items.first.mediaUrl,
          equals('https://www.dailymotion.com/video/x7tgad0'));
      expect(queueController.items.first.mediaType, equals('dailymotion'));
      expect(queueController.items.first.isDailymotion, isTrue);
    });

    testWidgets('displays back button and close button in top bar',
        (tester) async {
      bool popped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DailymotionBrowserSheet(
                      mode: DailymotionBrowserMode.createRoom,
                    ),
                  ),
                ).then((_) => popped = true);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Verify back button (Kembali) with arrow_back_rounded exists
      final backBtn = find.byTooltip('Kembali');
      expect(backBtn, findsOneWidget);
      expect(
        find.descendant(of: backBtn, matching: find.byIcon(Icons.arrow_back_rounded)),
        findsOneWidget,
      );

      // Verify close button (Tutup) with close_rounded exists
      final closeBtn = find.byTooltip('Tutup');
      expect(closeBtn, findsOneWidget);
      expect(
        find.descendant(of: closeBtn, matching: find.byIcon(Icons.close_rounded)),
        findsOneWidget,
      );

      // Tap back button and verify sheet pops
      await tester.tap(backBtn);
      await tester.pumpAndSettle();
      expect(popped, isTrue);
    });
  });
}
