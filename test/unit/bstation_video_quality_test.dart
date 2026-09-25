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

  group('BstationPlayerController - Video Quality Unit Tests', () {
    late BstationPlayerController controller;

    setUp(() {
      controller = BstationPlayerController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('1. Default available qualities and initial auto state', () {
      expect(controller.availableQualities, isNotEmpty);
      expect(controller.availableQualities.length, equals(4));

      // 1st is Auto
      final autoQ = controller.availableQualities[0];
      expect(autoQ.isAuto, isTrue);
      expect(autoQ.id, equals('auto'));
      expect(autoQ.shortLabel, equals('Auto'));
      expect(autoQ.mode, equals(QualityControlMode.webviewBridge));

      // 2nd is 720p
      final q720 = controller.availableQualities[1];
      expect(q720.id, equals('720'));
      expect(q720.height, equals(720));
      expect(q720.shortLabel, equals('720p'));
      expect(q720.badgeDescription, equals('HD Resolusi Tinggi'));

      // 3rd is 480p
      final q480 = controller.availableQualities[2];
      expect(q480.id, equals('480'));
      expect(q480.height, equals(480));
      expect(q480.shortLabel, equals('480p'));

      // 4th is 360p
      final q360 = controller.availableQualities[3];
      expect(q360.id, equals('360'));
      expect(q360.height, equals(360));
      expect(q360.shortLabel, equals('360p'));
    });

    test('2. setQuality switches quality, notifies listeners, and calls callbacks', () async {
      VideoQuality? selectedCallbackQuality;
      var notifyCount = 0;

      controller.onQualitySelectedChanged = (quality) {
        selectedCallbackQuality = quality;
      };
      controller.addListener(() {
        notifyCount++;
      });

      // Switch to 720p
      await controller.setQuality('720');
      expect(controller.selectedQuality?.id, equals('720'));
      expect(controller.selectedQuality?.height, equals(720));
      expect(selectedCallbackQuality?.id, equals('720'));
      expect(notifyCount, greaterThan(0));

      // Switch to 480p
      await controller.setQuality('480');
      expect(controller.selectedQuality?.id, equals('480'));
      expect(controller.selectedQuality?.height, equals(480));
      expect(selectedCallbackQuality?.id, equals('480'));

      // Switch to 360p
      await controller.setQuality('360');
      expect(controller.selectedQuality?.id, equals('360'));
      expect(controller.selectedQuality?.height, equals(360));
      expect(selectedCallbackQuality?.id, equals('360'));

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

    test('4. Bridge message "resolution" updates detected height & width', () {
      var notified = false;
      controller.addListener(() => notified = true);

      controller.handleBridgeMessageForTesting(jsonEncode({
        'event': 'resolution',
        'height': 720,
        'width': 1280,
      }));

      expect(controller.detectedHeight, equals(720));
      expect(controller.detectedWidth, equals(1280));
      expect(notified, isTrue);
    });

    test('5. Bridge message "qualitychange" updates selected quality', () {
      VideoQuality? callbackQuality;
      controller.onQualitySelectedChanged = (q) => callbackQuality = q;

      controller.handleBridgeMessageForTesting(jsonEncode({
        'event': 'qualitychange',
        'quality': '480',
      }));

      expect(controller.selectedQuality?.id, equals('480'));
      expect(callbackQuality?.id, equals('480'));
    });

    test('6. Bridge message "qualities" updates dynamic available qualities from page', () {
      List<VideoQuality>? updatedQualities;
      controller.onQualitiesChanged = (qualities) => updatedQualities = qualities;

      controller.handleBridgeMessageForTesting(jsonEncode({
        'event': 'qualities',
        'qualities': [
          {'id': '1080', 'height': 1080, 'label': '1080p Full HD'},
          {'id': '720', 'height': 720, 'label': '720p HD'},
          {'id': '480', 'height': 480, 'label': '480p Standar'},
        ],
      }));

      expect(controller.availableQualities.length, equals(4)); // Auto + 1080 + 720 + 480
      expect(controller.availableQualities.first.isAuto, isTrue);
      expect(controller.availableQualities[1].id, equals('1080'));
      expect(controller.availableQualities[1].label, equals('1080p Full HD'));
      expect(updatedQualities, isNotNull);
      expect(updatedQualities!.any((q) => q.id == '1080'), isTrue);
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

    test('1. Bstation media loading configures quality support and labels', () async {
      await player.loadMedia(
        'bstation',
        'https://www.bilibili.tv/id/video/2048573920',
        autoPlay: false,
      );

      expect(player.mediaType, equals('bstation'));
      expect(player.supportsQualitySelection, isTrue);
      expect(player.availableQualities, isNotEmpty);
      expect(player.availableQualities.any((q) => q.isAuto), isTrue);
      expect(player.availableQualities.any((q) => q.id == '720'), isTrue);
      expect(player.availableQualities.any((q) => q.id == '480'), isTrue);
      expect(player.availableQualities.any((q) => q.id == '360'), isTrue);

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
    });

    test('2. Changing video quality updates selected state and currentQualityLabel', () async {
      await player.loadMedia(
        'bstation',
        'https://www.bilibili.tv/id/video/2048573920',
        autoPlay: false,
      );

      final q720 = player.availableQualities.firstWhere((q) => q.id == '720');
      await player.setVideoQuality(q720);

      expect(player.selectedQuality?.id, equals('720'));
      expect(player.currentQualityLabel, equals('720p'));

      final q480 = player.availableQualities.firstWhere((q) => q.id == '480');
      await player.setVideoQuality(q480);

      expect(player.selectedQuality?.id, equals('480'));
      expect(player.currentQualityLabel, equals('480p'));

      // Switch back to Auto
      final autoQ = player.availableQualities.firstWhere((q) => q.isAuto);
      await player.setVideoQuality(autoQ);

      expect(player.selectedQuality?.isAuto, isTrue);
    });

    test('3. Dynamic qualities event from Bstation bridge updates UnifiedPlayerController', () async {
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

      expect(player.availableQualities.any((q) => q.id == '1080'), isTrue);
      expect(player.availableQualities.firstWhere((q) => q.id == '1080').label, equals('1080p FHD'));
      expect(player.maxDetectedHeight, equals(1080));
      expect(player.maxResolutionLabel, equals('Full HD (1080p)'));
    });

    test('4. Stream resolution > default max auto-expands Bstation available quality tiers', () async {
      await player.loadMedia(
        'bstation',
        'https://www.bilibili.tv/id/video/2048573920',
        autoPlay: false,
      );

      // Before explicit qualities list, if <video> reports 1080p (or 1080x1920 vertical)
      player.bstationController?.handleBridgeMessageForTesting(jsonEncode({
        'event': 'resolution',
        'height': 1920,
        'width': 1080,
      }));

      expect(player.bstationController?.detectedHeight, equals(1080));
      expect(player.availableQualities.any((q) => q.id == '1080'), isTrue);
      expect(player.maxDetectedHeight, equals(1080));
      expect(player.maxResolutionLabel, equals('Full HD (1080p)'));
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

    testWidgets('Renders Bstation quality options and selects 720p on tap', (tester) async {
      await player.loadMedia(
        'bstation',
        'https://www.bilibili.tv/id/video/2048573920',
        autoPlay: false,
      );

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

      // Verify Bstation quality sheet header and platform badge
      expect(find.text('Kualitas Video'), findsOneWidget);
      expect(find.text('Bstation'), findsOneWidget);

      // Verify all Bstation quality choices are visible
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
