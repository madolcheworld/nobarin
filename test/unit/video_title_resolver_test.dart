import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nobarin/core/utils/video_title_resolver.dart';

void main() {
  setUp(() {
    VideoTitleResolver.clearCache();
  });

  group('VideoTitleResolver - cleanTitle Tests', () {
    test('returns empty string for null, empty or whitespace strings', () {
      expect(VideoTitleResolver.cleanTitle(null), equals(''));
      expect(VideoTitleResolver.cleanTitle(''), equals(''));
      expect(VideoTitleResolver.cleanTitle('   '), equals(''));
    });

    test('rejects purely numeric strings (IDs and indices)', () {
      expect(VideoTitleResolver.cleanTitle('11057474'), equals(''));
      expect(VideoTitleResolver.cleanTitle('1080'), equals(''));
      expect(VideoTitleResolver.cleanTitle('001'), equals(''));
      expect(VideoTitleResolver.cleanTitle('999999999'), equals(''));
    });

    test('rejects platform wrappers with IDs in parentheses', () {
      expect(VideoTitleResolver.cleanTitle('Video Bstation (11057474)'), equals(''));
      expect(VideoTitleResolver.cleanTitle('Bstation (11057474)'), equals(''));
      expect(VideoTitleResolver.cleanTitle('Video YouTube (dQw4w9WgXcQ)'), equals(''));
      expect(VideoTitleResolver.cleanTitle('YouTube (dQw4w9WgXcQ)'), equals(''));
      expect(VideoTitleResolver.cleanTitle('Video Dailymotion (x7tgad0)'), equals(''));
      expect(VideoTitleResolver.cleanTitle('Dailymotion (x7tgad0)'), equals(''));
    });

    test('unescapes HTML entities properly', () {
      final cleaned = VideoTitleResolver.cleanTitle(
        'SPY &amp; FAMILY E1 &quot;Operasi &#39;Strix&#39;&quot; &lt;Part 1&gt;',
      );
      expect(cleaned, equals('SPY & FAMILY E1 "Operasi \'Strix\'" <Part 1>'));
    });

    test('strips platform suffixes from title', () {
      expect(
        VideoTitleResolver.cleanTitle('One Piece Episode 1000 - Bstation'),
        equals('One Piece Episode 1000'),
      );
      expect(
        VideoTitleResolver.cleanTitle('Rick Astley - Never Gonna Give You Up | YouTube'),
        equals('Rick Astley - Never Gonna Give You Up'),
      );
      expect(
        VideoTitleResolver.cleanTitle('Jujutsu Kaisen Season 2 HD | bilibili'),
        equals('Jujutsu Kaisen Season 2'),
      );
      expect(
        VideoTitleResolver.cleanTitle('Dailymotion Documentary - Dailymotion'),
        equals('Dailymotion Documentary'),
      );
    });

    test('rejects generic platform names or titles that become empty after stripping', () {
      expect(VideoTitleResolver.cleanTitle('Bstation'), equals(''));
      expect(VideoTitleResolver.cleanTitle('YouTube'), equals(''));
      expect(VideoTitleResolver.cleanTitle('Dailymotion'), equals(''));
      expect(VideoTitleResolver.cleanTitle('Video'), equals(''));
      expect(VideoTitleResolver.cleanTitle('12345 - Bstation'), equals(''));
    });

    test('preserves valid titles without suffixes', () {
      expect(
        VideoTitleResolver.cleanTitle('Solo Leveling Episode 1 - I\'m Used to It'),
        equals('Solo Leveling Episode 1 - I\'m Used to It'),
      );
    });
  });

  group('VideoTitleResolver - resolveTitle Tests', () {
    test('resolves YouTube title via oEmbed mock', () async {
      final mock = MockClient((request) async {
        if (request.url.host.contains('youtube.com') && request.url.path.contains('oembed')) {
          return http.Response(
            jsonEncode({'title': 'Rick Astley - Never Gonna Give You Up - YouTube'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final title = await VideoTitleResolver.resolveTitle(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        client: mock,
      );

      expect(title, equals('Rick Astley - Never Gonna Give You Up'));
    });

    test('resolves Dailymotion title via oEmbed mock', () async {
      final mock = MockClient((request) async {
        if (request.url.host.contains('dailymotion.com') && request.url.path.contains('oembed')) {
          return http.Response(
            jsonEncode({'title': 'Amazing Nature Documentary - Dailymotion'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final title = await VideoTitleResolver.resolveTitle(
        'https://www.dailymotion.com/video/x7tgad0',
        client: mock,
      );

      expect(title, equals('Amazing Nature Documentary'));
    });

    test('resolves Bstation title from HTML <title> tag', () async {
      final mock = MockClient((request) async {
        if (request.url.host.contains('bilibili.tv')) {
          const html = '''
            <!DOCTYPE html>
            <html>
              <head>
                <title>SPY x FAMILY E1 - Operasi "Strix" - Bstation</title>
              </head>
              <body></body>
            </html>
          ''';
          return http.Response(html, 200, headers: {'content-type': 'text/html; charset=utf-8'});
        }
        return http.Response('Not found', 404);
      });

      final title = await VideoTitleResolver.resolveTitle(
        'https://www.bilibili.tv/id/play/1048837/11057474',
        client: mock,
      );

      expect(title, equals('SPY x FAMILY E1 - Operasi "Strix"'));
    });

    test('resolves Bstation title from og:title meta tag when title tag is generic', () async {
      final mock = MockClient((request) async {
        if (request.url.host.contains('bilibili.tv')) {
          const html = '''
            <!DOCTYPE html>
            <html>
              <head>
                <title>Bstation</title>
                <meta property="og:title" content="Frieren: Beyond Journey's End E28 - Bstation" />
              </head>
              <body></body>
            </html>
          ''';
          return http.Response(html, 200, headers: {'content-type': 'text/html; charset=utf-8'});
        }
        return http.Response('Not found', 404);
      });

      final title = await VideoTitleResolver.resolveTitle(
        'https://www.bilibili.tv/id/play/2088888',
        client: mock,
      );

      expect(title, equals("Frieren: Beyond Journey's End E28"));
    });

    test('extracts clean title from direct video URL filename', () async {
      final mock = MockClient((_) async => http.Response('Not found', 404));

      final title = await VideoTitleResolver.resolveTitle(
        'https://example.com/videos/trailer_final_hd.mp4',
        client: mock,
      );

      expect(title, equals('trailer final hd'));
    });

    test('rejects direct video URL with purely numeric filename', () async {
      final mock = MockClient((_) async => http.Response('Not found', 404));

      final title = await VideoTitleResolver.resolveTitle(
        'https://example.com/videos/123456789.mp4',
        client: mock,
      );

      expect(title, isNull);
    });

    test('caches resolved titles and returns cached title without HTTP call', () async {
      int requestCount = 0;
      final mock = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode({'title': 'Cached Video Title'}),
          200,
        );
      });

      final url = 'https://www.youtube.com/watch?v=cacheTest123';
      final first = await VideoTitleResolver.resolveTitle(url, client: mock);
      expect(first, equals('Cached Video Title'));
      expect(requestCount, equals(1));

      // Second call should hit the cache and not invoke HTTP client
      final second = await VideoTitleResolver.resolveTitle(url, client: mock);
      expect(second, equals('Cached Video Title'));
      expect(requestCount, equals(1));

      // Clear cache and call again
      VideoTitleResolver.clearCache();
      final third = await VideoTitleResolver.resolveTitle(url, client: mock);
      expect(third, equals('Cached Video Title'));
      expect(requestCount, equals(2));
    });
  });
}
