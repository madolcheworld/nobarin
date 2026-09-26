import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/room/models/video_quality.dart';
import 'package:nobarin/features/room/services/hls_manifest_parser.dart';

void main() {
  group('VideoQuality Model & Logic Tests', () {
    test('Auto quality is properly configured', () {
      const autoQuality = VideoQuality.auto();
      expect(autoQuality.id, 'auto');
      expect(autoQuality.label, 'Auto (Otomatis)');
      expect(autoQuality.isAuto, isTrue);
      expect(autoQuality.shortLabel, 'Auto');
      expect(autoQuality.height, isNull);
    });

    test('VideoQuality shortLabel formats properly for various heights', () {
      const q1080 = VideoQuality(id: '1080p', label: '1080p (FHD)', height: 1080);
      expect(q1080.shortLabel, '1080p');

      const q720 = VideoQuality(id: '720p', label: '720p (HD)', height: 720);
      expect(q720.shortLabel, '720p');

      const qCustom = VideoQuality(id: 'custom', label: 'Medium Quality');
      expect(qCustom.shortLabel, 'Medium Quality');
    });

    test('VideoQuality badgeDescription shows correct resolution tier', () {
      const q4k = VideoQuality(id: '2160p', label: '4K', height: 2160);
      expect(q4k.badgeDescription, 'Ultra HD 4K');

      const q1080 = VideoQuality(id: '1080p', label: '1080p', height: 1080);
      expect(q1080.badgeDescription, 'Full HD');

      const q720 = VideoQuality(id: '720p', label: '720p', height: 720);
      expect(q720.badgeDescription, 'HD Resolusi Tinggi');

      const q480 = VideoQuality(id: '480p', label: '480p', height: 480);
      expect(q480.badgeDescription, 'Standar Definition (SD)');

      const q360 = VideoQuality(id: '360p', label: '360p', height: 360);
      expect(q360.badgeDescription, 'Hemat Kuota');

      const qAuto = VideoQuality.auto();
      expect(qAuto.badgeDescription, 'Menyesuaikan koneksi internet');
    });

    test('Equality and hashCode are based on id and height', () {
      const q1 = VideoQuality(id: 'hd720', label: '720p', height: 720);
      const q2 = VideoQuality(id: 'hd720', label: '720p High Definition', height: 720);
      const q3 = VideoQuality(id: 'hd1080', label: '1080p', height: 1080);

      expect(q1, equals(q2));
      expect(q1.hashCode, equals(q2.hashCode));
      expect(q1, isNot(equals(q3)));
    });

    test('Dailymotion factory constructor maps resolution heights', () {
      final dmAuto = VideoQuality.dailymotion('auto');
      expect(dmAuto.isAuto, isTrue);
      expect(dmAuto.id, 'auto');
      expect(dmAuto.shortLabel, 'Auto');
      expect(dmAuto.mode, QualityControlMode.webviewBridge);

      final dm1080 = VideoQuality.dailymotion('1080', streamUrl: 'https://example.com/1080.m3u8');
      expect(dm1080.isAuto, isFalse);
      expect(dm1080.id, '1080');
      expect(dm1080.height, 1080);
      expect(dm1080.shortLabel, '1080p');
      expect(dm1080.badgeDescription, 'Full HD');
      expect(dm1080.streamUrl, 'https://example.com/1080.m3u8');
      expect(dm1080.mode, QualityControlMode.webviewBridge);

      final dm720p = VideoQuality.dailymotion('720p');
      expect(dm720p.height, 720);
      expect(dm720p.shortLabel, '720p');
      expect(dm720p.badgeDescription, 'HD Resolusi Tinggi');

      final dm480 = VideoQuality.dailymotion('480');
      expect(dm480.height, 480);
      expect(dm480.shortLabel, '480p');
      expect(dm480.badgeDescription, 'Standar Definition (SD)');

      final dm360 = VideoQuality.dailymotion('360');
      expect(dm360.height, 360);
      expect(dm360.shortLabel, '360p');
      expect(dm360.badgeDescription, 'Hemat Kuota');

      final dm240 = VideoQuality.dailymotion('240');
      expect(dm240.height, 240);
      expect(dm240.shortLabel, '240p');
      expect(dm240.badgeDescription, 'Sangat Hemat Kuota');
    });

    test('Bstation factory constructor preserves fps and bitrate', () {
      final bstationAuto = VideoQuality.bstation(
        id: 'auto',
        label: 'Auto (Otomatis Bstation)',
      );
      expect(bstationAuto.isAuto, isTrue);
      expect(bstationAuto.id, 'auto');
      expect(bstationAuto.shortLabel, 'Auto');
      expect(bstationAuto.mode, QualityControlMode.webviewBridge);

      final bstation1080p60 = VideoQuality.bstation(
        id: '116',
        label: '1080p 60fps',
        height: 1080,
        fps: 60.0,
        bitrate: 4500000,
      );
      expect(bstation1080p60.isAuto, isFalse);
      expect(bstation1080p60.id, '116');
      expect(bstation1080p60.height, 1080);
      expect(bstation1080p60.fps, 60.0);
      expect(bstation1080p60.bitrate, 4500000);
      expect(bstation1080p60.shortLabel, '1080p');
      expect(bstation1080p60.mode, QualityControlMode.webviewBridge);
    });

    test('YouTube factory constructor maps standard IFrame quality codes', () {
      final ytAuto = VideoQuality.youtube('auto');
      expect(ytAuto.isAuto, isTrue);

      final yt4k = VideoQuality.youtube('hd2160');
      expect(yt4k.height, 2160);
      expect(yt4k.shortLabel, '2160p');
      expect(yt4k.label, '2160p (4K Ultra HD)');
      expect(yt4k.badgeDescription, 'Ultra HD 4K');

      final yt2k = VideoQuality.youtube('hd1440');
      expect(yt2k.height, 1440);
      expect(yt2k.shortLabel, '1440p');
      expect(yt2k.badgeDescription, 'Quad HD 2K');

      final yt1080 = VideoQuality.youtube('hd1080');
      expect(yt1080.height, 1080);
      expect(yt1080.shortLabel, '1080p');

      final yt720 = VideoQuality.youtube('hd720');
      expect(yt720.height, 720);

      final yt480 = VideoQuality.youtube('large');
      expect(yt480.height, 480);

      final yt360 = VideoQuality.youtube('medium');
      expect(yt360.height, 360);

      final yt240 = VideoQuality.youtube('small');
      expect(yt240.height, 240);

      final yt144 = VideoQuality.youtube('tiny');
      expect(yt144.height, 144);
    });

    test('normalizeResolutionHeight handles 16:9, vertical 9:16, and ultrawide 21:9', () {
      // Standard 16:9
      expect(VideoQuality.normalizeResolutionHeight(width: 1920, height: 1080), 1080);
      expect(VideoQuality.normalizeResolutionHeight(width: 1280, height: 720), 720);
      expect(VideoQuality.normalizeResolutionHeight(width: 3840, height: 2160), 2160);

      // Vertical 9:16 (uses shorter side = 1080p / 720p)
      expect(VideoQuality.normalizeResolutionHeight(width: 1080, height: 1920), 1080);
      expect(VideoQuality.normalizeResolutionHeight(width: 720, height: 1280), 720);

      // Ultrawide 21:9 (maps by width so 1920x800 is recognized as 1080p class)
      expect(VideoQuality.normalizeResolutionHeight(width: 1920, height: 800), 1080);
      expect(VideoQuality.normalizeResolutionHeight(width: 2560, height: 1080), 1440);
      expect(VideoQuality.normalizeResolutionHeight(width: 3840, height: 1600), 2160);
    });
  });

  group('HlsManifestParser Unit Tests', () {
    test('isHlsUrl detects .m3u8 paths and query parameters', () {
      expect(HlsManifestParser.isHlsUrl('https://cdn.example.com/live/master.m3u8'), isTrue);
      expect(HlsManifestParser.isHlsUrl('https://cdn.example.com/live/master.m3u8?token=abc'), isTrue);
      expect(HlsManifestParser.isHlsUrl('https://cdn.example.com/video.mp4'), isFalse);
    });

    test('extractVariants and parseMasterPlaylist extract exact resolution variants and resolve relative URLs', () {
      const manifest = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,FRAME-RATE=30.0
360p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2800000,AVERAGE-BANDWIDTH=2400000,RESOLUTION=1280x720,FRAME-RATE=30.0
720p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5500000,RESOLUTION=1920x1080,FRAME-RATE=60.0
https://cdn.example.com/streams/1080p60/index.m3u8
''';

      final baseUri = Uri.parse('https://cdn.example.com/streams/master.m3u8');
      final variants = HlsManifestParser.extractVariants(
        manifest,
        baseUri: baseUri,
      );

      expect(variants.length, equals(3));
      expect(variants[0].height, equals(360));
      expect(variants[0].streamUrl, equals('https://cdn.example.com/streams/360p/index.m3u8'));
      expect(variants[1].height, equals(720));
      expect(variants[1].bandwidth, equals(2400000));
      expect(variants[1].streamUrl, equals('https://cdn.example.com/streams/720p/index.m3u8'));
      expect(variants[2].height, equals(1080));
      expect(variants[2].frameRate, equals(60.0));
      expect(variants[2].streamUrl, equals('https://cdn.example.com/streams/1080p60/index.m3u8'));

      final qualities = HlsManifestParser.parseMasterPlaylist(
        manifest,
        baseUri: baseUri,
      );
      expect(qualities.length, equals(4)); // Auto + 1080p 60fps + 720p + 360p
      expect(qualities[0].isAuto, isTrue);
      expect(qualities[1].label, equals('1080p 60fps'));
      expect(qualities[1].height, equals(1080));
      expect(qualities[2].label, equals('720p'));
      expect(qualities[2].height, equals(720));
      expect(qualities[3].label, equals('360p'));
      expect(qualities[3].height, equals(360));
    });

    test('parseMasterPlaylist returns empty list for single-stream media playlist', () {
      const mediaPlaylist = '''
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXTINF:9.009,
segment0.ts
#EXTINF:9.009,
segment1.ts
''';

      final baseUri = Uri.parse('https://cdn.example.com/streams/360p/index.m3u8');
      final variants = HlsManifestParser.extractVariants(
        mediaPlaylist,
        baseUri: baseUri,
      );
      expect(variants, isEmpty);
      expect(HlsManifestParser.parseMasterPlaylist(mediaPlaylist, baseUri: baseUri), isEmpty);
    });
  });
}

