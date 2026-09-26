import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/room/controllers/dailymotion_player_controller.dart';
import 'package:nobarin/features/room/controllers/dailymotion_web_adapter/dailymotion_web_adapter.dart';
import 'package:nobarin/features/room/presentation/widgets/dailymotion_player_widget.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('DailymotionWebAdapter Interface & Stub Tests', () {
    test('DailymotionWebAdapter.isSupported is false on VM/Desktop test platform', () {
      expect(DailymotionWebAdapter.isSupported, isFalse);
    });

    test('DailymotionWebAdapter.create returns null gracefully on non-web platform', () {
      final adapter = DailymotionWebAdapter.create(
        onPositionChanged: (_) {},
        onDurationChanged: (_) {},
        onPlayingChanged: (_) {},
        onPlaybackEnded: () {},
        onError: (_) {},
      );
      expect(adapter, isNull);
    });
  });

  group('DailymotionPlayerController Web Integration Tests', () {
    test('buildWebWidget returns null when not running on Web or before load', () {
      final controller = DailymotionPlayerController();
      expect(controller.buildWebWidget(), isNull);
      expect(controller.webAdapter, isNull);
      controller.dispose();
    });

    test('extractVideoId accurately parses all Dailymotion URL variations', () {
      // Standard video URL
      expect(
        DailymotionPlayerController.extractVideoId('https://www.dailymotion.com/video/x913q9y'),
        equals('x913q9y'),
      );
      // Short dai.ly URL
      expect(
        DailymotionPlayerController.extractVideoId('https://dai.ly/x913q9y'),
        equals('x913q9y'),
      );
      // Embed player URL
      expect(
        DailymotionPlayerController.extractVideoId('https://geo.dailymotion.com/player.html?video=x913q9y'),
        equals('x913q9y'),
      );
      // Direct video ID
      expect(
        DailymotionPlayerController.extractVideoId('x913q9y'),
        equals('x913q9y'),
      );
      // Empty or invalid URL
      expect(
        DailymotionPlayerController.extractVideoId(''),
        isNull,
      );
    });
  });

  group('DailymotionPlayerWidget Rendering Tests', () {
    testWidgets('renders loading state when WebViewController is null', (tester) async {
      final controller = DailymotionPlayerController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailymotionPlayerWidget(controller: controller),
          ),
        ),
      );

      expect(find.byType(DailymotionPlayerWidget), findsOneWidget);
      expect(find.text('Memuat Pemutar Dailymotion...'), findsOneWidget);

      controller.dispose();
    });
  });
}
