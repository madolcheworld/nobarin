import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/room/controllers/dailymotion_player_controller.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/models/video_quality.dart';

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

    test('detectMediaFromUrl detects Dailymotion URLs correctly', () {
      final detectedStandard = UnifiedPlayerController.detectMediaFromUrl(
        'https://www.dailymotion.com/video/x7tgad0',
      );
      expect(detectedStandard, isNotNull);
      expect(detectedStandard!.mediaType, equals('dailymotion'));
      expect(detectedStandard.mediaId, equals('x7tgad0'));
      expect(detectedStandard.isDailymotion, isTrue);
      expect(detectedStandard.thumbnailUrl,
          equals('https://www.dailymotion.com/thumbnail/video/x7tgad0'));

      final detectedShort = UnifiedPlayerController.detectMediaFromUrl(
        'https://dai.ly/x7tgad0',
      );
      expect(detectedShort, isNotNull);
      expect(detectedShort!.mediaType, equals('dailymotion'));
      expect(detectedShort.mediaId, equals('x7tgad0'));
      expect(detectedShort.isDailymotion, isTrue);

      final detectedEmbed = UnifiedPlayerController.detectMediaFromUrl(
        'https://geo.dailymotion.com/player.html?video=x7tgad0',
      );
      expect(detectedEmbed, isNotNull);
      expect(detectedEmbed!.mediaType, equals('dailymotion'));
      expect(detectedEmbed.mediaId, equals('x7tgad0'));
      expect(detectedEmbed.isDailymotion, isTrue);
    });

    test(
        'extractVideoId in DailymotionPlayerController handles various URL shapes',
        () {
      expect(DailymotionPlayerController.extractVideoId(
              'https://www.dailymotion.com/video/x8xyz12'),
          'x8xyz12');
      expect(DailymotionPlayerController.extractVideoId(
              'https://dai.ly/x8xyz12'),
          'x8xyz12');
      expect(
          DailymotionPlayerController.extractVideoId(
              'https://geo.dailymotion.com/player.html?video=x8xyz12'),
          'x8xyz12');
      expect(
          DailymotionPlayerController.extractVideoId(
              'https://www.dailymotion.com/embed/video/x8xyz12'),
          'x8xyz12');
      expect(DailymotionPlayerController.extractVideoId('x8xyz12'), 'x8xyz12');
      expect(DailymotionPlayerController.extractVideoId('invalid url'), isNull);
    });

    test('VideoQuality model handles multiple modes and formats labels', () {
      const autoQuality = VideoQuality.auto();
      expect(autoQuality.isAuto, isTrue);
      expect(autoQuality.shortLabel, equals('Auto'));
      expect(autoQuality.badgeDescription, contains('koneksi'));

      final bstationHd = VideoQuality.bstation(
        id: '720',
        label: '720p (HD)',
        height: 720,
      );
      expect(bstationHd.mode, equals(QualityControlMode.webviewBridge));
      expect(bstationHd.shortLabel, equals('720p'));
      expect(bstationHd.badgeDescription, contains('HD'));

      final dmFhd = VideoQuality.dailymotion('1080');
      expect(dmFhd.mode, equals(QualityControlMode.webviewBridge));
      expect(dmFhd.height, equals(1080));
      expect(dmFhd.shortLabel, equals('1080p'));

      final fixedOriginal = VideoQuality.fixed(
        height: 1080,
        width: 1920,
      );
      expect(fixedOriginal.mode, equals(QualityControlMode.fixedOriginal));
      expect(fixedOriginal.shortLabel, equals('1080p (Asli)'));
      expect(fixedOriginal.badgeDescription, contains('efisien'));
    });

    test('UnifiedPlayerController supportsQualitySelection handles each media source', () async {
      final controller = UnifiedPlayerController();
      addTearDown(() => controller.dispose());

      // Direct URL
      await controller.loadMedia('direct_url', 'https://example.com/live.m3u8');
      expect(controller.supportsQualitySelection, isTrue);

      // Local file
      await controller.loadMedia('direct_url', '/sdcard/Download/movie.mp4');
      expect(controller.isLocalFile, isTrue);
      expect(controller.supportsQualitySelection, isFalse);
      expect(controller.currentQualityLabel, contains('Asli'));

      // P2P stream
      await controller.loadMedia('direct_url', 'p2p://room123/video.mp4');
      expect(controller.isP2PStream, isTrue);
      expect(controller.supportsQualitySelection, isFalse);

      // YouTube
      await controller.loadMedia('youtube', 'https://youtu.be/dQw4w9WgXcQ');
      expect(controller.supportsQualitySelection, isFalse);

      // Dailymotion
      await controller.loadMedia('dailymotion', 'https://dai.ly/x7tgad0');
      expect(controller.supportsQualitySelection, isTrue);
    });
  });
}
