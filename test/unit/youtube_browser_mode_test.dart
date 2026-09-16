import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/browser/presentation/youtube_browser_sheet.dart';
import 'package:nobarin/features/room/controllers/queue_controller.dart';
import 'package:nobarin/features/room/controllers/sync_controller.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/models/room_model.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('YouTubeBrowserMode Enum Tests', () {
    test('enum has all required modes', () {
      expect(YouTubeBrowserMode.values, contains(YouTubeBrowserMode.general));
      expect(YouTubeBrowserMode.values, contains(YouTubeBrowserMode.queueOnly));
      expect(YouTubeBrowserMode.values, contains(YouTubeBrowserMode.createRoom));
      expect(YouTubeBrowserMode.values, contains(YouTubeBrowserMode.watchNow));
    });
  });

  group('YouTubeBrowserSheet Widget & Mode Tests', () {
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
            body: YouTubeBrowserSheet(
              mode: YouTubeBrowserMode.queueOnly,
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
            body: YouTubeBrowserSheet(
              mode: YouTubeBrowserMode.createRoom,
              onVideoSelected: (type, url, title) {
                selectedUrl = url;
              },
            ),
          ),
        ),
      );

      // Verify mode title in top bar
      expect(find.text('Pilih Video YouTube'), findsOneWidget);
      // Verify fallback button has Buka Room dengan Video Ini
      expect(find.text('Buka Room dengan Video Ini'), findsOneWidget);

      // Enter a valid URL in fallback
      await tester.enterText(
        find.byType(TextField),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      await tester.tap(find.text('Buka Room dengan Video Ini'));
      await tester.pumpAndSettle();

      expect(selectedUrl, equals('https://www.youtube.com/watch?v=dQw4w9WgXcQ'));
    });

    testWidgets('renders fallback UI with watchNow mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: YouTubeBrowserSheet(
              mode: YouTubeBrowserMode.watchNow,
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

    testWidgets('queueOnly mode adds to queue on fallback submit', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: YouTubeBrowserSheet(
              mode: YouTubeBrowserMode.queueOnly,
              queueController: queueController,
            ),
          ),
        ),
      );

      expect(queueController.items.isEmpty, isTrue);

      await tester.enterText(
        find.byType(TextField),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      await tester.tap(find.text('+ Tambahkan ke Antrean'));
      await tester.pumpAndSettle();

      expect(queueController.items.length, equals(1));
      expect(queueController.items.first.mediaUrl,
          equals('https://www.youtube.com/watch?v=dQw4w9WgXcQ'));
    });
  });
}
