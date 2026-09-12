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

    test('Vimeo and Dailymotion preset qualities', () {
      final vimeoPresets = [
        const VideoQuality.auto(),
        const VideoQuality(id: '1080p', label: '1080p (Full HD)', height: 1080),
        const VideoQuality(id: '720p', label: '720p (HD)', height: 720),
        const VideoQuality(id: '540p', label: '540p (SD)', height: 540),
        const VideoQuality(id: '360p', label: '360p (Hemat Kuota)', height: 360),
      ];

      expect(vimeoPresets.any((q) => q.isAuto), isTrue);
      expect(vimeoPresets.any((q) => q.id == '1080p'), isTrue);
      expect(vimeoPresets.any((q) => q.id == '720p'), isTrue);
      expect(vimeoPresets.any((q) => q.id == '360p'), isTrue);
    });
  });
}
