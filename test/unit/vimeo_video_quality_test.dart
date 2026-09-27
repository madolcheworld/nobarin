import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/controllers/vimeo_player_controller.dart';
import 'package:nobarin/features/room/models/video_quality.dart';
import 'package:nobarin/features/room/presentation/widgets/video_quality_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('VimeoPlayerController - Dynamic Video Quality Unit Tests', () {
    late VimeoPlayerController controller;

    setUp(() {
      controller = VimeoPlayerController();
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

    test('2. Updating qualities from bridge populates, sorts and notifies only exact tiers', () {
      List<VideoQuality>? updatedQualities;
      controller.onQualitiesChanged = (qualities) {
        updatedQualities = qualities;
      };

      // Video only has 1080p, 720p, 360p
      controller.handleBridgeMessageForTesting(jsonEncode({
        'event': 'qualities',
        'qualities': ['360p', '1080p', '720p'],
      }));

      expect(controller.availableQualities.length, equals(4)); // Auto + 3 tiers
      expect(controller.availableQualities.first.isAuto, isTrue);
      expect(controller.availableQualities[1].id, equals('1080p'));
      expect(controller.availableQualities[1].height, equals(1080));
      expect(controller.availableQualities[2].id, equals('720p'));
      expect(controller.availableQualities[2].height, equals(720));
      expect(controller.availableQualities[3].id, equals('360p'));
      expect(controller.availableQualities[3].height, equals(360));
      expect(updatedQualities, isNotNull);
      expect(updatedQualities!.length, equals(4));
    });

    test('3. VideoQuality.vimeo factory parses various label formats accurately', () {
      final q1080 = VideoQuality.vimeo('1080p');
      expect(q1080.height, equals(1080));
      expect(q1080.shortLabel, equals('1080p'));
      expect(q1080.badgeDescription, contains('Full HD'));

      final q4k = VideoQuality.vimeo('2160p');
      expect(q4k.height, equals(2160));
      expect(q4k.shortLabel, equals('2160p'));
      expect(q4k.badgeDescription, contains('4K'));

      final q720 = VideoQuality.vimeo('720');
      expect(q720.height, equals(720));
      expect(q720.shortLabel, equals('720p'));
      expect(q720.badgeDescription, contains('HD'));
    });

    test('4. Timeupdate and resolution events update position, duration, and detected dimensions', () {
      double? pos;
      double? dur;
      controller.onPositionChanged = (p) => pos = p;
      controller.onDurationChanged = (d) => dur = d;

      controller.handleBridgeMessageForTesting(jsonEncode({
        'event': 'timeupdate',
        'data': {
          'seconds': 45.5,
          'duration': 180.0,
        },
      }));

      expect(controller.position, equals(45.5));
      expect(controller.duration, equals(180.0));
      expect(pos, equals(45.5));
      expect(dur, equals(180.0));

      controller.handleBridgeMessageForTesting(jsonEncode({
        'event': 'resolution',
        'width': 1920,
        'height': 1080,
      }));

      expect(controller.detectedWidth, equals(1920));
      expect(controller.detectedHeight, equals(1080));
    });
  });

  group('VideoQualitySheet UI Tests for Vimeo', () {
    testWidgets('renders Vimeo quality options with brand badge in bottom sheet', (tester) async {
      final player = UnifiedPlayerController();
      addTearDown(() => player.dispose());

      await player.loadMedia('vimeo', 'https://vimeo.com/76979871');
      player.vimeoController?.handleBridgeMessageForTesting(jsonEncode({
        'event': 'qualities',
        'qualities': ['1080p', '720p', '360p'],
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

      // Open sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Kualitas Video'), findsOneWidget);
      expect(find.text('Vimeo'), findsOneWidget);
      expect(find.text('1080p'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);
      expect(find.text('FHD'), findsOneWidget);
      expect(find.text('Full HD'), findsOneWidget);
    });
  });
}
