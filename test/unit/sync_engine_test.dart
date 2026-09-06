import 'package:flutter_test/flutter_test.dart';
import 'package:watch_party/core/utils/ntp_clock_sync.dart';
import 'package:watch_party/features/room/controllers/sync_engine.dart';
import 'package:watch_party/features/room/models/sync_payload.dart';

void main() {
  group('SyncEngine Drift & Correction Tests', () {
    late NtpClockSync clockSync;
    late SyncEngine engine;

    setUp(() {
      clockSync = NtpClockSync();
      clockSync.setClockOffset(0);
      engine = SyncEngine(clockSync: clockSync);
    });

    test('calculateTargetPosition returns identical position when paused', () {
      const payload = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: 'https://example.com/video.mp4',
        state: 'paused',
        positionSeconds: 45.0,
        timestampMs: 1000000,
        controllerId: 'host-1',
      );

      // Even after 5 seconds, paused video target position remains 45.0
      final target = engine.calculateTargetPosition(payload, 1005000);
      expect(target, 45.0);
    });

    test('calculateTargetPosition extrapolates position accurately when playing',
        () {
      const payload = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: 'https://example.com/video.mp4',
        state: 'playing',
        positionSeconds: 10.0,
        timestampMs: 1000000,
        playbackSpeed: 1.0,
        controllerId: 'host-1',
      );

      // 3 seconds later at 1.0x speed -> 10.0 + 3.0 = 13.0
      final target = engine.calculateTargetPosition(payload, 1003000);
      expect(target, 13.0);

      // 3 seconds later at 1.5x speed -> 10.0 + (3.0 * 1.5) = 14.5
      final speedPayload = payload.copyWith(playbackSpeed: 1.5);
      final speedTarget = engine.calculateTargetPosition(speedPayload, 1003000);
      expect(speedTarget, 14.5);
    });

    test('Drift < 300ms is treated as jitter tolerance (no action)', () {
      const payload = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: 'https://example.com/video.mp4',
        state: 'playing',
        positionSeconds: 20.0,
        timestampMs: 1000000,
        controllerId: 'host-1',
      );

      // Target position = 20.0 + 1.0s = 21.0s
      // Local position = 20.85s (Drift = 0.15s = 150ms < 300ms)
      final action = engine.evaluateCorrection(payload, 20.85, 1001000);
      expect(action, DriftAction.noAction);
    });

    test('300ms <= Drift < 2000ms triggers micro-adjustment (speed up/down)',
        () {
      const payload = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: 'https://example.com/video.mp4',
        state: 'playing',
        positionSeconds: 50.0,
        timestampMs: 1000000,
        controllerId: 'host-1',
      );

      // Target = 50.0s (at t=1000000)
      // Client is at 49.2s (lagging behind by 0.8s = 800ms)
      final lagAction = engine.evaluateCorrection(payload, 49.2, 1000000);
      expect(lagAction, DriftAction.microSpeedUp);
      expect(engine.getRecommendedSpeed(lagAction), 1.06);

      // Client is at 50.8s (ahead of host by 0.8s = 800ms)
      final leadAction = engine.evaluateCorrection(payload, 50.8, 1000000);
      expect(leadAction, DriftAction.microSlowDown);
      expect(engine.getRecommendedSpeed(leadAction), 0.94);
    });

    test('Drift >= 2000ms triggers Hard Seek', () {
      const payload = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: 'https://example.com/video.mp4',
        state: 'playing',
        positionSeconds: 100.0,
        timestampMs: 1000000,
        controllerId: 'host-1',
      );

      // Target = 100.0s
      // Client is at 95.0s (lagging by 5.0s = 5000ms >= 2000ms)
      final action = engine.evaluateCorrection(payload, 95.0, 1000000);
      expect(action, DriftAction.hardSeek);
      expect(engine.getRecommendedSpeed(action), 1.0);
    });

    test('NTP Clock Offset is factored into target position calculation', () {
      // Suppose local clock is 2000ms behind server (clockOffsetMs = +2000)
      clockSync.setClockOffset(2000);

      const payload = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: 'https://example.com/video.mp4',
        state: 'playing',
        positionSeconds: 10.0,
        timestampMs: 5000, // server timestamp
        controllerId: 'host-1',
      );

      // If local clock is 3000ms, synchronized time is 3000 + 2000 = 5000ms.
      // Delta = 5000 - 5000 = 0. Target = 10.0
      final target = engine.calculateTargetPosition(payload, 5000);
      expect(target, 10.0);
      expect(clockSync.synchronizedTimestampMs >= 0, isTrue);
      expect(clockSync.clockOffsetMs, 2000);
    });
  });
}
