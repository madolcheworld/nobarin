import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/core/utils/ntp_clock_sync.dart';
import 'package:nobarin/features/room/controllers/sync_engine.dart';
import 'package:nobarin/features/room/models/sync_payload.dart';

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

    // -------------------------------------------------------------------------
    // Enhanced Tests: State-Aware & High-Precision Optimizations
    // -------------------------------------------------------------------------

    test('Paused state with drift > 50ms triggers hardSeek directly (never microSpeedUp)', () {
      const payload = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: 'https://example.com/video.mp4',
        state: 'paused',
        positionSeconds: 40.0,
        timestampMs: 1000000,
        controllerId: 'host-1',
      );

      // Client is at 40.4s (drift = 400ms). In paused mode, micro-speed cannot catch up!
      // Must return hardSeek so client seeks to exact frame 40.0s.
      final action = engine.evaluateCorrection(payload, 40.4, 1000000);
      expect(action, DriftAction.hardSeek);

      // Client is at 40.02s (drift = 20ms <= 50ms) -> noAction
      final tightAction = engine.evaluateCorrection(payload, 40.02, 1000000);
      expect(tightAction, DriftAction.noAction);
    });

    test('Explicit seek action triggers hardSeek directly', () {
      const payload = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: 'https://example.com/video.mp4',
        state: 'playing',
        positionSeconds: 85.0,
        timestampMs: 1000000,
        controllerId: 'host-1',
        action: 'seek',
      );

      // Even if drift is under 2.0s (e.g. 0.8s), explicit seek action must seek directly
      final action = engine.evaluateCorrection(payload, 84.2, 1000000);
      expect(action, DriftAction.hardSeek);
    });

    test('calculateAdaptiveSpeed provides smooth multi-tier proportional rates', () {
      const payload = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: 'https://example.com/video.mp4',
        state: 'playing',
        positionSeconds: 100.0,
        timestampMs: 1000000,
        playbackSpeed: 1.0,
        controllerId: 'host-1',
      );

      // Tier 0: Drift 50ms (< 80ms) -> 1.0x (in sync)
      expect(
        engine.calculateAdaptiveSpeed(
          payload: payload,
          currentLocalPositionSeconds: 99.95,
          currentTimestampMs: 1000000,
        ),
        1.0,
      );

      // Tier 1: Drift 200ms (80ms - 350ms) -> Ultra-fine 1.025x (lag) / 0.975x (lead)
      expect(
        engine.calculateAdaptiveSpeed(
          payload: payload,
          currentLocalPositionSeconds: 99.8,
          currentTimestampMs: 1000000,
        ),
        1.025,
      );
      expect(
        engine.calculateAdaptiveSpeed(
          payload: payload,
          currentLocalPositionSeconds: 100.2,
          currentTimestampMs: 1000000,
        ),
        0.975,
      );

      // Tier 2: Drift 600ms (350ms - 1000ms) -> Moderate 1.05x / 0.95x
      expect(
        engine.calculateAdaptiveSpeed(
          payload: payload,
          currentLocalPositionSeconds: 99.4,
          currentTimestampMs: 1000000,
        ),
        1.05,
      );
      expect(
        engine.calculateAdaptiveSpeed(
          payload: payload,
          currentLocalPositionSeconds: 100.6,
          currentTimestampMs: 1000000,
        ),
        0.95,
      );

      // Tier 3: Drift 1400ms (1000ms - 1800ms) -> Catch-up 1.08x / 0.92x
      expect(
        engine.calculateAdaptiveSpeed(
          payload: payload,
          currentLocalPositionSeconds: 98.6,
          currentTimestampMs: 1000000,
        ),
        1.08,
      );
      expect(
        engine.calculateAdaptiveSpeed(
          payload: payload,
          currentLocalPositionSeconds: 101.4,
          currentTimestampMs: 1000000,
        ),
        0.92,
      );

      // Tier 4: Drift >= 1800ms -> returns 1.0x (handed over to hard seek)
      expect(
        engine.calculateAdaptiveSpeed(
          payload: payload,
          currentLocalPositionSeconds: 95.0,
          currentTimestampMs: 1000000,
        ),
        1.0,
      );
    });

    test('calculateAdaptiveSpeed handles YouTube discrete playback rates', () {
      const payload = SyncPayload(
        mediaType: 'youtube',
        mediaUrl: 'https://youtube.com/watch?v=abc',
        state: 'playing',
        positionSeconds: 50.0,
        timestampMs: 1000000,
        controllerId: 'host-1',
      );

      // YouTube lag 600ms -> discrete 1.25x
      expect(
        engine.calculateAdaptiveSpeed(
          payload: payload,
          currentLocalPositionSeconds: 49.4,
          currentTimestampMs: 1000000,
          isYouTube: true,
        ),
        1.25,
      );

      // YouTube lead 600ms -> discrete 0.75x
      expect(
        engine.calculateAdaptiveSpeed(
          payload: payload,
          currentLocalPositionSeconds: 50.6,
          currentTimestampMs: 1000000,
          isYouTube: true,
        ),
        0.75,
      );
    });

    test('Exponential Moving Average (EMA) low-pass filter smooths noise spikes', () {
      engine.resetFilter();

      // Sample 1: Baseline 0.1s
      final s1 = engine.applyLowPassFilter(0.1);
      expect(s1, 0.1);

      // Sample 2: Sudden render spike to 0.8s
      // Filtered = 0.35 * 0.8 + 0.65 * 0.1 = 0.28 + 0.065 = 0.345
      final s2 = engine.applyLowPassFilter(0.8);
      expect(s2, closeTo(0.345, 0.001));

      // Reset works
      engine.resetFilter();
      expect(engine.applyLowPassFilter(0.5), 0.5);
    });

    test('Seek cooldown prevents rapid repeated seek thrashing', () {
      expect(engine.isSeekInCooldown(), isFalse);

      engine.recordSeek();
      expect(engine.isSeekInCooldown(), isTrue);

      // Custom zero-duration cooldown expires immediately
      expect(engine.isSeekInCooldown(Duration.zero), isFalse);
    });

    test('Target position calculation clamps to video duration if provided', () {
      const payload = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: 'https://example.com/video.mp4',
        state: 'playing',
        positionSeconds: 118.0,
        timestampMs: 1000000,
        playbackSpeed: 1.0,
        controllerId: 'host-1',
        maxDurationSeconds: 120.0,
      );

      // 5 seconds later -> 118.0 + 5.0 = 123.0s, clamped to maxDuration 120.0s
      final target = engine.calculateTargetPosition(payload, 1005000);
      expect(target, 120.0);
    });
  });
}
