import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/room/controllers/dailymotion_player_controller.dart';
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

  group('DailymotionPlayerController - Video Quality Unit Tests', () {
    late DailymotionPlayerController controller;

    setUp(() {
      controller = DailymotionPlayerController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('1. Default available qualities and initial auto state', () {
      expect(controller.availableQualities, isNotEmpty);
      expect(controller.availableQualities.length, equals(6));

      // Initially Auto
      final autoQ = controller.availableQualities[0];
      expect(autoQ.isAuto, isTrue);
      expect(autoQ.id, equals('auto'));
      expect(autoQ.shortLabel, equals('Auto'));
      expect(autoQ.mode, equals(QualityControlMode.webviewBridge));
      expect(controller.selectedQuality?.isAuto, isTrue);

      // Default presets present
      expect(controller.availableQualities[1].id, equals('1080'));
      expect(controller.availableQualities[2].id, equals('720'));
      expect(controller.availableQualities[3].id, equals('480'));
      expect(controller.availableQualities[4].id, equals('360'));
      expect(controller.availableQualities[5].id, equals('240'));
    });

    test('2. Updating qualities from bridge populates, sorts and notifies', () {
      List<VideoQuality>? updatedQualities;
      controller.onQualitiesChanged = (qualities) {
        updatedQualities = qualities;
      };

      controller.handleBridgeMessageForTesting(jsonEncode({
        'event': 'qualities',
        'qualities': ['240', '1080', '480', '720', '360'],
      }));

      expect(controller.availableQualities.length, equals(6)); // Auto + 5 tiers
      expect(controller.availableQualities.first.isAuto, isTrue);
      expect(controller.availableQualities[1].id, equals('1080'));
      expect(controller.availableQualities[1].height, equals(1080));
      expect(controller.availableQualities[2].id, equals('720'));
      expect(controller.availableQualities[3].id, equals('480'));
      expect(controller.availableQualities[4].id, equals('360'));
      expect(controller.availableQualities[5].id, equals('240'));
      expect(updatedQualities, isNotNull);
      expect(updatedQualities!.length, equals(6));
    });

    test('3. setQuality switches quality, notifies listeners, and calls callbacks', () async {
      // First populate qualities
      controller.handleBridgeMessageForTesting(jsonEncode({
        'event': 'qualities',
        'qualities': ['1080', '720', '480', '360', '240'],
      }));

      VideoQuality? selectedCallbackQuality;
      var notifyCount = 0;

      controller.onQualitySelectedChanged = (quality) {
        selectedCallbackQuality = quality;
      };
      controller.addListener(() {
        notifyCount++;
      });

      // Switch to 1080p
      await controller.setQuality('1080');
      expect(controller.selectedQuality?.id, equals('1080'));
      expect(controller.selectedQuality?.height, equals(1080));
      expect(selectedCallbackQuality?.id, equals('1080'));
      expect(notifyCount, greaterThan(0));

      // Switch to 720p
      await controller.setQuality('720');
      expect(controller.selectedQuality?.id, equals('720'));
      expect(controller.selectedQuality?.height, equals(720));
      expect(selectedCallbackQuality?.id, equals('720'));

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

    test('4. setQuality handles custom/unknown quality fallback gracefully', () async {
      await controller.setQuality('customQuality');
      expect(controller.selectedQuality?.id, equals('customQuality'));
      expect(controller.selectedQuality?.mode, equals(QualityControlMode.webviewBridge));
    });

    test('5. Bridge message "resolution" updates detected height & width', () {
      var notified = false;
      controller.addListener(() => notified = true);

      controller.handleBridgeMessageForTesting(jsonEncode({
        'event': 'resolution',
        'height': 1080,
        'width': 1920,
      }));

      expect(controller.detectedHeight, equals(1080));
      expect(controller.detectedWidth, equals(1920));
      expect(notified, isTrue);
    });

    test('6. Bridge message "qualitychange" updates selected quality', () {
      // First populate qualities
      controller.handleBridgeMessageForTesting(jsonEncode({
        'event': 'qualities',
        'qualities': ['1080', '720', '480', '360'],
      }));

      VideoQuality? callbackQuality;
      controller.onQualitySelectedChanged = (q) => callbackQuality = q;

      controller.handleBridgeMessageForTesting(jsonEncode({
        'event': 'qualitychange',
        'quality': '720',
      }));

      expect(controller.selectedQuality?.id, equals('720'));
      expect(callbackQuality?.id, equals('720'));
    });

    test('7. Bridge message "qualities" with map objects handles attributes cleanly', () {
      controller.handleBridgeMessageForTesting(jsonEncode({
        'event': 'qualities',
        'qualities': [
          {'id': '1080p', 'quality': '1080'},
          {'id': '720p', 'quality': '720'},
        ],
      }));

      expect(controller.availableQualities.length, equals(3)); // Auto + 1080 + 720
      expect(controller.availableQualities.first.isAuto, isTrue);
      expect(controller.availableQualities[1].height, equals(1080));
      expect(controller.availableQualities[2].height, equals(720));
    });
  });

  group('UnifiedPlayerController - Dailymotion Quality Integration Tests', () {
    late UnifiedPlayerController player;

    setUp(() {
      player = UnifiedPlayerController();
    });

    tearDown(() {
      player.dispose();
    });

    test('1. Dailymotion media loading configures quality support and labels', () async {
      await player.loadMedia(
        'dailymotion',
        'https://www.dailymotion.com/video/x84sh87',
        autoPlay: false,
      );

      expect(player.mediaType, equals('dailymotion'));
      expect(player.supportsQualitySelection, isTrue);
      expect(player.availableQualities, isNotEmpty);
      expect(player.availableQualities.any((q) => q.isAuto), isTrue);
      expect(player.availableQualities.any((q) => q.id == '1080'), isTrue);
      expect(player.availableQualities.any((q) => q.id == '720'), isTrue);
      expect(player.availableQualities.any((q) => q.id == '480'), isTrue);
      expect(player.availableQualities.any((q) => q.id == '360'), isTrue);
      expect(player.availableQualities.any((q) => q.id == '240'), isTrue);

      // Initially Auto without resolution
      expect(player.currentQualityLabel, equals('Auto'));

      // Simulate stream reporting 1080p resolution
      player.dailymotionController?.handleBridgeMessageForTesting(jsonEncode({
        'event': 'resolution',
        'height': 1080,
        'width': 1920,
      }));

      // In Auto mode, label reflects detected stream height
      expect(player.currentQualityLabel, equals('Auto (1080p)'));
    });

    test('2. Changing video quality updates selected state and currentQualityLabel', () async {
      await player.loadMedia(
        'dailymotion',
        'https://www.dailymotion.com/video/x84sh87',
        autoPlay: false,
      );

      final q1080 = player.availableQualities.firstWhere((q) => q.id == '1080');
      await player.setVideoQuality(q1080);

      expect(player.selectedQuality?.id, equals('1080'));
      expect(player.currentQualityLabel, equals('1080p'));

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

    test('3. Dynamic qualities event from Dailymotion bridge updates UnifiedPlayerController', () async {
      await player.loadMedia(
        'dailymotion',
        'https://www.dailymotion.com/video/x84sh87',
        autoPlay: false,
      );

      player.dailymotionController?.handleBridgeMessageForTesting(jsonEncode({
        'event': 'qualities',
        'qualities': ['1080', '720', '360'],
      }));

      expect(player.availableQualities.length, equals(4)); // Auto + 3
      expect(player.availableQualities.any((q) => q.id == '1080'), isTrue);
      expect(player.availableQualities.any((q) => q.id == '720'), isTrue);
      expect(player.availableQualities.any((q) => q.id == '360'), isTrue);
      expect(player.availableQualities.any((q) => q.id == '240'), isFalse);
    });
  });

  group('VideoQualitySheet - Dailymotion UI Quality Selection Tests', () {
    late UnifiedPlayerController player;
    late SyncController syncController;

    const testUser = UserProfile(
      id: 'tester-1',
      username: 'Tester',
      avatarUrl: '🚀',
    );

    final testRoom = RoomModel(
      id: 'room-dm-1',
      code: 'WP9999',
      title: 'Dailymotion Room',
      hostId: 'tester-1',
      hostName: 'Tester',
      isPublic: true,
      currentMediaType: 'dailymotion',
      currentMediaUrl: 'https://www.dailymotion.com/video/x84sh87',
      livekitRoomName: 'room_WP9999',
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

    testWidgets('Renders Dailymotion quality options and selects 720p on tap', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await player.loadMedia(
        'dailymotion',
        'https://www.dailymotion.com/video/x84sh87',
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

      // Verify Dailymotion quality sheet header and platform badge
      expect(find.text('Kualitas Video'), findsOneWidget);
      expect(find.text('Dailymotion'), findsOneWidget);

      // Verify Dailymotion quality choices are visible
      expect(find.text('Auto (Otomatis Dailymotion)'), findsOneWidget);
      expect(find.text('1080p'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);
      expect(find.text('480p'), findsOneWidget);
      expect(find.text('360p'), findsOneWidget);
      expect(find.text('240p'), findsOneWidget);

      // Tap on 720p option
      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();

      // Controller should now have 720p selected
      expect(player.selectedQuality?.id, equals('720'));
      expect(player.currentQualityLabel, equals('720p'));
    });
  });
}
