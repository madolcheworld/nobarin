import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nobarin/core/network/api_cache_manager.dart';
import 'package:nobarin/core/network/app_http_client.dart';
import 'package:nobarin/features/lobby/data/dailymotion_service.dart';
import 'package:nobarin/features/lobby/data/youtube_service.dart';

void main() {
  group('Service Cache Integration Tests', () {
    setUp(() {
      ApiCacheManager.instance.clear();
      AppHttpClient.setMockClient(null);
    });

    tearDown(() {
      ApiCacheManager.instance.clear();
      AppHttpClient.setMockClient(null);
    });

    test('YouTubeService.fetchVideoDetails caches response and skips second network call', () async {
      int httpCalls = 0;
      final mock = MockClient((request) async {
        httpCalls++;
        return http.Response(
          jsonEncode({
            'title': 'Test Video Cached',
            'author_name': 'Test Channel',
            'thumbnail_url': 'https://example.com/thumb.jpg',
          }),
          200,
        );
      });

      AppHttpClient.setMockClient(mock);

      // First call: hits network
      final video1 = await YouTubeService.fetchVideoDetails('aqz-KE-bpKQ');
      expect(httpCalls, equals(1));
      expect(video1.title, equals('Test Video Cached'));

      // Second call: served from ApiCacheManager without network call
      final video2 = await YouTubeService.fetchVideoDetails('aqz-KE-bpKQ');
      expect(httpCalls, equals(1)); // count did not increase!
      expect(video2.title, equals('Test Video Cached'));
    });


    test('DailymotionService.fetchVideoDetails caches response and skips second network call', () async {
      int httpCalls = 0;
      final mock = MockClient((request) async {
        httpCalls++;
        return http.Response(
          jsonEncode({
            'id': 'xcustom123',
            'title': 'Dailymotion Custom Cached',
            'duration': 300,
            'thumbnail_720_url': 'https://example.com/dm.jpg',
            'owner.screenname': 'DMOwner',
            'views_total': 1000,
          }),
          200,
        );
      });

      AppHttpClient.setMockClient(mock);

      final d1 = await DailymotionService.fetchVideoDetails('xcustom123');
      expect(httpCalls, equals(1));
      expect(d1?.title, equals('Dailymotion Custom Cached'));

      final d2 = await DailymotionService.fetchVideoDetails('xcustom123');
      expect(httpCalls, equals(1));
      expect(d2?.title, equals('Dailymotion Custom Cached'));
    });
  });
}
