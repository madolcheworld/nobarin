import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/browser/presentation/google_drive_browser_sheet.dart';
import 'package:nobarin/features/room/controllers/google_drive_player_controller.dart';
import 'package:nobarin/features/room/controllers/queue_controller.dart';
import 'package:nobarin/features/room/controllers/sync_controller.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/models/queue_item.dart';
import 'package:nobarin/features/room/models/room_model.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('GoogleDriveBrowserMode Enum Tests', () {
    test('enum has all required modes', () {
      expect(GoogleDriveBrowserMode.values,
          contains(GoogleDriveBrowserMode.general));
      expect(GoogleDriveBrowserMode.values,
          contains(GoogleDriveBrowserMode.queueOnly));
      expect(GoogleDriveBrowserMode.values,
          contains(GoogleDriveBrowserMode.createRoom));
      expect(GoogleDriveBrowserMode.values,
          contains(GoogleDriveBrowserMode.watchNow));
    });
  });

  group('GoogleDrivePlayerController ID Extraction & Preview Tests', () {
    test('extracts file ID from standard /file/d/ URLs', () {
      const url =
          'https://drive.google.com/file/d/1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P/view?usp=sharing';
      final fileId = GoogleDrivePlayerController.extractFileId(url);
      expect(fileId, equals('1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P'));
    });

    test('extracts file ID from preview URLs', () {
      const url =
          'https://drive.google.com/file/d/1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P/preview';
      final fileId = GoogleDrivePlayerController.extractFileId(url);
      expect(fileId, equals('1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P'));
    });

    test('extracts file ID from open?id= URLs', () {
      const url =
          'https://drive.google.com/open?id=1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P';
      final fileId = GoogleDrivePlayerController.extractFileId(url);
      expect(fileId, equals('1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P'));
    });

    test('extracts file ID from uc?id= export URLs', () {
      const url =
          'https://drive.google.com/uc?id=1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P&export=download';
      final fileId = GoogleDrivePlayerController.extractFileId(url);
      expect(fileId, equals('1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P'));
    });

    test('extracts file ID from docs.google.com URLs', () {
      const url =
          'https://docs.google.com/file/d/1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P/edit';
      final fileId = GoogleDrivePlayerController.extractFileId(url);
      expect(fileId, equals('1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P'));
    });

    test('accepts raw Google Drive file ID with standard length and chars', () {
      const rawId = '1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P';
      final fileId = GoogleDrivePlayerController.extractFileId(rawId);
      expect(fileId, equals(rawId));
    });

    test('returns null for non-Google Drive URLs', () {
      expect(
          GoogleDrivePlayerController.extractFileId('https://example.com/video.mp4'),
          isNull);
      expect(
          GoogleDrivePlayerController.extractFileId('https://youtube.com/watch?v=123'),
          isNull);
    });

    test('resolvePreviewUri formats correct embed URL', () {
      final uri = GoogleDrivePlayerController.resolvePreviewUri(
          '1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P');
      expect(uri.toString(),
          equals('https://drive.google.com/file/d/1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P/preview'));
    });

    test('playback control methods update state and notify listeners accurately', () async {
      final ctrl = GoogleDrivePlayerController();
      int notifyCount = 0;
      ctrl.addListener(() => notifyCount++);

      await ctrl.play();
      expect(ctrl.isPlaying, isTrue);
      expect(notifyCount, equals(1));

      await ctrl.pause();
      expect(ctrl.isPlaying, isFalse);
      expect(notifyCount, equals(2));

      await ctrl.seekTo(125.5);
      expect(ctrl.position, equals(125.5));
      expect(notifyCount, equals(3));

      await ctrl.setVolume(0.6);
      expect(ctrl.volume, equals(0.6));
      expect(ctrl.isMuted, isFalse);
      expect(notifyCount, equals(4));

      await ctrl.mute();
      expect(ctrl.isMuted, isTrue);
      expect(notifyCount, equals(5));

      await ctrl.unmute();
      expect(ctrl.isMuted, isFalse);
      expect(notifyCount, equals(6));

      await ctrl.setPlaybackSpeed(1.5);
      expect(ctrl.playbackSpeed, equals(1.5));
      expect(notifyCount, equals(7));

      ctrl.dispose();
    });
  });

  group('UnifiedPlayerController Google Drive URL Detection Tests', () {
    test('detects drive.google.com/file/d URLs properly', () {
      final detected = UnifiedPlayerController.detectMediaFromUrl(
        'https://drive.google.com/file/d/1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P/view',
      );
      expect(detected, isNotNull);
      expect(detected!.mediaType, equals('google_drive'));
      expect(detected.isGoogleDrive, isTrue);
      expect(detected.isYouTube, isFalse);
      expect(detected.isBstation, isFalse);
      expect(detected.isDailymotion, isFalse);
      expect(detected.mediaId, equals('1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P'));
    });

    test('detects docs.google.com URLs properly', () {
      final detected = UnifiedPlayerController.detectMediaFromUrl(
        'https://docs.google.com/file/d/1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P/preview',
      );
      expect(detected, isNotNull);
      expect(detected!.mediaType, equals('google_drive'));
      expect(detected.mediaId, equals('1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P'));
    });
  });

  group('QueueItem Google Drive Model Tests', () {
    test('recognizes google_drive and gdrive mediaType', () {
      final item1 = QueueItem(
        id: 'q1',
        roomId: 'room1',
        mediaType: 'google_drive',
        mediaUrl: 'https://drive.google.com/file/d/123/preview',
        title: 'Video Drive Test',
        addedByUserId: 'u1',
        addedByUserName: 'Alice',
        createdAt: DateTime.now(),
      );
      expect(item1.isGoogleDrive, isTrue);
      expect(item1.isYouTube, isFalse);
      expect(item1.isDailymotion, isFalse);

      final item2 = QueueItem(
        id: 'q2',
        roomId: 'room1',
        mediaType: 'gdrive',
        mediaUrl: 'https://drive.google.com/file/d/123/preview',
        title: 'Video Drive Test 2',
        addedByUserId: 'u1',
        addedByUserName: 'Alice',
        createdAt: DateTime.now(),
      );
      expect(item2.isGoogleDrive, isTrue);
    });
  });

  group('GoogleDriveBrowserSheet Widget & Mode Tests', () {
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
            body: GoogleDriveBrowserSheet(
              mode: GoogleDriveBrowserMode.queueOnly,
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
            body: GoogleDriveBrowserSheet(
              mode: GoogleDriveBrowserMode.createRoom,
              onVideoSelected: (type, url, title) {
                selectedUrl = url;
              },
            ),
          ),
        ),
      );

      // Verify mode title in top bar
      expect(find.text('Pilih Video Google Drive'), findsOneWidget);
      // Verify fallback button has Buka Room dengan Video Ini
      expect(find.text('Buka Room dengan Video Ini'), findsOneWidget);

      // Enter a valid URL in fallback
      await tester.enterText(
        find.byType(TextField),
        'https://drive.google.com/file/d/1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P/view',
      );
      await tester.tap(find.text('Buka Room dengan Video Ini'));
      await tester.pumpAndSettle();

      expect(
        selectedUrl,
        equals('https://drive.google.com/file/d/1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P/view'),
      );
    });

    testWidgets('renders fallback UI with watchNow mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GoogleDriveBrowserSheet(
              mode: GoogleDriveBrowserMode.watchNow,
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
            body: GoogleDriveBrowserSheet(
              mode: GoogleDriveBrowserMode.queueOnly,
              queueController: queueController,
            ),
          ),
        ),
      );

      const testUrl =
          'https://drive.google.com/file/d/1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P/view';
      await tester.enterText(find.byType(TextField), testUrl);
      await tester.tap(find.text('+ Tambahkan ke Antrean'));
      await tester.pumpAndSettle();

      expect(queueController.items.length, equals(1));
      expect(queueController.items.first.mediaType, equals('google_drive'));
      expect(queueController.items.first.mediaUrl, equals(testUrl));
    });
  });
}
