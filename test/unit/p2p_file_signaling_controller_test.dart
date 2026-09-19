import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/core/network/p2p_file_stream_service.dart';
import 'package:nobarin/features/room/controllers/p2p_file_signaling_controller.dart';

void main() {
  group('P2PFileSignalingController Tests', () {
    test('Initialization and disposal lifecycle', () {
      final controller = P2PFileSignalingController(
        roomId: 'test-room-1',
        userId: 'user-1',
        userName: 'Tester',
        isHost: true,
      );

      expect(controller.isDisposed, isFalse);
      expect(controller.peerConnections, isEmpty);

      controller.dispose();
      expect(controller.isDisposed, isTrue);
    });

    test('P2PFileMetadata serialization round-trip', () {
      const metadata = P2PFileMetadata(
        fileName: 'test_video.mp4',
        fileSize: 10485760,
        mimeType: 'video/mp4',
        lanUrl: 'http://192.168.1.50:8080/video',
        hostUserId: 'host-1',
        hostUserName: 'HostUser',
      );

      final json = metadata.toJson();
      expect(json['file_name'], 'test_video.mp4');
      expect(json['file_size'], 10485760);
      expect(json['lan_url'], 'http://192.168.1.50:8080/video');
      expect(json['host_user_id'], 'host-1');

      final fromJson = P2PFileMetadata.fromJson(json);
      expect(fromJson.fileName, metadata.fileName);
      expect(fromJson.fileSize, metadata.fileSize);
      expect(fromJson.lanUrl, metadata.lanUrl);
      expect(fromJson.hostUserId, metadata.hostUserId);
      expect(fromJson.formattedSize, '10.0 MB');
    });
  });
}
