import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/core/utils/ntp_clock_sync.dart';
import 'package:nobarin/features/room/controllers/sync_engine.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/models/sync_payload.dart';

void main() {
  group('Media Sources Synchronization Test Suite', () {
    late NtpClockSync clockSync;
    late SyncEngine syncEngine;

    setUp(() {
      clockSync = NtpClockSync();
      clockSync.setClockOffset(0);
      syncEngine = SyncEngine(clockSync: clockSync);
    });

    // -------------------------------------------------------------------------
    // 1. Direct Video URL (MP4 / HLS .m3u8) Synchronization
    // -------------------------------------------------------------------------
    group('1. Direct Video URL Sync', () {
      const directUrl =
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';

      test('Host Play action syncs state and extrapolates position for Viewer', () {
        const hostTimestamp = 1000000;
        final payload = SyncPayload(
          mediaType: 'direct_url',
          mediaUrl: directUrl,
          state: 'playing',
          positionSeconds: 15.0,
          timestampMs: hostTimestamp,
          playbackSpeed: 1.0,
          controllerId: 'host-user',
        );

        // Viewer receives packet 1200ms later (1.2s of network delay)
        const viewerReceiveTime = hostTimestamp + 1200;
        final targetPos =
            syncEngine.calculateTargetPosition(payload, viewerReceiveTime);

        // Expected: 15.0 + 1.2 = 16.2 seconds
        expect(targetPos, closeTo(16.2, 0.001));
      });

      test('Host Pause action freezes position for Viewer', () {
        const hostTimestamp = 1000000;
        final payload = SyncPayload(
          mediaType: 'direct_url',
          mediaUrl: directUrl,
          state: 'paused',
          positionSeconds: 42.5,
          timestampMs: hostTimestamp,
          controllerId: 'host-user',
        );

        // Viewer receives 5 seconds later
        final targetPos =
            syncEngine.calculateTargetPosition(payload, hostTimestamp + 5000);
        expect(targetPos, 42.5);
      });

      test('Direct URL Drift correction tiering (Jitter, Micro-Speed, Hard Seek)', () {
        const hostTimestamp = 1000000;
        final payload = SyncPayload(
          mediaType: 'direct_url',
          mediaUrl: directUrl,
          state: 'playing',
          positionSeconds: 100.0,
          timestampMs: hostTimestamp,
          controllerId: 'host-user',
        );

        // Case A: Jitter (< 300ms drift) -> No action
        var action =
            syncEngine.evaluateCorrection(payload, 100.15, hostTimestamp);
        expect(action, DriftAction.noAction);

        // Case B: Lagging 800ms (300ms - 2000ms) -> Micro speed up (1.06x)
        action = syncEngine.evaluateCorrection(payload, 99.2, hostTimestamp);
        expect(action, DriftAction.microSpeedUp);
        expect(syncEngine.getRecommendedSpeed(action), 1.06);

        // Case C: Ahead 800ms (300ms - 2000ms) -> Micro slow down (0.94x)
        action = syncEngine.evaluateCorrection(payload, 100.8, hostTimestamp);
        expect(action, DriftAction.microSlowDown);
        expect(syncEngine.getRecommendedSpeed(action), 0.94);

        // Case D: Desync >= 2000ms -> Hard Seek
        action = syncEngine.evaluateCorrection(payload, 95.0, hostTimestamp);
        expect(action, DriftAction.hardSeek);
      });

      test('Direct URL media detection correctly parses URL', () {
        final detected = UnifiedPlayerController.detectMediaFromUrl(directUrl);
        expect(detected, isNotNull);
        expect(detected!.mediaType, 'direct_url');
        expect(detected.mediaUrl, directUrl);
        expect(detected.isDirectUrl, isTrue);
      });
    });
  });
}
