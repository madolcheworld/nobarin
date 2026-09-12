import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/lobby/data/models/youtube_video_model.dart';
import 'package:nobarin/features/lobby/data/youtube_service.dart';

void main() {
  group('YouTubeVideo Model Tests', () {
    test('instantiates and creates valid YouTube url', () {
      const video = YouTubeVideo(
        id: 'dQw4w9WgXcQ',
        title: 'Rick Astley',
        channelTitle: 'Rick Astley',
        thumbnailUrl: 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        duration: '03:33',
      );

      expect(video.url, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(video.id, 'dQw4w9WgXcQ');
    });

    test('fromId generates correct defaults', () {
      final video = YouTubeVideo.fromId(id: 'xyz123abc45');
      expect(video.id, 'xyz123abc45');
      expect(video.thumbnailUrl, 'https://img.youtube.com/vi/xyz123abc45/hqdefault.jpg');
      expect(video.url, 'https://www.youtube.com/watch?v=xyz123abc45');
    });

    test('toJson and fromJson work symmetrically', () {
      const video = YouTubeVideo(
        id: 'test_id_123',
        title: 'Test Title',
        channelTitle: 'Test Channel',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        duration: '10:00',
      );

      final json = video.toJson();
      final fromJson = YouTubeVideo.fromJson(json);

      expect(fromJson.id, video.id);
      expect(fromJson.title, video.title);
      expect(fromJson.channelTitle, video.channelTitle);
      expect(fromJson.thumbnailUrl, video.thumbnailUrl);
      expect(fromJson.duration, video.duration);
    });
  });

  group('YouTubeService Tests', () {
    test('extractVideoId accurately parses multiple YouTube URL variants', () {
      expect(
        YouTubeService.extractVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        YouTubeService.extractVideoId('https://youtu.be/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        YouTubeService.extractVideoId('https://www.youtube.com/shorts/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        YouTubeService.extractVideoId('https://www.youtube.com/embed/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        YouTubeService.extractVideoId('dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        YouTubeService.extractVideoId('not-a-youtube-id'),
        isNull,
      );
    });

    test('categoryPresets has rich default categories', () {
      expect(YouTubeService.categoryPresets.containsKey('Trending'), isTrue);
      expect(YouTubeService.categoryPresets.containsKey('Musik & Lo-Fi'), isTrue);
      expect(YouTubeService.categoryPresets.containsKey('Trailer Film'), isTrue);
      expect(YouTubeService.categoryPresets.containsKey('Anime'), isTrue);
      expect(YouTubeService.categoryPresets['Trending']!.isNotEmpty, isTrue);
    });

    test('search empty query returns Trending presets', () async {
      final results = await YouTubeService.search('');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.id, YouTubeService.categoryPresets['Trending']!.first.id);
    });

    test('search direct URL returns video info directly', () async {
      final results = await YouTubeService.search('https://youtu.be/dQw4w9WgXcQ');
      expect(results.length, 1);
      expect(results.first.id, 'dQw4w9WgXcQ');
    });

    test('search with pagination parameters works gracefully', () async {
      final page1 = await YouTubeService.search('Trending', page: 1);
      final page2 = await YouTubeService.search('Trending', page: 2);
      expect(page1, isNotEmpty);
      expect(page2, isA<List<YouTubeVideo>>());
    });
  });
}
