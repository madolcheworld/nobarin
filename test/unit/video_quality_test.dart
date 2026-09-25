import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/room/models/video_quality.dart';

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

    test('YouTube preset quality mappings', () {
      final ytPresets = [
        const VideoQuality.auto(),
        const VideoQuality(id: 'hd1080', label: '1080p (Full HD)', height: 1080),
        const VideoQuality(id: 'hd720', label: '720p (HD)', height: 720),
        const VideoQuality(id: 'large', label: '480p (SD)', height: 480),
        const VideoQuality(id: 'medium', label: '360p (Hemat Kuota)', height: 360),
        const VideoQuality(id: 'small', label: '240p (Rendah)', height: 240),
        const VideoQuality(id: 'tiny', label: '144p (Sangat Rendah)', height: 144),
      ];

      expect(ytPresets.length, 7);
      expect(ytPresets.first.isAuto, isTrue);
      expect(ytPresets[1].id, 'hd1080');
      expect(ytPresets[2].id, 'hd720');
      expect(ytPresets[3].id, 'large');
      expect(ytPresets[4].id, 'medium');
      expect(ytPresets[5].id, 'small');
      expect(ytPresets[6].id, 'tiny');
    });

    test('Dailymotion preset qualities and factory constructor', () {
      final dmAuto = VideoQuality.dailymotion('auto');
      expect(dmAuto.isAuto, isTrue);
      expect(dmAuto.id, 'auto');
      expect(dmAuto.shortLabel, 'Auto');
      expect(dmAuto.mode, QualityControlMode.webviewBridge);

      final dm1080 = VideoQuality.dailymotion('1080');
      expect(dm1080.isAuto, isFalse);
      expect(dm1080.id, '1080');
      expect(dm1080.height, 1080);
      expect(dm1080.shortLabel, '1080p');
      expect(dm1080.badgeDescription, 'Full HD');
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

    test('Bstation preset qualities and factory constructor', () {
      final bstationAuto = VideoQuality.bstation(
        id: 'auto',
        label: 'Auto (Otomatis Bstation)',
      );
      expect(bstationAuto.isAuto, isTrue);
      expect(bstationAuto.id, 'auto');
      expect(bstationAuto.shortLabel, 'Auto');
      expect(bstationAuto.mode, QualityControlMode.webviewBridge);

      final bstation720 = VideoQuality.bstation(
        id: '720',
        label: '720p HD',
        height: 720,
      );
      expect(bstation720.isAuto, isFalse);
      expect(bstation720.id, '720');
      expect(bstation720.height, 720);
      expect(bstation720.shortLabel, '720p');
      expect(bstation720.badgeDescription, 'HD Resolusi Tinggi');
      expect(bstation720.mode, QualityControlMode.webviewBridge);

      final bstation480 = VideoQuality.bstation(
        id: '480',
        label: '480p Standar',
        height: 480,
      );
      expect(bstation480.height, 480);
      expect(bstation480.shortLabel, '480p');
      expect(bstation480.badgeDescription, 'Standar Definition (SD)');

      final bstation360 = VideoQuality.bstation(
        id: '360',
        label: '360p Hemat',
        height: 360,
      );
      expect(bstation360.height, 360);
      expect(bstation360.shortLabel, '360p');
      expect(bstation360.badgeDescription, 'Hemat Kuota');
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

    test('buildStandardTiersUpTo generates descending resolution tiers up to maxHeight', () {
      final tiers720 = VideoQuality.buildStandardTiersUpTo(720, minHeight: 240);
      expect(tiers720, equals([720, 480, 360, 240]));

      final tiers2160 = VideoQuality.buildStandardTiersUpTo(2160, minHeight: 360);
      expect(tiers2160, equals([2160, 1440, 1080, 720, 480, 360]));
    });
  });
}

