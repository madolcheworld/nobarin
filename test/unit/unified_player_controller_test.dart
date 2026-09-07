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
