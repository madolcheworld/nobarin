import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nobarin/core/network/app_http_client.dart';
import 'package:nobarin/features/lobby/data/bstation_service.dart';
import 'package:nobarin/features/lobby/data/models/bstation_video_model.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/models/queue_item.dart';

void main() {
  group('BstationVideo Model Tests', () {
    test('instantiates with proper getters and formatted fields', () {
      const video = BstationVideo(
        id: '2048992',
        title: 'SPY x FAMILY Season 2',
        uploaderName: 'Muse Indonesia',
        thumbnailUrl: 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=800',
        durationSeconds: 1440,
        viewsTotal: 1850000,
        category: 'Anime Populer',
        episodeNumber: 'Ep. 01',
        description: 'Petualangan keluarga Forger berlanjut!',
      );

      expect(video.id, '2048992');
      expect(video.url, 'https://www.bilibili.tv/id/play/2048992');
      expect(video.embedUrl, contains('https://www.bilibili.tv/id/play/2048992'));
      expect(video.effectiveThumbnailUrl, 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=800');
      expect(video.durationFormatted, '24:00');
      expect(video.viewsFormatted, '1.9M views');
      expect(video.category, 'Anime Populer');
      expect(video.episodeNumber, 'Ep. 01');
      expect(video.uploaderName, 'Muse Indonesia');
      expect(video.description, 'Petualangan keluarga Forger berlanjut!');
    });

    test('fromId generates correct defaults', () {
      final video = BstationVideo.fromId('BV1xx411c7mD');
      expect(video.id, 'BV1xx411c7mD');
      expect(video.title, 'Bstation Video (BV1xx411c7mD)');
      expect(video.url, 'https://www.bilibili.com/video/BV1xx411c7mD');
      expect(video.embedUrl, contains('https://player.bilibili.com/player.html?bvid=BV1xx411c7mD'));
      expect(video.category, 'Anime Populer');
      expect(video.durationFormatted, 'HD');
    });

    test('toJson and fromJson work symmetrically', () {
      const video = BstationVideo(
        id: '1004829',
        title: 'Jujutsu Kaisen Season 2 - Shibuya Incident',
        uploaderName: 'Ani-One Asia',
        thumbnailUrl: 'https://images.unsplash.com/photo-1534447677768-be436bb09401?w=800',
        durationSeconds: 1420,
        viewsTotal: 3400000,
        category: 'Anime Populer',
        episodeNumber: 'Ep. 09',
        description: 'Insiden Shibuya dimulai!',
      );

      final json = video.toJson();
      final fromJson = BstationVideo.fromJson(json);

      expect(fromJson.id, video.id);
      expect(fromJson.title, video.title);
      expect(fromJson.uploaderName, video.uploaderName);
      expect(fromJson.thumbnailUrl, video.thumbnailUrl);
      expect(fromJson.durationSeconds, video.durationSeconds);
      expect(fromJson.viewsTotal, video.viewsTotal);
      expect(fromJson.category, video.category);
      expect(fromJson.episodeNumber, video.episodeNumber);
      expect(fromJson.description, video.description);
    });
  });

  group('BstationService Tests', () {
    test('extractVideoId parses standard bilibili.tv/id/video/{id} URLs', () {
      const url = 'https://www.bilibili.tv/id/video/2048992';
      expect(BstationService.extractVideoId(url), '2048992');
    });

    test('extractVideoId parses bilibili.tv/en/video/{id} URLs', () {
      const url = 'https://www.bilibili.tv/en/video/4786329';
      expect(BstationService.extractVideoId(url), '4786329');
    });

    test('extractVideoId parses bilibili.tv/id/play/{season}/{episode} URLs', () {
      const url = 'https://www.bilibili.tv/id/play/2088820/1149830';
      expect(BstationService.extractVideoId(url), '2088820/1149830');
    });

    test('extractVideoId parses bilibili.com/video/BV... URLs', () {
      const url = 'https://www.bilibili.com/video/BV17x411w7KC';
      expect(BstationService.extractVideoId(url), 'BV17x411w7KC');
    });

    test('extractVideoId parses b23.tv/{id} short URLs', () {
      const url = 'https://b23.tv/BV1xx411c7mD';
      expect(BstationService.extractVideoId(url), 'BV1xx411c7mD');
    });

    test('extractVideoId parses raw Bstation BV ID', () {
      const rawId = 'BV17x411w7KC';
      expect(BstationService.extractVideoId(rawId), rawId);
    });

    test('extractVideoId parses raw numeric ID', () {
      const rawId = '2048992';
      expect(BstationService.extractVideoId(rawId), rawId);
    });

    test('extractVideoId returns null for invalid strings', () {
      expect(BstationService.extractVideoId(''), isNull);
      expect(BstationService.extractVideoId('https://youtube.com/watch?v=123'), isNull);
      expect(BstationService.extractVideoId('invalid_id_format_xyz'), isNull);
    });

    test('categoryPresets has expected categories and valid video objects', () {
      final presets = BstationService.categoryPresets;
      expect(presets.keys, contains('Anime Populer'));
      expect(presets.keys, contains('Trending & Kreator'));
      expect(presets.keys, contains('AMV & Musik'));
      expect(presets.keys, contains('Komedi & Parodi'));

      for (final entry in presets.entries) {
        expect(entry.value, isNotEmpty);
        for (final video in entry.value) {
          expect(video.id, isNotEmpty);
          expect(video.title, isNotEmpty);
          expect(video.url, contains('bilibili.'));
          expect(video.embedUrl, anyOf(contains('player.bilibili.com/player.html?'), contains('bilibili.tv/id/play/')));
        }
      }
    });

    test('search filters fallback presets correctly', () async {
      final mock = MockClient((request) async => http.Response('Error', 500));
      AppHttpClient.setMockClient(mock);

      final genshinResults = await BstationService.search('genshin');
      expect(genshinResults, isNotEmpty);
      expect(genshinResults.first.title.toLowerCase(), contains('genshin'));

      final yoasobiResults = await BstationService.search('yoasobi');
      expect(yoasobiResults, isNotEmpty);

      final emptyResults = await BstationService.search('nonexistentuniquekeyword999');
      expect(emptyResults, isEmpty);

      AppHttpClient.setMockClient(null);
    });

    test('search parses live API responses correctly', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              'modules': [
                {
                  'type': 'ogv_subject',
                  'items': [
                    {
                      'title': 'Naruto',
                      'seasons': [
                        {
                          'season_id': '1005144',
                          'title': '<em class="keyword">Naruto</em> Shippuden',
                          'cover': 'https://pic.bstarstatic.com/test.jpg',
                          'view': '446.5M Putar',
                          'description': 'Kisah ninja Naruto &amp; teman-temannya',
                          'index_show': 'Tamat',
                          'styles': [
                            {'title': 'Anime'},
                            {'title': 'Aksi'}
                          ],
                        }
                      ]
                    }
                  ]
                },
                {
                  'type': 'ugc',
                  'items': [
                    {
                      'aid': '2044815780',
                      'title': 'Minato Story &amp; Action',
                      'cover': 'https://pic.bstarstatic.com/ugc.jpg',
                      'duration': '10:15',
                      'view': '6.7K Ditonton',
                      'author': {'nickname': 'CreatorNinja'}
                    }
                  ]
                }
              ]
            }
          }),
          200,
        );
      });

      AppHttpClient.setMockClient(mock);

      final results = await BstationService.search('naruto');
      expect(results, hasLength(2));

      // Anime season item
      expect(results[0].id, '1005144');
      expect(results[0].title, 'Naruto Shippuden');
      expect(results[0].viewsTotal, 446500000);
      expect(results[0].category, 'Anime, Aksi');
      expect(results[0].episodeNumber, 'Tamat');
      expect(results[0].description, contains('&'));

      // UGC video item
      expect(results[1].id, '2044815780');
      expect(results[1].title, 'Minato Story & Action');
      expect(results[1].durationSeconds, 615);
      expect(results[1].uploaderName, 'CreatorNinja');
      expect(results[1].viewsTotal, 6700);

      AppHttpClient.setMockClient(null);
    });
  });

  group('UnifiedPlayerController Bstation Tests', () {
    test('extractBstationVideoId delegates properly', () {
      const url = 'https://www.bilibili.tv/id/video/2048992';
      expect(UnifiedPlayerController.extractBstationVideoId(url), '2048992');
    });
  });

  group('QueueItem Bstation Tests', () {
    test('isBstation returns true for bstation mediaType', () {
      final item = QueueItem(
        id: '1',
        roomId: 'room1',
        mediaType: 'bstation',
        mediaUrl: 'https://www.bilibili.tv/id/video/2048992',
        title: 'SPY x FAMILY Episode 1',
        addedByUserId: 'u1',
        addedByUserName: 'Host',
        createdAt: DateTime.now(),
      );

      expect(item.isBstation, isTrue);
      expect(item.isYouTube, isFalse);
      expect(item.isDailymotion, isFalse);
      expect(item.isGoogleDrive, isFalse);
    });

    test('isBstation returns true for bilibili mediaType', () {
      final item = QueueItem(
        id: '2',
        roomId: 'room1',
        mediaType: 'bilibili',
        mediaUrl: 'https://www.bilibili.com/video/BV17x411w7KC',
        title: 'Bilibili Stream',
        addedByUserId: 'u1',
        addedByUserName: 'Host',
        createdAt: DateTime.now(),
      );

      expect(item.isBstation, isTrue);
    });
  });
}
