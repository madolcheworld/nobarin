import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/room/controllers/bstation_player_controller.dart';
import 'package:nobarin/features/room/controllers/sync_controller.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/models/room_model.dart';
import 'package:nobarin/features/room/models/video_quality.dart';
import 'package:nobarin/features/room/presentation/widgets/video_quality_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BstationPlayerController - Dynamic Video Quality Unit Tests', () {
    late BstationPlayerController controller;

    setUp(() {
      controller = BstationPlayerController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('1. Initial state has only Auto without hardcoded resolution options', () {
      expect(controller.availableQualities, isNotEmpty);
      expect(controller.availableQualities.length, equals(1));

      final autoQ = controller.availableQualities[0];
      expect(autoQ.isAuto, isTrue);
      expect(autoQ.id, equals('auto'));
      expect(autoQ.shortLabel, equals('Auto'));
      expect(autoQ.mode, equals(QualityControlMode.webviewBridge));
      expect(controller.selectedQuality?.isAuto, isTrue);
    });

    test('2. setQuality switches quality across dynamically detected qualities', () async {
      controller.handleBridgeMessageForTesting(jsonEncode({
        'event': 'qualities',
        'qualities': [
          {'id': '64', 'height': 720, 'label': '720p HD'},
          {'id': '32', 'height': 480, 'label': '480p Standar'},
          {'id': '16', 'height': 360, 'label': '360p Hemat'},
        ],
      }));

      VideoQuality? selectedCallbackQuality;
      var notifyCount = 0;

      controller.onQualitySelectedChanged = (quality) {
        selectedCallbackQuality = quality;
      };
      controller.addListener(() {
        notifyCount++;
      });

      // Switch to 720p (by Bstation qn ID '64')
      await controller.setQuality('64');
      expect(controller.selectedQuality?.id, equals('64'));
      expect(controller.selectedQuality?.height, equals(720));
      expect(selectedCallbackQuality?.id, equals('64'));
      expect(notifyCount, greaterThan(0));

      // Switch to 480p
      await controller.setQuality('32');
      expect(controller.selectedQuality?.id, equals('32'));
      expect(controller.selectedQuality?.height, equals(480));
      expect(selectedCallbackQuality?.id, equals('32'));

      // Switch back to auto
      await controller.setQuality('auto');
      expect(controller.selectedQuality?.isAuto, isTrue);
      expect(selectedCallbackQuality?.isAuto, isTrue);
    });

    test('3. setQuality handles custom/unknown quality fallback gracefully', () async {
      await controller.setQuality('1080');
      expect(controller.selectedQuality?.id, equals('1080'));
      expect(controller.selectedQuality?.label, equals('1080p'));
      expect(controller.selectedQuality?.mode, equals(QualityControlMode.webviewBridge));
    });

    test('4. Bridge message "resolution" updates detected height & width without fabricating tiers', () {
      var notified = false;
      controller.addListener(() => notified = true);

      controller.handleBridgeMessageForTesting(jsonEncode({
        'event': 'resolution',
        'height': 720,
        'width': 1280,
      }));

      expect(controller.detectedHeight, equals(720));
      expect(controller.detectedWidth, equals(1280));
      // Must NOT fabricate fake [720, 480, 360, 240] tiers
      expect(controller.availableQualities.length, equals(1));
      expect(notified, isTrue);
    });

    test('5. Bridge message "qualitychange" updates selected quality', () {
      controller.handleBridgeMessageForTesting(jsonEncode({
        'event': 'qualities',
        'qualities': [
          {'id': '720', 'height': 720, 'label': '720p HD'},
          {'id': '480', 'height': 480, 'label': '480p Standar'},
        ],
      }));

      VideoQuality? callbackQuality;
      controller.onQualitySelectedChanged = (q) => callbackQuality = q;

      controller.handleBridgeMessageForTesting(jsonEncode({
        'event': 'qualitychange',
        'quality': '480',
      }));

      expect(controller.selectedQuality?.id, equals('480'));
      expect(callbackQuality?.id, equals('480'));
    });

    test('6. Bridge message "qualities" populates only the exact resolutions of the video', () {
      List<VideoQuality>? updatedQualities;
      controller.onQualitiesChanged = (qualities) => updatedQualities = qualities;

      // Video only has 1080p and 360p (no 720p or 480p)
      controller.handleBridgeMessageForTesting(jsonEncode({
        'event': 'qualities',
        'qualities': [
          {'id': '80', 'height': 1080, 'label': '1080p Full HD'},
          {'id': '16', 'height': 360, 'label': '360p Hemat'},
        ],
      }));

      expect(controller.availableQualities.length, equals(3)); // Auto + 1080p + 360p
      expect(controller.availableQualities.first.isAuto, isTrue);
      expect(controller.availableQualities[1].id, equals('80'));
      expect(controller.availableQualities[1].height, equals(1080));
      expect(controller.availableQualities[2].id, equals('16'));
      expect(controller.availableQualities[2].height, equals(360));
      expect(controller.availableQualities.any((q) => q.height == 720), isFalse);
      expect(controller.availableQualities.any((q) => q.height == 480), isFalse);
      expect(updatedQualities, isNotNull);
    });
  });

  group('UnifiedPlayerController - Bstation Quality Integration Tests', () {
    late UnifiedPlayerController player;

    setUp(() {
      player = UnifiedPlayerController();
    });

    tearDown(() {
      player.dispose();
    });

    test('1. Bstation media loading starts with Auto only (no hardcoded tiers) and updates label on resolution', () async {
      await player.loadMedia(
        'bstation',
        'https://www.bilibili.tv/id/video/2048573920',
        autoPlay: false,
      );

      expect(player.mediaType, equals('bstation'));
      expect(player.availableQualities.length, equals(1));
      expect(player.availableQualities.first.isAuto, isTrue);
      expect(player.supportsQualitySelection, isFalse);

      // Initially Auto without resolution
      expect(player.currentQualityLabel, equals('Auto'));

      // Simulate video stream starting and reporting 720p resolution
      player.bstationController?.handleBridgeMessageForTesting(jsonEncode({
        'event': 'resolution',
        'height': 720,
        'width': 1280,
      }));

      // In Auto mode, label reflects detected stream height
      expect(player.currentQualityLabel, equals('Auto (720p)'));
      expect(player.maxDetectedHeight, equals(720));
    });

    test('2. Dynamic qualities event from Bstation bridge enables quality selection with exact tiers', () async {
      await player.loadMedia(
        'bstation',
        'https://www.bilibili.tv/id/video/2048573920',
        autoPlay: false,
      );

      player.bstationController?.handleBridgeMessageForTesting(jsonEncode({
        'event': 'qualities',
        'qualities': [
          {'id': '1080', 'height': 1080, 'label': '1080p FHD'},
          {'id': '720', 'height': 720, 'label': '720p HD'},
          {'id': '360', 'height': 360, 'label': '360p Hemat'},
        ],
      }));

      expect(player.supportsQualitySelection, isTrue);
      expect(player.explicitQualityCount, equals(3));
      expect(player.availableQualities.any((q) => q.id == '1080'), isTrue);
      expect(player.availableQualities.any((q) => q.id == '480'), isFalse);
      expect(player.maxDetectedHeight, equals(1080));
      expect(player.maxResolutionLabel, equals('Full HD (1080p)'));

      final q720 = player.availableQualities.firstWhere((q) => q.id == '720');
      await player.setVideoQuality(q720);

      expect(player.selectedQuality?.id, equals('720'));
      expect(player.currentQualityLabel, equals('720p'));
    });
  });

  group('VideoQualitySheet - Bstation UI Quality Selection Tests', () {
    late UnifiedPlayerController player;
    late SyncController syncController;

    const testUser = UserProfile(
      id: 'tester-1',
      username: 'Tester',
      avatarUrl: '🚀',
    );

    final testRoom = RoomModel(
      id: 'room-bstation-1',
      code: 'WP8888',
      title: 'Bstation Room',
      hostId: 'tester-1',
      hostName: 'Tester',
      isPublic: true,
      currentMediaType: 'bstation',
      currentMediaUrl: 'https://www.bilibili.tv/id/video/2048573920',
      livekitRoomName: 'room_WP8888',
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

    testWidgets('Renders detected Bstation quality options and selects 720p on tap', (tester) async {
      await player.loadMedia(
        'bstation',
        'https://www.bilibili.tv/id/video/2048573920',
        autoPlay: false,
      );

      // Simulate Bstation bridge detecting 3 exact resolutions for this video
      player.bstationController?.handleBridgeMessageForTesting(jsonEncode({
        'event': 'qualities',
        'qualities': [
          {'id': '720', 'height': 720, 'label': '720p HD'},
          {'id': '480', 'height': 480, 'label': '480p Standar'},
          {'id': '360', 'height': 360, 'label': '360p Hemat'},
        ],
      }));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => VideoQualitySheet.show(context, player: player),
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      // Tap button to open sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Verify Bstation quality sheet header, platform badge, and count badge
      expect(find.text('Kualitas Video'), findsOneWidget);
      expect(find.text('Bstation'), findsOneWidget);
      expect(find.text('3 resolusi tersedia'), findsOneWidget);

      // Verify detected Bstation quality choices are visible
      expect(find.text('Auto (Otomatis Bstation)'), findsOneWidget);
      expect(find.text('720p HD'), findsOneWidget);
      expect(find.text('480p Standar'), findsOneWidget);
      expect(find.text('360p Hemat'), findsOneWidget);

      // Tap on 720p option
      await tester.tap(find.text('720p HD'));
      await tester.pumpAndSettle();

      // Controller should now have 720p selected
      expect(player.selectedQuality?.id, equals('720'));
      expect(player.currentQualityLabel, equals('720p'));
    });
  });
}
