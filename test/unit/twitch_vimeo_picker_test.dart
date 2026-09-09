import 'package:flutter_test/flutter_test.dart';
import 'package:watch_party/features/lobby/data/models/twitch_stream_model.dart';
import 'package:watch_party/features/lobby/data/models/vimeo_video_model.dart';
import 'package:watch_party/features/lobby/data/twitch_service.dart';
import 'package:watch_party/features/lobby/data/vimeo_service.dart';

void main() {
  group('TwitchStream Model Tests', () {
    test('instantiates and creates valid Twitch url', () {
      const stream = TwitchStream(
        id: 'monstercat',
        title: 'Monstercat 24/7 Live Radio',
        channelTitle: 'Monstercat',
        thumbnailUrl: 'https://static-cdn.jtvnw.net/previews-ttv/live_user_monstercat-640x360.jpg',
        category: 'Musik',
        viewerCount: '1.4K penonton',
      );

      expect(stream.url, 'https://www.twitch.tv/monstercat');
      expect(stream.id, 'monstercat');
      expect(stream.viewerCount, '1.4K penonton');
      expect(stream.category, 'Musik');
    });

    test('fromId generates correct defaults', () {
      final stream = TwitchStream.fromId(id: 'riotgames');
      expect(stream.id, 'riotgames');
      expect(stream.url, 'https://www.twitch.tv/riotgames');
      expect(stream.thumbnailUrl, contains('live_user_riotgames-640x360.jpg'));
    });

    test('toJson and fromJson work symmetrically', () {
      const stream = TwitchStream(
        id: 'eslcs',
        title: 'ESL CS2 Stream',
        channelTitle: 'ESLcs',
        thumbnailUrl: 'https://example.com/esl.jpg',
        category: 'Esports',
        viewerCount: '20K',
      );

      final json = stream.toJson();
      final fromJson = TwitchStream.fromJson(json);

      expect(fromJson.id, stream.id);
      expect(fromJson.title, stream.title);
      expect(fromJson.channelTitle, stream.channelTitle);
      expect(fromJson.thumbnailUrl, stream.thumbnailUrl);
      expect(fromJson.category, stream.category);
      expect(fromJson.viewerCount, stream.viewerCount);
    });
  });

  group('VimeoVideo Model Tests', () {
    test('instantiates and creates valid Vimeo url', () {
      const video = VimeoVideo(
        id: '76979871',
        title: 'The New Normal',
        channelTitle: 'Vimeo Staff Picks',
        thumbnailUrl: 'https://vumbnail.com/76979871.jpg',
        duration: '11:15',
        category: 'Staff Picks',
      );

      expect(video.url, 'https://vimeo.com/76979871');
      expect(video.id, '76979871');
      expect(video.duration, '11:15');
      expect(video.category, 'Staff Picks');
    });

    test('fromId generates correct defaults', () {
      final video = VimeoVideo.fromId(id: '1084537');
      expect(video.id, '1084537');
      expect(video.url, 'https://vimeo.com/1084537');
      expect(video.thumbnailUrl, 'https://vumbnail.com/1084537.jpg');
      expect(video.duration, 'HD');
    });

    test('toJson and fromJson work symmetrically', () {
      const video = VimeoVideo(
        id: '22439234',
        title: 'The Mountain',
        channelTitle: 'TSO Photography',
        thumbnailUrl: 'https://vumbnail.com/22439234.jpg',
        duration: '03:05',
        category: 'Staff Picks',
      );

      final json = video.toJson();
      final fromJson = VimeoVideo.fromJson(json);

      expect(fromJson.id, video.id);
      expect(fromJson.title, video.title);
      expect(fromJson.channelTitle, video.channelTitle);
      expect(fromJson.thumbnailUrl, video.thumbnailUrl);
      expect(fromJson.duration, video.duration);
    });
  });

  group('TwitchService Tests', () {
    test('extractChannel accurately extracts username from various formats', () {
      expect(TwitchService.extractChannel('https://www.twitch.tv/monstercat'), 'monstercat');
      expect(TwitchService.extractChannel('https://twitch.tv/riotgames'), 'riotgames');
      expect(TwitchService.extractChannel('shroud'), 'shroud');
      expect(TwitchService.extractChannel(''), isNull);
    });

    test('categoryPresets has expected rich categories', () {
      expect(TwitchService.categoryPresets.containsKey('Populer & Live'), isTrue);
      expect(TwitchService.categoryPresets.containsKey('Musik & Radio 24/7'), isTrue);
      expect(TwitchService.categoryPresets.containsKey('Esports & Turnamen'), isTrue);
      expect(TwitchService.categoryPresets.containsKey('Gaming'), isTrue);
      expect(TwitchService.categoryPresets.containsKey('Just Chatting'), isTrue);
    });

    test('search empty query returns default category presets', () async {
      final results = await TwitchService.search('');
      expect(results, isNotEmpty);
      expect(results.first.id, TwitchService.categoryPresets['Populer & Live']!.first.id);
    });

    test('search direct URL returns channel stream', () async {
      final results = await TwitchService.search('https://twitch.tv/monstercat');
      expect(results, isNotEmpty);
      expect(results.first.id, 'monstercat');
    });

    test('search keyword filters presets or creates stream', () async {
      final results = await TwitchService.search('esports');
      expect(results, isNotEmpty);
      expect(results.any((s) => s.category.toLowerCase().contains('esports')), isTrue);
    });
  });

  group('VimeoService Tests', () {
    test('extractVideoId accurately extracts numeric ID', () {
      expect(VimeoService.extractVideoId('https://vimeo.com/76979871'), '76979871');
      expect(VimeoService.extractVideoId('vimeo.com/channels/staffpicks/76979871'), '76979871');
      expect(VimeoService.extractVideoId('76979871'), '76979871');
      expect(VimeoService.extractVideoId(''), isNull);
    });

    test('categoryPresets has expected rich categories', () {
      expect(VimeoService.categoryPresets.containsKey('Staff Picks'), isTrue);
      expect(VimeoService.categoryPresets.containsKey('Film Pendek & Sci-Fi'), isTrue);
      expect(VimeoService.categoryPresets.containsKey('Animasi 3D'), isTrue);
      expect(VimeoService.categoryPresets.containsKey('Dokumenter & Alam'), isTrue);
    });

    test('search empty query returns Staff Picks presets', () async {
      final results = await VimeoService.search('');
      expect(results, isNotEmpty);
      expect(results.first.id, VimeoService.categoryPresets['Staff Picks']!.first.id);
    });

    test('search direct URL returns specific video item', () async {
      final results = await VimeoService.search('https://vimeo.com/76979871');
      expect(results, isNotEmpty);
      expect(results.first.id, '76979871');
    });

    test('search keyword filters presets', () async {
      final results = await VimeoService.search('bunny');
      expect(results, isNotEmpty);
      expect(results.first.title.toLowerCase(), contains('bunny'));
    });
  });
}
