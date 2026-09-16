import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('UnifiedPlayerController Unit Tests', () {
    test('detectMediaFromUrl detects direct video URL correctly', () {
      final detected = UnifiedPlayerController.detectMediaFromUrl(
        'https://example.com/videos/sample.mp4',
      );
      expect(detected, isNotNull);
      expect(detected!.mediaType, equals('direct_url'));
      expect(
          detected.mediaUrl, equals('https://example.com/videos/sample.mp4'));
      expect(detected.title, equals('sample.mp4'));
      expect(detected.isDirectUrl, isTrue);

      expect(UnifiedPlayerController.detectMediaFromUrl(''), isNull);
      expect(UnifiedPlayerController.detectMediaFromUrl('invalid_url'), isNull);
    });

    test('loadMedia loads direct media URL and updates properties', () async {
      final controller = UnifiedPlayerController();
      addTearDown(() => controller.dispose());

      await controller.loadMedia(
        'direct_url',
        'https://example.com/movie.mp4',
        autoPlay: false,
      );

      expect(controller.mediaType, equals('direct_url'));
      expect(controller.mediaUrl, equals('https://example.com/movie.mp4'));
      expect(controller.hasMedia, isTrue);
    });

    test('clearError resets errorMessage to null and notifies listeners', () {
      final controller = UnifiedPlayerController();
      addTearDown(() => controller.dispose());

      int notifyCount = 0;
      controller.addListener(() {
        notifyCount++;
      });

      controller.clearError();
      expect(controller.errorMessage, isNull);
      expect(notifyCount, equals(1));
    });

    test('toggleMute toggles muted state and adjusts volume', () async {
      final controller = UnifiedPlayerController();
      addTearDown(() => controller.dispose());

      expect(controller.isMuted, isFalse);

      await controller.toggleMute();
      expect(controller.isMuted, isTrue);

      await controller.toggleMute();
      expect(controller.isMuted, isFalse);
    });

    test(
        'enterFullscreen, exitFullscreen, and toggleFullscreen update state and notify listeners',
        () async {
      final controller = UnifiedPlayerController();
      addTearDown(() => controller.dispose());

      expect(controller.isFullscreen, isFalse);

      int notifyCount = 0;
      controller.addListener(() {
        notifyCount++;
      });

      await controller.enterFullscreen();
      expect(controller.isFullscreen, isTrue);
      expect(notifyCount, greaterThanOrEqualTo(1));

      // Re-entering fullscreen when already in fullscreen does nothing
      final prevCount = notifyCount;
      await controller.enterFullscreen();
      expect(controller.isFullscreen, isTrue);
      expect(notifyCount, equals(prevCount));

      await controller.exitFullscreen();
      expect(controller.isFullscreen, isFalse);
      expect(notifyCount, greaterThan(prevCount));

      // Toggle fullscreen
      await controller.toggleFullscreen();
      expect(controller.isFullscreen, isTrue);

      await controller.toggleFullscreen();
      expect(controller.isFullscreen, isFalse);
    });

    test('detectMediaFromUrl detects YouTube URLs correctly', () {
      final detectedWatch = UnifiedPlayerController.detectMediaFromUrl(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(detectedWatch, isNotNull);
      expect(detectedWatch!.mediaType, equals('youtube'));
      expect(detectedWatch.mediaId, equals('dQw4w9WgXcQ'));
      expect(detectedWatch.isYoutube, isTrue);
      expect(detectedWatch.thumbnailUrl, contains('dQw4w9WgXcQ'));

      final detectedShorts = UnifiedPlayerController.detectMediaFromUrl(
        'https://m.youtube.com/shorts/dQw4w9WgXcQ',
      );
      expect(detectedShorts, isNotNull);
      expect(detectedShorts!.mediaType, equals('youtube'));
      expect(detectedShorts.mediaId, equals('dQw4w9WgXcQ'));

      final detectedShortUrl = UnifiedPlayerController.detectMediaFromUrl(
        'https://youtu.be/dQw4w9WgXcQ',
      );
      expect(detectedShortUrl, isNotNull);
      expect(detectedShortUrl!.mediaType, equals('youtube'));
      expect(detectedShortUrl.mediaId, equals('dQw4w9WgXcQ'));
    });
  });
}
