import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/browser/presentation/vimeo_browser_sheet.dart';
import 'package:nobarin/features/room/controllers/queue_controller.dart';
import 'package:nobarin/features/room/controllers/sync_controller.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/models/room_model.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('VimeoBrowserMode Enum Tests', () {
    test('enum has all required modes', () {
      expect(VimeoBrowserMode.values, contains(VimeoBrowserMode.general));
      expect(VimeoBrowserMode.values, contains(VimeoBrowserMode.queueOnly));
      expect(VimeoBrowserMode.values, contains(VimeoBrowserMode.createRoom));
      expect(VimeoBrowserMode.values, contains(VimeoBrowserMode.watchNow));
    });
  });

  group('UnifiedPlayerController Vimeo URL Detection Tests', () {
    test('detects vimeo.com standard video URLs properly', () {
      final detected = UnifiedPlayerController.detectMediaFromUrl(
        'https://vimeo.com/76979871',
      );
      expect(detected, isNotNull);
      expect(detected!.mediaType, equals('vimeo'));
      expect(detected.isVimeo, isTrue);
      expect(detected.isYouTube, isFalse);
      expect(detected.isDailymotion, isFalse);
      expect(detected.mediaId, equals('76979871'));
      expect(detected.thumbnailUrl, equals('https://vumbnail.com/76979871.jpg'));
    });

    test('detects player.vimeo.com embed URLs properly', () {
      final detected = UnifiedPlayerController.detectMediaFromUrl(
        'https://player.vimeo.com/video/76979871',
      );
      expect(detected, isNotNull);
      expect(detected!.mediaType, equals('vimeo'));
      expect(detected.mediaId, equals('76979871'));
    });

    test('detects channels and groups Vimeo URLs properly', () {
      final channel = UnifiedPlayerController.detectMediaFromUrl(
        'https://vimeo.com/channels/staffpicks/76979871',
      );
      expect(channel, isNotNull);
      expect(channel!.mediaType, equals('vimeo'));
      expect(channel.mediaId, equals('76979871'));

      final group = UnifiedPlayerController.detectMediaFromUrl(
        'https://vimeo.com/groups/motion/videos/76979871',
      );
      expect(group, isNotNull);
      expect(group!.mediaType, equals('vimeo'));
      expect(group.mediaId, equals('76979871'));
    });

    test('detects unlisted Vimeo URLs with hash properly', () {
      final unlisted = UnifiedPlayerController.detectMediaFromUrl(
        'https://vimeo.com/76979871/abcdef1234',
      );
      expect(unlisted, isNotNull);
      expect(unlisted!.mediaType, equals('vimeo'));
      expect(unlisted.mediaId, equals('76979871'));
    });
  });

  group('VimeoBrowserSheet Widget & Mode Tests', () {
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
            body: VimeoBrowserSheet(
              mode: VimeoBrowserMode.queueOnly,
              queueController: queueController,
            ),
          ),
        ),
      );

      // Verify mode title in top bar
      expect(find.text('Tambah ke Antrean (Vimeo)'), findsOneWidget);
      // Verify fallback button has + Tambahkan ke Antrean
      expect(find.text('+ Tambahkan ke Antrean'), findsOneWidget);
    });

    testWidgets('renders fallback UI with createRoom mode', (tester) async {
      String? selectedUrl;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VimeoBrowserSheet(
              mode: VimeoBrowserMode.createRoom,
              onVideoSelected: (type, url, title) {
                selectedUrl = url;
              },
            ),
          ),
        ),
      );

      // Verify mode title in top bar
      expect(find.text('Pilih Video Vimeo'), findsOneWidget);
      // Verify fallback button has Pilih Video Ini
      expect(find.text('Pilih Video Ini'), findsOneWidget);

      // Enter a valid Vimeo URL in fallback
      await tester.enterText(
        find.byType(TextField),
        'https://vimeo.com/76979871',
      );
      await tester.tap(find.text('Pilih Video Ini'));
      await tester.pumpAndSettle();

      expect(selectedUrl, equals('https://vimeo.com/76979871'));
    });

    testWidgets('renders fallback UI with watchNow mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VimeoBrowserSheet(
              mode: VimeoBrowserMode.watchNow,
              syncController: syncController,
            ),
          ),
        ),
      );

      // Verify mode title in top bar
      expect(find.text('Ganti Video Room'), findsOneWidget);
      // Verify fallback button has Putar Sekarang
      expect(find.text('Putar Sekarang'), findsOneWidget);
    });

    testWidgets('queueOnly mode adds to queue on fallback submit', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VimeoBrowserSheet(
              mode: VimeoBrowserMode.queueOnly,
              queueController: queueController,
            ),
          ),
        ),
      );

      expect(queueController.items.isEmpty, isTrue);

      await tester.enterText(
        find.byType(TextField),
        'https://vimeo.com/76979871',
      );
      await tester.tap(find.text('+ Tambahkan ke Antrean'));
      await tester.pumpAndSettle();

      expect(queueController.items.length, equals(1));
      expect(
        queueController.items.first.mediaUrl,
        equals('https://vimeo.com/76979871'),
      );
      expect(queueController.items.first.mediaType, equals('vimeo'));
      expect(queueController.items.first.isVimeo, isTrue);
    });

    testWidgets('displays close button in top bar and pops', (tester) async {
      bool popped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const VimeoBrowserSheet(
                      mode: VimeoBrowserMode.createRoom,
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

      final closeBtn = find.byTooltip('Tutup');
      expect(closeBtn, findsOneWidget);

      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      expect(popped, isTrue);
    });
  });
}
