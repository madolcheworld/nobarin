import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/room/controllers/vimeo_player_controller.dart';
import 'package:nobarin/features/room/controllers/vimeo_web_adapter/vimeo_web_adapter.dart';
import 'package:nobarin/features/room/presentation/widgets/vimeo_player_widget.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('VimeoWebAdapter Interface & Stub Tests', () {
    test('VimeoWebAdapter.isSupported is false on VM/Desktop test platform', () {
      expect(VimeoWebAdapter.isSupported, isFalse);
    });

    test('VimeoWebAdapter.create returns null gracefully on non-web platform', () {
      final adapter = VimeoWebAdapter.create(
        onPositionChanged: (_) {},
        onDurationChanged: (_) {},
        onPlayingChanged: (_) {},
        onPlaybackEnded: () {},
        onError: (_) {},
      );
      expect(adapter, isNull);
    });
  });

  group('VimeoPlayerController Web Integration & URL Extraction Tests', () {
    test('buildWebWidget returns null when not running on Web or before load', () {
      final controller = VimeoPlayerController();
      expect(controller.buildWebWidget(), isNull);
      expect(controller.webAdapter, isNull);
      controller.dispose();
    });

    test('extractVideoId accurately parses all Vimeo URL shapes', () {
      // Standard video URL
      expect(
        VimeoPlayerController.extractVideoId('https://vimeo.com/76979871'),
        equals('76979871'),
      );
      // Channels URL
      expect(
        VimeoPlayerController.extractVideoId('https://vimeo.com/channels/staffpicks/76979871'),
        equals('76979871'),
      );
      // Groups URL
      expect(
        VimeoPlayerController.extractVideoId('https://vimeo.com/groups/motion/videos/76979871'),
        equals('76979871'),
      );
      // Player embed URL
      expect(
        VimeoPlayerController.extractVideoId('https://player.vimeo.com/video/76979871'),
        equals('76979871'),
      );
      // Unlisted path URL
      expect(
        VimeoPlayerController.extractVideoId('https://vimeo.com/76979871/abcdef1234'),
        equals('76979871'),
      );
      // Direct video ID
      expect(
        VimeoPlayerController.extractVideoId('76979871'),
        equals('76979871'),
      );
      // Empty or invalid URL
      expect(
        VimeoPlayerController.extractVideoId(''),
        isNull,
      );
      expect(
        VimeoPlayerController.extractVideoId('https://example.com/video/76979871'),
        isNull,
      );
    });

    test('extractUnlistedHash accurately parses Vimeo privacy hashes', () {
      // Path based privacy hash
      expect(
        VimeoPlayerController.extractUnlistedHash('https://vimeo.com/76979871/abcdef1234'),
        equals('abcdef1234'),
      );
      // Query parameter based privacy hash
      expect(
        VimeoPlayerController.extractUnlistedHash('https://player.vimeo.com/video/76979871?h=abcdef1234'),
        equals('abcdef1234'),
      );
      // Standard public URL (no hash)
      expect(
        VimeoPlayerController.extractUnlistedHash('https://vimeo.com/76979871'),
        isNull,
      );
    });
  });

  group('VimeoPlayerWidget Rendering Tests', () {
    testWidgets('renders loading state when WebViewController is null', (tester) async {
      final controller = VimeoPlayerController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VimeoPlayerWidget(controller: controller),
          ),
        ),
      );

      expect(find.byType(VimeoPlayerWidget), findsOneWidget);
      expect(find.text('Memuat Pemutar Vimeo...'), findsOneWidget);

      controller.dispose();
    });
  });
}
