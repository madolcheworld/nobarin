import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/lobby/data/google_drive_service.dart';
import 'package:nobarin/features/lobby/data/models/google_drive_video_model.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/models/queue_item.dart';

void main() {
  group('GoogleDriveVideo Model Tests', () {
    test('instantiates with proper getters', () {
      const video = GoogleDriveVideo(
        id: '1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8',
        title: 'Tears of Steel (Sci-Fi 4K)',
        category: 'Trailer & Demo 4K',
        duration: '12:14',
        fileSize: '1.2 GB',
        ownerName: 'Blender Foundation',
        thumbnailUrl: 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=600',
      );

      expect(video.id, '1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8');
      expect(video.url, 'https://drive.google.com/file/d/1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8/view?usp=sharing');
      expect(video.previewUrl, 'https://drive.google.com/file/d/1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8/preview');
      expect(video.downloadUrl, 'https://drive.google.com/uc?export=download&id=1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8');
      expect(video.driveThumbnailUrl, 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=600');
      expect(video.category, 'Trailer & Demo 4K');
      expect(video.duration, '12:14');
      expect(video.fileSize, '1.2 GB');
      expect(video.ownerName, 'Blender Foundation');
    });

    test('fromId generates correct defaults', () {
      final video = GoogleDriveVideo.fromId('1B_w69jZ-bV5X8oK1234567890abcdef');
      expect(video.id, '1B_w69jZ-bV5X8oK1234567890abcdef');
      expect(video.title, 'Google Drive Video (1B_w69jZ-bV5X8oK1234567890abcdef)');
      expect(video.url, 'https://drive.google.com/file/d/1B_w69jZ-bV5X8oK1234567890abcdef/view?usp=sharing');
      expect(video.previewUrl, 'https://drive.google.com/file/d/1B_w69jZ-bV5X8oK1234567890abcdef/preview');
      expect(video.category, 'Koleksi Drive');
    });

    test('toJson and fromJson work symmetrically', () {
      const video = GoogleDriveVideo(
        id: '1aBcDeFgHiJkLmNoPqRsTuVwXyZ123456',
        title: 'Big Buck Bunny (Full HD)',
        category: 'Film & Animasi Open Source',
        duration: '09:56',
        fileSize: '850 MB',
        ownerName: 'Blender Institute',
        thumbnailUrl: 'https://images.unsplash.com/photo-1534447677768-be436bb09401?w=600',
      );

      final json = video.toJson();
      final fromJson = GoogleDriveVideo.fromJson(json);

      expect(fromJson.id, video.id);
      expect(fromJson.title, video.title);
      expect(fromJson.category, video.category);
      expect(fromJson.duration, video.duration);
      expect(fromJson.fileSize, video.fileSize);
      expect(fromJson.ownerName, video.ownerName);
      expect(fromJson.thumbnailUrl, video.thumbnailUrl);
    });
  });

  group('GoogleDriveService Tests', () {
    test('extractFileId parses /file/d/{id} URLs', () {
      const url = 'https://drive.google.com/file/d/1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8/view?usp=sharing';
      expect(GoogleDriveService.extractFileId(url), '1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8');
    });

    test('extractFileId parses /open?id={id} URLs', () {
      const url = 'https://drive.google.com/open?id=1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8';
      expect(GoogleDriveService.extractFileId(url), '1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8');
    });

    test('extractFileId parses /uc?id={id} URLs', () {
      const url = 'https://drive.google.com/uc?id=1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8&export=download';
      expect(GoogleDriveService.extractFileId(url), '1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8');
    });

    test('extractFileId parses raw Drive ID', () {
      const rawId = '1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8';
      expect(GoogleDriveService.extractFileId(rawId), rawId);
    });

    test('extractFileId returns null for invalid strings', () {
      expect(GoogleDriveService.extractFileId(''), isNull);
      expect(GoogleDriveService.extractFileId('https://youtube.com/watch?v=123'), isNull);
      expect(GoogleDriveService.extractFileId('short_id'), isNull);
    });

    test('categoryPresets has categories and valid videos', () {
      final presets = GoogleDriveService.categoryPresets;
      expect(presets.keys, contains('Film & Animasi Open Source'));
      expect(presets.keys, contains('Trailer & Demo 4K'));
      expect(presets.keys, contains('Dokumenter & Sains'));

      for (final entry in presets.entries) {
        expect(entry.value, isNotEmpty);
        for (final video in entry.value) {
          expect(video.id, isNotEmpty);
          expect(video.title, isNotEmpty);
          expect(video.previewUrl, contains('/preview'));
        }
      }
    });

    test('search filters videos correctly', () async {
      final bunnyResults = await GoogleDriveService.search('bunny');
      expect(bunnyResults, isNotEmpty);
      expect(bunnyResults.first.title.toLowerCase(), contains('bunny'));

      final demoResults = await GoogleDriveService.search('4k');
      expect(demoResults, isNotEmpty);

      final emptyResults = await GoogleDriveService.search('random nonexistent movie query');
      expect(emptyResults, isEmpty);
    });
  });

  group('UnifiedPlayerController Google Drive Tests', () {
    test('extractGoogleDriveFileId works identically', () {
      const url = 'https://drive.google.com/file/d/1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8/preview';
      expect(UnifiedPlayerController.extractGoogleDriveFileId(url), '1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8');
    });
  });

  group('QueueItem Google Drive Tests', () {
    test('isGoogleDrive returns true for google_drive and gdrive', () {
      final item1 = QueueItem(
        id: '1',
        roomId: 'room1',
        mediaType: 'google_drive',
        mediaUrl: 'https://drive.google.com/file/d/1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8/view',
        title: 'Sintel 4K',
        addedByUserId: 'u1',
        addedByUserName: 'Host',
        createdAt: DateTime.now(),
      );

      final item2 = QueueItem(
        id: '2',
        roomId: 'room1',
        mediaType: 'gdrive',
        mediaUrl: 'https://drive.google.com/file/d/1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8/view',
        title: 'Sintel 4K',
        addedByUserId: 'u1',
        addedByUserName: 'Host',
        createdAt: DateTime.now(),
      );

      final item3 = QueueItem(
        id: '3',
        roomId: 'room1',
        mediaType: 'youtube',
        mediaUrl: 'https://youtu.be/test',
        title: 'YT Video',
        addedByUserId: 'u1',
        addedByUserName: 'Host',
        createdAt: DateTime.now(),
      );

      expect(item1.isGoogleDrive, isTrue);
      expect(item2.isGoogleDrive, isTrue);
      expect(item3.isGoogleDrive, isFalse);
    });
  });
}
