import 'package:flutter_test/flutter_test.dart';
import 'package:watch_party/features/room/models/sync_payload.dart';

void main() {
  group('SyncPayload Model Tests', () {
    test('JSON serialization & deserialization round-trip', () {
      final payload = SyncPayload(
        mediaType: 'youtube',
        mediaUrl: 'https://youtube.com/watch?v=123',
        state: 'playing',
        positionSeconds: 142.5,
        timestampMs: 1725514800000,
        playbackSpeed: 1.25,
        controllerId: 'user-456',
      );

      final json = payload.toJson();
      expect(json['media_type'], 'youtube');
      expect(json['media_url'], 'https://youtube.com/watch?v=123');
      expect(json['state'], 'playing');
      expect(json['position_seconds'], 142.5);
      expect(json['timestamp_ms'], 1725514800000);
      expect(json['playback_speed'], 1.25);
      expect(json['controller_id'], 'user-456');

      final fromJson = SyncPayload.fromJson(json);
      expect(fromJson.mediaType, payload.mediaType);
      expect(fromJson.mediaUrl, payload.mediaUrl);
      expect(fromJson.state, payload.state);
      expect(fromJson.positionSeconds, payload.positionSeconds);
      expect(fromJson.timestampMs, payload.timestampMs);
      expect(fromJson.playbackSpeed, payload.playbackSpeed);
      expect(fromJson.controllerId, payload.controllerId);
      expect(fromJson.isPlaying, isTrue);
      expect(fromJson.isPaused, isFalse);
    });

    test('copyWith works correctly', () {
      const payload = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: 'https://example.com/v.mp4',
        state: 'paused',
        positionSeconds: 0.0,
        timestampMs: 1000,
        controllerId: 'user-1',
      );

      final updated = payload.copyWith(state: 'playing', positionSeconds: 10.0);
      expect(updated.state, 'playing');
      expect(updated.positionSeconds, 10.0);
      expect(updated.mediaUrl, payload.mediaUrl);
    });
  });
}
