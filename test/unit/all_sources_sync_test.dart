import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/core/utils/ntp_clock_sync.dart';
import 'package:nobarin/features/room/controllers/sync_engine.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/models/sync_payload.dart';

void main() {
  group('Media Sources Synchronization Test Suite (All Sources)', () {
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

    // -------------------------------------------------------------------------
    // 2. Dailymotion Video Synchronization
    // -------------------------------------------------------------------------
    group('2. Dailymotion Sync', () {
      const dailymotionUrl = 'https://www.dailymotion.com/video/x7tgad0';

      test('Host Play action syncs state and extrapolates position for Viewer', () {
        const hostTimestamp = 1000000;
        final payload = SyncPayload(
          mediaType: 'dailymotion',
          mediaUrl: dailymotionUrl,
          state: 'playing',
          positionSeconds: 20.0,
          timestampMs: hostTimestamp,
          playbackSpeed: 1.0,
          controllerId: 'host-user',
        );

        // Viewer receives packet 1000ms later (1.0s network delay)
        const viewerReceiveTime = hostTimestamp + 1000;
        final targetPos =
            syncEngine.calculateTargetPosition(payload, viewerReceiveTime);

        // Expected: 20.0 + 1.0 = 21.0 seconds
        expect(targetPos, closeTo(21.0, 0.001));
      });

      test('Host Pause action freezes position for Viewer', () {
        const hostTimestamp = 1000000;
        final payload = SyncPayload(
          mediaType: 'dailymotion',
          mediaUrl: dailymotionUrl,
          state: 'paused',
          positionSeconds: 55.0,
          timestampMs: hostTimestamp,
          controllerId: 'host-user',
        );

        final targetPos =
            syncEngine.calculateTargetPosition(payload, hostTimestamp + 4000);
        expect(targetPos, 55.0);
      });

      test('Dailymotion media detection correctly parses standard and short URLs', () {
        final detectedStd =
            UnifiedPlayerController.detectMediaFromUrl(dailymotionUrl);
        expect(detectedStd, isNotNull);
        expect(detectedStd!.mediaType, 'dailymotion');
        expect(detectedStd.mediaId, 'x7tgad0');
        expect(detectedStd.isDailymotion, isTrue);

        final detectedShort =
            UnifiedPlayerController.detectMediaFromUrl('https://dai.ly/x7tgad0');
        expect(detectedShort, isNotNull);
        expect(detectedShort!.mediaType, 'dailymotion');
        expect(detectedShort.mediaId, 'x7tgad0');
      });
    });

    // -------------------------------------------------------------------------
    // 3. YouTube Video Synchronization & Discrete Rate Slewing
    // -------------------------------------------------------------------------
    group('3. YouTube Sync', () {
      const ytUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';

      test('Host Play and Pause actions synchronize accurately', () {
        const hostTimestamp = 1000000;
        final playPayload = SyncPayload(
          mediaType: 'youtube',
          mediaUrl: ytUrl,
          state: 'playing',
          positionSeconds: 60.0,
          timestampMs: hostTimestamp,
          controllerId: 'host-user',
        );

        // 800ms transit delay
        final playTarget =
            syncEngine.calculateTargetPosition(playPayload, hostTimestamp + 800);
        expect(playTarget, closeTo(60.8, 0.001));

        final pausePayload = SyncPayload(
          mediaType: 'youtube',
          mediaUrl: ytUrl,
          state: 'paused',
          positionSeconds: 60.8,
          timestampMs: hostTimestamp,
          controllerId: 'host-user',
        );
        final pauseTarget =
            syncEngine.calculateTargetPosition(pausePayload, hostTimestamp + 3000);
        expect(pauseTarget, 60.8);
      });

      test('YouTube IFrame API enforces discrete playback speed adjustments (1.25x / 0.75x)', () {
        const hostTimestamp = 1000000;
        final payload = SyncPayload(
          mediaType: 'youtube',
          mediaUrl: ytUrl,
          state: 'playing',
          positionSeconds: 100.0,
          timestampMs: hostTimestamp,
          controllerId: 'host-user',
        );

        // Case A: Lagging 800ms (within 0.4s - 1.8s) -> 1.25x discrete YouTube rate
        final speedUp = syncEngine.calculateAdaptiveSpeed(
          payload: payload,
          currentLocalPositionSeconds: 99.2,
          currentTimestampMs: hostTimestamp,
          isYouTube: true,
        );
        expect(speedUp, 1.25);

        // Case B: Ahead 800ms (within 0.4s - 1.8s) -> 0.75x discrete YouTube rate
        final slowDown = syncEngine.calculateAdaptiveSpeed(
          payload: payload,
          currentLocalPositionSeconds: 100.8,
          currentTimestampMs: hostTimestamp,
          isYouTube: true,
        );
        expect(slowDown, 0.75);

        // Case C: Deadband (< 0.4s drift) -> 1.0x normal speed
        final inSyncSpeed = syncEngine.calculateAdaptiveSpeed(
          payload: payload,
          currentLocalPositionSeconds: 100.2,
          currentTimestampMs: hostTimestamp,
          isYouTube: true,
        );
        expect(inSyncSpeed, 1.0);
      });

      test('YouTube media detection correctly parses watch, youtu.be, and shorts URLs', () {
        final d1 = UnifiedPlayerController.detectMediaFromUrl(ytUrl);
        expect(d1, isNotNull);
        expect(d1!.mediaType, 'youtube');
        expect(d1.mediaId, 'dQw4w9WgXcQ');
        expect(d1.isYoutube, isTrue);

        final d2 = UnifiedPlayerController.detectMediaFromUrl('https://youtu.be/dQw4w9WgXcQ');
        expect(d2, isNotNull);
        expect(d2!.mediaType, 'youtube');
        expect(d2.mediaId, 'dQw4w9WgXcQ');

        final d3 = UnifiedPlayerController.detectMediaFromUrl('https://m.youtube.com/shorts/dQw4w9WgXcQ');
        expect(d3, isNotNull);
        expect(d3!.mediaType, 'youtube');
        expect(d3.mediaId, 'dQw4w9WgXcQ');
      });
    });

    // -------------------------------------------------------------------------
    // 4. Bstation (Bilibili) Video Synchronization
    // -------------------------------------------------------------------------
    group('4. Bstation / Bilibili Sync', () {
      const bstationUrl = 'https://www.bilibili.tv/id/play/1004884';

      test('Host Play and Pause synchronization', () {
        const hostTimestamp = 1000000;
        final playPayload = SyncPayload(
          mediaType: 'bstation',
          mediaUrl: bstationUrl,
          state: 'playing',
          positionSeconds: 120.0,
          timestampMs: hostTimestamp,
          controllerId: 'host-user',
        );

        // 500ms delay
        final target =
            syncEngine.calculateTargetPosition(playPayload, hostTimestamp + 500);
        expect(target, closeTo(120.5, 0.001));

        final pausePayload = SyncPayload(
          mediaType: 'bstation',
          mediaUrl: bstationUrl,
          state: 'paused',
          positionSeconds: 120.5,
          timestampMs: hostTimestamp,
          controllerId: 'host-user',
        );
        expect(
          syncEngine.calculateTargetPosition(pausePayload, hostTimestamp + 2000),
          120.5,
        );
      });

      test('Bstation continuous proportional slewing (1.05x / 0.95x)', () {
        const hostTimestamp = 1000000;
        final payload = SyncPayload(
          mediaType: 'bstation',
          mediaUrl: bstationUrl,
          state: 'playing',
          positionSeconds: 100.0,
          timestampMs: hostTimestamp,
          controllerId: 'host-user',
        );

        // Lagging 600ms -> 1.05x
        final speedUp = syncEngine.calculateAdaptiveSpeed(
          payload: payload,
          currentLocalPositionSeconds: 99.4,
          currentTimestampMs: hostTimestamp,
          isYouTube: false,
        );
        expect(speedUp, 1.05);

        // Ahead 600ms -> 0.95x
        final slowDown = syncEngine.calculateAdaptiveSpeed(
          payload: payload,
          currentLocalPositionSeconds: 100.6,
          currentTimestampMs: hostTimestamp,
          isYouTube: false,
        );
        expect(slowDown, 0.95);
      });

      test('Bstation media detection parses bilibili.tv, bilibili.com, and b23.tv', () {
        final d1 = UnifiedPlayerController.detectMediaFromUrl(bstationUrl);
        expect(d1, isNotNull);
        expect(d1!.mediaType, 'bstation');
        expect(d1.isBstation, isTrue);

        final d2 = UnifiedPlayerController.detectMediaFromUrl('https://www.bilibili.com/video/BV1xx411c7mD');
        expect(d2, isNotNull);
        expect(d2!.mediaType, 'bstation');

        final d3 = UnifiedPlayerController.detectMediaFromUrl('https://b23.tv/abc1234');
        expect(d3, isNotNull);
        expect(d3!.mediaType, 'bstation');
      });
    });

    // -------------------------------------------------------------------------
    // 5. Google Drive Video Synchronization
    // -------------------------------------------------------------------------
    group('5. Google Drive Sync', () {
      const gdriveUrl = 'https://drive.google.com/file/d/1Bxyz987654321_Abcdefghijk/view';

      test('Google Drive stream synchronization aligns playing and paused states', () {
        const hostTimestamp = 1000000;
        final payload = SyncPayload(
          mediaType: 'direct_url',
          mediaUrl: gdriveUrl,
          state: 'playing',
          positionSeconds: 35.0,
          timestampMs: hostTimestamp,
          controllerId: 'host-user',
        );

        final target =
            syncEngine.calculateTargetPosition(payload, hostTimestamp + 600);
        expect(target, closeTo(35.6, 0.001));
      });

      test('Google Drive URL is recognized as direct stream URL', () {
        final detected = UnifiedPlayerController.detectMediaFromUrl(gdriveUrl);
        expect(detected, isNotNull);
        expect(detected!.mediaType, 'direct_url');
        expect(detected.mediaUrl, gdriveUrl);
      });
    });

    // -------------------------------------------------------------------------
    // 6. Local File & P2P Stream Synchronization
    // -------------------------------------------------------------------------
    group('6. Local File & P2P Stream Sync', () {
      const localFilePath = '/storage/emulated/0/Movies/sample_anime.mp4';
      const p2pStreamUrl = 'p2p://room-sync-testing-123/sample_anime.mp4';

      test('Local File and P2P Stream detection', () {
        expect(UnifiedPlayerController.isLocalFilePath(localFilePath), isTrue);
        expect(UnifiedPlayerController.isLocalFilePath('C:\\Users\\Videos\\movie.mp4'), isTrue);
        expect(UnifiedPlayerController.isLocalFilePath('file:///home/user/video.mp4'), isTrue);

        final detectedLocal = UnifiedPlayerController.detectMediaFromUrl(localFilePath);
        expect(detectedLocal, isNotNull);
        expect(detectedLocal!.mediaType, 'direct_url');
        expect(detectedLocal.title, 'sample anime');

        final detectedP2P = UnifiedPlayerController.detectMediaFromUrl(p2pStreamUrl);
        expect(detectedP2P, isNotNull);
        expect(detectedP2P!.mediaType, 'direct_url');
        expect(detectedP2P.mediaUrl, p2pStreamUrl);
      });

      test('P2P direct stream synchronization extrapolates elapsed time', () {
        const hostTimestamp = 1000000;
        final payload = SyncPayload(
          mediaType: 'local_p2p',
          mediaUrl: p2pStreamUrl,
          state: 'playing',
          positionSeconds: 77.0,
          timestampMs: hostTimestamp,
          controllerId: 'host-peer-id',
        );

        // 400ms peer transit delay
        final target =
            syncEngine.calculateTargetPosition(payload, hostTimestamp + 400);
        expect(target, closeTo(77.4, 0.001));
      });
    });
  });
}
