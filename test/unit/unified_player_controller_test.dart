import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:watch_party/features/room/controllers/unified_player_controller.dart';

class FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return FakePlatformNavigationDelegate(params);
  }

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return FakePlatformWebViewController(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return FakePlatformWebViewWidget(params);
  }
}

class FakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  FakePlatformNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback onNavigationRequest) async {}

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback onWebResourceError) async {}
}

class FakePlatformWebViewController extends PlatformWebViewController {
  FakePlatformWebViewController(super.params) : super.implementation();

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(PlatformNavigationDelegate handler) async {}

  @override
  Future<void> setUserAgent(String? userAgent) async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams javaScriptChannelParams) async {}

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {}

  @override
  Future<void> enableZoom(bool enabled) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {}

  @override
  Future<void> runJavaScript(String javaScript) async {}

  @override
  Future<String> runJavaScriptReturningResult(String javaScript) async => '';
}

class FakePlatformWebViewWidget extends PlatformWebViewWidget {
  FakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    WebViewPlatform.instance = FakeWebViewPlatform();
  });

  group('UnifiedPlayerController Unit Tests', () {
    test('extractYouTubeVideoId extracts video ID across various formats', () {
      // Standard watch URL
      expect(
        UnifiedPlayerController.extractYouTubeVideoId(
            'https://www.youtube.com/watch?v=aqz-KE-bpKQ'),
        equals('aqz-KE-bpKQ'),
      );

      // youtu.be short URL
      expect(
        UnifiedPlayerController.extractYouTubeVideoId(
            'https://youtu.be/aqz-KE-bpKQ'),
        equals('aqz-KE-bpKQ'),
      );

      // Shorts URL
      expect(
        UnifiedPlayerController.extractYouTubeVideoId(
            'https://www.youtube.com/shorts/aqz-KE-bpKQ'),
        equals('aqz-KE-bpKQ'),
      );

      // Live URL
      expect(
        UnifiedPlayerController.extractYouTubeVideoId(
            'https://www.youtube.com/live/aqz-KE-bpKQ'),
        equals('aqz-KE-bpKQ'),
      );

      // Embed URL
      expect(
        UnifiedPlayerController.extractYouTubeVideoId(
            'https://www.youtube.com/embed/aqz-KE-bpKQ'),
        equals('aqz-KE-bpKQ'),
      );

      // YouTube nocookie embed URL
      expect(
        UnifiedPlayerController.extractYouTubeVideoId(
            'https://www.youtube-nocookie.com/embed/aqz-KE-bpKQ'),
        equals('aqz-KE-bpKQ'),
      );

      // Raw 11-character video ID
      expect(
        UnifiedPlayerController.extractYouTubeVideoId('aqz-KE-bpKQ'),
        equals('aqz-KE-bpKQ'),
      );

      // URL with query parameters before or after v=
      expect(
        UnifiedPlayerController.extractYouTubeVideoId(
            'https://www.youtube.com/watch?feature=shared&v=aqz-KE-bpKQ&t=12s'),
        equals('aqz-KE-bpKQ'),
      );

      // Non-YouTube URLs or invalid strings
      expect(
        UnifiedPlayerController.extractYouTubeVideoId(
            'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4'),
        isNull,
      );
      expect(
        UnifiedPlayerController.extractYouTubeVideoId(''),
        isNull,
      );
      expect(
        UnifiedPlayerController.extractYouTubeVideoId('not_a_valid_id'),
        isNull,
      );
    });

    test('loadMedia auto-detects YouTube URL even when direct_url type is passed',
        () async {
      final controller = UnifiedPlayerController();
      addTearDown(() => controller.dispose());

      await controller.loadMedia(
        'direct_url',
        'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
        autoPlay: false,
      );

      // Should automatically route to YouTube
      expect(controller.mediaType, equals('youtube'));
      expect(controller.mediaUrl,
          equals('https://www.youtube.com/watch?v=aqz-KE-bpKQ'));
    });

    test('loadMedia auto-detects direct media URL even when youtube type is passed',
        () async {
      final controller = UnifiedPlayerController();
      addTearDown(() => controller.dispose());

      await controller.loadMedia(
        'youtube',
        'https://example.com/movie.mp4',
        autoPlay: false,
      );

      // Should automatically route to direct_url
      expect(controller.mediaType, equals('direct_url'));
      expect(controller.mediaUrl, equals('https://example.com/movie.mp4'));
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

    test('extractTwitchMedia parses channels, videos, and clips accurately', () {
      // Channel
      final channel = UnifiedPlayerController.extractTwitchMedia(
          'https://www.twitch.tv/monstercat');
      expect(channel, isNotNull);
      expect(channel!.type, equals('channel'));
      expect(channel.id, equals('monstercat'));
      expect(channel.isChannel, isTrue);

      // Video (VOD)
      final video = UnifiedPlayerController.extractTwitchMedia(
          'https://www.twitch.tv/videos/123456789');
      expect(video, isNotNull);
      expect(video!.type, equals('video'));
      expect(video.id, equals('123456789'));
      expect(video.isVideo, isTrue);

      // Clips subdomain
      final clip1 = UnifiedPlayerController.extractTwitchMedia(
          'https://clips.twitch.tv/GloriousTastyApple');
      expect(clip1, isNotNull);
      expect(clip1!.type, equals('clip'));
      expect(clip1.id, equals('GloriousTastyApple'));
      expect(clip1.isClip, isTrue);

      // Channel clip path
      final clip2 = UnifiedPlayerController.extractTwitchMedia(
          'https://www.twitch.tv/ninja/clip/GloriousTastyApple');
      expect(clip2, isNotNull);
      expect(clip2!.type, equals('clip'));
      expect(clip2.id, equals('GloriousTastyApple'));

      // Non-Twitch
      expect(
          UnifiedPlayerController.extractTwitchMedia('https://vimeo.com/76979871'),
          isNull);
      expect(
          UnifiedPlayerController.extractTwitchMedia('https://youtube.com/watch?v=123'),
          isNull);
      expect(UnifiedPlayerController.extractTwitchMedia(''), isNull);
    });

    test('extractVimeoVideoId parses standard, channel, and player URLs', () {
      // Standard
      expect(
        UnifiedPlayerController.extractVimeoVideoId('https://vimeo.com/76979871'),
        equals('76979871'),
      );

      // Channel / Staffpicks
      expect(
        UnifiedPlayerController.extractVimeoVideoId(
            'https://vimeo.com/channels/staffpicks/76979871'),
        equals('76979871'),
      );

      // Player embed
      expect(
        UnifiedPlayerController.extractVimeoVideoId(
            'https://player.vimeo.com/video/76979871'),
        equals('76979871'),
      );

      // Non-Vimeo
      expect(
        UnifiedPlayerController.extractVimeoVideoId(
            'https://www.twitch.tv/monstercat'),
        isNull,
      );
      expect(
        UnifiedPlayerController.extractVimeoVideoId('https://example.com/video.mp4'),
        isNull,
      );
      expect(UnifiedPlayerController.extractVimeoVideoId(''), isNull);
    });

    test('loadMedia auto-detects Twitch and Vimeo URLs', () async {
      final controller = UnifiedPlayerController();
      addTearDown(() => controller.dispose());

      // Twitch auto-detect
      await controller.loadMedia(
        'direct_url',
        'https://www.twitch.tv/monstercat',
        autoPlay: false,
      );
      expect(controller.mediaType, equals('twitch'));
      expect(controller.mediaUrl, equals('https://www.twitch.tv/monstercat'));

      // Vimeo auto-detect
      await controller.loadMedia(
        'youtube',
        'https://vimeo.com/76979871',
        autoPlay: false,
      );
      expect(controller.mediaType, equals('vimeo'));
      expect(controller.mediaUrl, equals('https://vimeo.com/76979871'));
    });

    test('embed player delegates play, pause, seek, and state updates', () async {
      final controller = UnifiedPlayerController();
      addTearDown(() => controller.dispose());

      await controller.loadMedia(
        'twitch',
        'https://www.twitch.tv/monstercat',
        autoPlay: false,
      );

      final List<String> receivedCommands = [];
      controller.onEmbedPlayerCommand = (action, arg) {
        receivedCommands.add('$action:${arg ?? ""}');
      };

      await controller.play();
      expect(receivedCommands, contains('play:'));

      await controller.pause();
      expect(receivedCommands, contains('pause:'));

      await controller.seekTo(45.0);
      expect(receivedCommands, contains('seek:45.0'));

      controller.updateEmbedPlaybackState(
        isPlaying: true,
        position: 15.0,
        duration: 120.0,
      );

      expect(controller.isPlaying, isTrue);
      expect(controller.position, equals(15.0));
      expect(controller.duration, equals(120.0));
    });

    test('enterFullscreen, exitFullscreen, and toggleFullscreen update state and notify listeners', () async {
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
  });
}
