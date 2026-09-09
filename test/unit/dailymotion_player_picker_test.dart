import 'package:flutter_test/flutter_test.dart';
import 'package:watch_party/features/lobby/data/dailymotion_service.dart';
import 'package:watch_party/features/lobby/data/models/dailymotion_video_model.dart';
import 'package:watch_party/features/room/controllers/unified_player_controller.dart';
import 'package:watch_party/features/room/models/queue_item.dart';

void main() {
  group('DailymotionVideo Model Tests', () {
    test('instantiates with proper getters and formatted fields', () {
      const video = DailymotionVideo(
        id: 'x7tgad0',
        title: 'Big Buck Bunny (Official Dailymotion)',
        uploaderName: 'Blender Foundation',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x7tgad0',
        durationSeconds: 596,
        viewsTotal: 125000,
        category: 'Film & Animasi',
        description: 'Open source animated short film',
      );

      expect(video.id, 'x7tgad0');
      expect(video.url, 'https://www.dailymotion.com/video/x7tgad0');
      expect(video.embedUrl, contains('https://www.dailymotion.com/embed/video/x7tgad0'));
      expect(video.canonicalThumbnailUrl, 'https://www.dailymotion.com/thumbnail/video/x7tgad0');
      expect(video.formattedDuration, '09:56');
      expect(video.formattedViews, '125.0K views');
      expect(video.category, 'Film & Animasi');
      expect(video.uploaderName, 'Blender Foundation');
    });

    test('fromId generates correct defaults', () {
      final video = DailymotionVideo.fromId('x8abcde');
      expect(video.id, 'x8abcde');
      expect(video.title, 'Dailymotion Video (x8abcde)');
      expect(video.url, 'https://www.dailymotion.com/video/x8abcde');
      expect(video.embedUrl, contains('https://www.dailymotion.com/embed/video/x8abcde'));
      expect(video.canonicalThumbnailUrl, 'https://www.dailymotion.com/thumbnail/video/x8abcde');
      expect(video.category, 'Trending');
      expect(video.formattedDuration, 'HD');
    });

    test('toJson and fromJson work symmetrically', () {
      const video = DailymotionVideo(
        id: 'x81r4s7',
        title: 'Tears of Steel Sci-Fi Demo',
        uploaderName: 'Mango Open Movie',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x81r4s7',
        durationSeconds: 734,
        viewsTotal: 84000,
        category: 'Film & Animasi',
        description: 'VFX open source film',
      );

      final json = video.toJson();
      final fromJson = DailymotionVideo.fromJson(json);

      expect(fromJson.id, video.id);
      expect(fromJson.title, video.title);
      expect(fromJson.uploaderName, video.uploaderName);
      expect(fromJson.thumbnailUrl, video.thumbnailUrl);
      expect(fromJson.durationSeconds, video.durationSeconds);
      expect(fromJson.viewsTotal, video.viewsTotal);
      expect(fromJson.category, video.category);
      expect(fromJson.description, video.description);
    });
  });

  group('DailymotionService Tests', () {
    test('extractVideoId parses standard dailymotion.com/video/{id} URLs', () {
      const url = 'https://www.dailymotion.com/video/x7tgad0';
      expect(DailymotionService.extractVideoId(url), 'x7tgad0');
    });

    test('extractVideoId parses dailymotion.com/video/{id}?query=1 URLs', () {
      const url = 'https://www.dailymotion.com/video/x7tgad0?playlist=x54321';
      expect(DailymotionService.extractVideoId(url), 'x7tgad0');
    });

    test('extractVideoId parses dai.ly/{id} short URLs', () {
      const url = 'https://dai.ly/x7tgad0';
      expect(DailymotionService.extractVideoId(url), 'x7tgad0');
    });

    test('extractVideoId parses embed URLs', () {
      const url = 'https://www.dailymotion.com/embed/video/x7tgad0?autoplay=1';
      expect(DailymotionService.extractVideoId(url), 'x7tgad0');
    });

    test('extractVideoId parses raw Dailymotion ID', () {
      const rawId = 'x7tgad0';
      expect(DailymotionService.extractVideoId(rawId), rawId);
    });

    test('extractVideoId returns null for invalid strings', () {
      expect(DailymotionService.extractVideoId(''), isNull);
      expect(DailymotionService.extractVideoId('https://youtube.com/watch?v=123'), isNull);
      expect(DailymotionService.extractVideoId('invalid_id_format'), isNull);
    });

    test('categoryPresets has expected categories and valid video objects', () {
      final presets = DailymotionService.categoryPresets;
      expect(presets.keys, contains('Trending'));
      expect(presets.keys, contains('Film & Animasi'));
      expect(presets.keys, contains('Berita & Media'));
      expect(presets.keys, contains('Musik & Klip'));
      expect(presets.keys, contains('Olahraga & Aksi'));

      for (final entry in presets.entries) {
        expect(entry.value, isNotEmpty);
        for (final video in entry.value) {
          expect(video.id, isNotEmpty);
          expect(video.title, isNotEmpty);
          expect(video.url, contains('dailymotion.com/video/'));
          expect(video.embedUrl, contains('dailymotion.com/embed/video/'));
        }
      }
    });

    test('search filters fallback presets correctly', () async {
      final bunnyResults = await DailymotionService.search('bunny');
      expect(bunnyResults, isNotEmpty);
      expect(bunnyResults.first.title.isNotEmpty, isTrue);

      final newsResults = await DailymotionService.search('euronews');
      expect(newsResults, isNotEmpty);

      final emptyResults = await DailymotionService.search('nonexistentuniqueterm12345');
      expect(emptyResults, isEmpty);
    });
  });

  group('UnifiedPlayerController Dailymotion Tests', () {
    test('extractDailymotionVideoId delegates properly', () {
      const url = 'https://www.dailymotion.com/video/x81r4s7';
      expect(UnifiedPlayerController.extractDailymotionVideoId(url), 'x81r4s7');
    });
  });

  group('QueueItem Dailymotion Tests', () {
    test('isDailymotion returns true for dailymotion mediaType', () {
      final itemDm = QueueItem(
        id: '1',
        roomId: 'room1',
        mediaType: 'dailymotion',
        mediaUrl: 'https://www.dailymotion.com/video/x7tgad0',
        title: 'Big Buck Bunny',
        addedByUserId: 'u1',
        addedByUserName: 'Host',
        createdAt: DateTime.now(),
      );

      final itemYt = QueueItem(
        id: '2',
        roomId: 'room1',
        mediaType: 'youtube',
        mediaUrl: 'https://youtu.be/test',
        title: 'YT Video',
        addedByUserId: 'u1',
        addedByUserName: 'Host',
        createdAt: DateTime.now(),
      );

      expect(itemDm.isDailymotion, isTrue);
      expect(itemYt.isDailymotion, isFalse);
    });
  });
}
