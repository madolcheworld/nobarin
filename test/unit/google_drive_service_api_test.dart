import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nobarin/features/lobby/data/google_drive_service.dart';
import 'package:nobarin/features/lobby/data/models/google_drive_video_model.dart';

void main() {
  group('GoogleDriveVideo fromDriveApiJson Tests', () {
    test('correctly parses public file with video metadata', () {
      final json = {
        'id': 'file_drive_101',
        'name': 'Open_Source_Film.mp4',
        'mimeType': 'video/mp4',
        'thumbnailLink': 'https://lh3.googleusercontent.com/sample_thumb',
        'size': '${500 * 1024 * 1024}', // 500 MB
        'videoMediaMetadata': {
          'durationMillis': '${(12 * 60 + 30) * 1000}', // 12m 30s
        },
        'permissions': [
          {'role': 'owner', 'type': 'user'},
          {'role': 'reader', 'type': 'anyone'},
        ],
      };

      final video = GoogleDriveVideo.fromDriveApiJson(json);

      expect(video.id, 'file_drive_101');
      expect(video.title, 'Open_Source_Film.mp4');
      expect(video.thumbnailUrl, 'https://lh3.googleusercontent.com/sample_thumb');
      expect(video.duration, '12:30');
      expect(video.fileSize, contains('500'));
      expect(video.isPublic, isTrue);
    });

    test('correctly parses private file without anyone permission', () {
      final json = {
        'id': 'file_drive_private',
        'name': 'Tugas_Kuliah_Private.mov',
        'mimeType': 'video/quicktime',
        'size': '${1200 * 1024 * 1024}', // ~1.17 GB
        'videoMediaMetadata': {
          'durationMillis': '${(1 * 3600 + 5 * 60 + 10) * 1000}', // 1h 5m 10s
        },
        'permissions': [
          {'role': 'owner', 'type': 'user'},
        ],
      };

      final video = GoogleDriveVideo.fromDriveApiJson(json);

      expect(video.id, 'file_drive_private');
      expect(video.title, 'Tugas_Kuliah_Private.mov');
      expect(video.duration, '01:05:10');
      expect(video.fileSize, contains('GB'));
      expect(video.isPublic, isFalse);
    });
  });

  group('GoogleDriveService User Videos API Tests', () {
    setUp(() {
      GoogleDriveService.resetMockVideos();
    });

    test('fetchUserVideos in mock mode returns mock personal videos', () async {
      final videos = await GoogleDriveService.fetchUserVideos(isMock: true);

      expect(videos, isNotEmpty);
      expect(videos.any((v) => v.title.contains('Liburan')), isTrue);
      expect(videos.any((v) => !v.isPublic), isTrue);
    });

    test('fetchUserVideos with query filters mock personal videos', () async {
      final videos = await GoogleDriveService.fetchUserVideos(
        query: 'sunset',
        isMock: true,
      );

      expect(videos.length, 1);
      expect(videos.first.title, contains('Sunset'));
    });

    test('fetchUserVideos parses real Google Drive v3 REST API response', () async {
      final mockApiResponse = {
        'files': [
          {
            'id': 'real_drive_file_1',
            'name': 'Nature_Documentary_FHD.mp4',
            'mimeType': 'video/mp4',
            'thumbnailLink': 'https://drive.google.com/thumb1',
            'size': '209715200',
            'videoMediaMetadata': {'durationMillis': '600000'},
            'permissions': [
              {'type': 'anyone', 'role': 'reader'}
            ],
          },
        ]
      };

      final client = MockClient((request) async {
        expect(request.url.host, 'www.googleapis.com');
        expect(request.url.path, '/drive/v3/files');
        expect(request.headers['Authorization'], 'Bearer valid_test_token');
        return http.Response(jsonEncode(mockApiResponse), 200);
      });

      final videos = await GoogleDriveService.fetchUserVideos(
        accessToken: 'valid_test_token',
        client: client,
        isMock: false,
      );

      expect(videos.length, 1);
      expect(videos.first.id, 'real_drive_file_1');
      expect(videos.first.title, 'Nature_Documentary_FHD.mp4');
      expect(videos.first.isPublic, isTrue);
    });

    test('makeFileAccessibleToRoom updates mock video to public', () async {
      final initialVideos = await GoogleDriveService.fetchUserVideos(isMock: true);
      final privateVideo = initialVideos.firstWhere((v) => !v.isPublic);

      final success = await GoogleDriveService.makeFileAccessibleToRoom(
        privateVideo.id,
        isMock: true,
      );

      expect(success, isTrue);

      final updatedVideos = await GoogleDriveService.fetchUserVideos(isMock: true);
      final updatedVideo = updatedVideos.firstWhere((v) => v.id == privateVideo.id);
      expect(updatedVideo.isPublic, isTrue);
    });

    test('makeFileAccessibleToRoom sends permissions POST request to Drive API', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'www.googleapis.com');
        expect(request.url.path, '/drive/v3/files/test_file_id/permissions');
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer valid_test_token');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['role'], 'reader');
        expect(body['type'], 'anyone');

        return http.Response('{"id": "perm_id_123"}', 200);
      });

      final success = await GoogleDriveService.makeFileAccessibleToRoom(
        'test_file_id',
        accessToken: 'valid_test_token',
        client: client,
        isMock: false,
      );

      expect(success, isTrue);
    });
  });
}
