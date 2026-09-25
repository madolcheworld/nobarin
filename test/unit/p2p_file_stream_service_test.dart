import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/core/network/local_media_server.dart';
import 'package:nobarin/core/network/p2p_file_stream_service.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File sampleFile;
  late P2PFileStreamService service;
  late LocalMediaServer localMediaServer;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nobarin_p2p_test_');
    sampleFile = File('${tempDir.path}/anime_episode_01.mp4');
    await sampleFile.writeAsBytes(List.filled(2048, 42));

    localMediaServer = LocalMediaServer();
    service = P2PFileStreamService.withDependencies(
      localMediaServer: localMediaServer,
    );
  });

  tearDown(() async {
    await service.reset();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('P2PFileStreamService Tests', () {
    test('P2PFileMetadata formatting and JSON serialization', () {
      const meta = P2PFileMetadata(
        fileName: 'sample_movie.mp4',
        fileSize: 154201948, // ~147.1 MB
        mimeType: 'video/mp4',
        lanUrl: 'http://192.168.1.50:8888/video',
        hostUserId: 'user-host-1',
        hostUserName: 'SuperHost',
      );

      expect(meta.formattedSize, equals('147.1 MB'));

      final json = meta.toJson();
      expect(json['file_name'], equals('sample_movie.mp4'));
      expect(json['file_size'], equals(154201948));
      expect(json['lan_url'], equals('http://192.168.1.50:8888/video'));

      final deserialized = P2PFileMetadata.fromJson(json);
      expect(deserialized.fileName, equals(meta.fileName));
      expect(deserialized.fileSize, equals(meta.fileSize));
      expect(deserialized.lanUrl, equals(meta.lanUrl));
      expect(deserialized.hostUserId, equals(meta.hostUserId));
      expect(deserialized.hostUserName, equals(meta.hostUserName));
    });

    test('hostFile starts local media server and populates active metadata', () async {
      final metadata = await service.hostFile(
        filePath: sampleFile.path,
        hostUserId: 'user-123',
        hostUserName: 'TestHost',
      );

      expect(service.isHosting, isTrue);
      expect(service.hostedFilePath, equals(sampleFile.path));
      expect(metadata.fileName, equals('anime_episode_01.mp4'));
      expect(metadata.fileSize, equals(2048));
      expect(metadata.mimeType, equals('video/mp4'));
      expect(metadata.hostUserId, equals('user-123'));
      expect(service.localMediaServer.isRunning, isTrue);
    });

    test('local override (Syncplay mode) management', () {
      expect(service.hasLocalOverride, isFalse);
      expect(service.localOverrideFilePath, isNull);

      service.setLocalOverride('/storage/emulated/0/Download/same_anime.mp4');
      expect(service.hasLocalOverride, isTrue);
      expect(service.localOverrideFilePath, equals('/storage/emulated/0/Download/same_anime.mp4'));

      service.clearLocalOverride();
      expect(service.hasLocalOverride, isFalse);
      expect(service.localOverrideFilePath, isNull);
    });

    test('reset clears hosting, metadata, and stops servers', () async {
      await service.hostFile(
        filePath: sampleFile.path,
        hostUserId: 'user-123',
      );
      expect(service.isHosting, isTrue);

      await service.reset();
      expect(service.isHosting, isFalse);
      expect(service.hostedFilePath, isNull);
      expect(service.activeMetadata, isNull);
      expect(service.localMediaServer.isRunning, isFalse);
    });

    test('UnifiedPlayerController correctly detects local files and P2P streams', () {
      // Local path
      final localDetected = UnifiedPlayerController.detectMediaFromUrl(sampleFile.path);
      expect(localDetected, isNotNull);
      expect(localDetected!.isDirectUrl, isTrue);
      expect(localDetected.mediaUrl, equals(sampleFile.path));
      expect(localDetected.title, equals('anime episode 01'));

      // Windows local path
      final winDetected = UnifiedPlayerController.detectMediaFromUrl(r'C:\Videos\Movie.mkv');
      expect(winDetected, isNotNull);
      expect(winDetected!.title, equals('Movie'));

      // P2P scheme
      final p2pDetected = UnifiedPlayerController.detectMediaFromUrl('p2p://room_101/video.mp4');
      expect(p2pDetected, isNotNull);
      expect(p2pDetected!.isDirectUrl, isTrue);

      // Player properties
      final controller = UnifiedPlayerController();
      expect(controller.isLocalFile, isFalse);
      expect(controller.isP2PStream, isFalse);
      controller.dispose();
    });
  });
}
