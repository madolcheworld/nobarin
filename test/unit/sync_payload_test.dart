import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/room/models/sync_payload.dart';

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
        seqId: 42,
        action: 'play',
        actionEpoch: 1725514800000,
        maxDurationSeconds: 600.0,
      );

      final json = payload.toJson();
      expect(json['media_type'], 'youtube');
      expect(json['media_url'], 'https://youtube.com/watch?v=123');
      expect(json['state'], 'playing');
      expect(json['position_seconds'], 142.5);
      expect(json['timestamp_ms'], 1725514800000);
      expect(json['playback_speed'], 1.25);
      expect(json['controller_id'], 'user-456');
      expect(json['seq_id'], 42);
      expect(json['action'], 'play');
      expect(json['action_epoch'], 1725514800000);
      expect(json['max_duration_seconds'], 600.0);

      final fromJson = SyncPayload.fromJson(json);
      expect(fromJson.mediaType, payload.mediaType);
      expect(fromJson.mediaUrl, payload.mediaUrl);
      expect(fromJson.state, payload.state);
      expect(fromJson.positionSeconds, payload.positionSeconds);
      expect(fromJson.timestampMs, payload.timestampMs);
      expect(fromJson.playbackSpeed, payload.playbackSpeed);
      expect(fromJson.controllerId, payload.controllerId);
      expect(fromJson.seqId, 42);
      expect(fromJson.action, 'play');
      expect(fromJson.actionEpoch, 1725514800000);
      expect(fromJson.maxDurationSeconds, 600.0);
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

      final updated = payload.copyWith(
        state: 'playing',
        positionSeconds: 10.0,
        seqId: 5,
        action: 'seek',
      );
      expect(updated.state, 'playing');
      expect(updated.positionSeconds, 10.0);
      expect(updated.mediaUrl, payload.mediaUrl);
      expect(updated.seqId, 5);
      expect(updated.action, 'seek');
    });
  });
}
