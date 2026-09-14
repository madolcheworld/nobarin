import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/core/utils/ntp_clock_sync.dart';
import 'package:nobarin/features/room/controllers/sync_engine.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/models/sync_payload.dart';

void main() {
  group('All Media Sources Synchronization Test Suite', () {
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
      const directUrl = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';

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
        final targetPos = syncEngine.calculateTargetPosition(payload, viewerReceiveTime);

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
        final targetPos = syncEngine.calculateTargetPosition(payload, hostTimestamp + 5000);
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
        var action = syncEngine.evaluateCorrection(payload, 100.15, hostTimestamp);
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
    });

    // -------------------------------------------------------------------------
    // 2. YouTube Video Synchronization
    // -------------------------------------------------------------------------
    group('2. YouTube Video Sync', () {
      const ytUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
      const ytShortsUrl = 'https://youtube.com/shorts/dQw4w9WgXcQ';

      test('URL detection & ID extraction for YouTube formats', () {
        expect(UnifiedPlayerController.extractYouTubeVideoId(ytUrl), 'dQw4w9WgXcQ');
        expect(UnifiedPlayerController.extractYouTubeVideoId(ytShortsUrl), 'dQw4w9WgXcQ');
        expect(UnifiedPlayerController.extractYouTubeVideoId('dQw4w9WgXcQ'), 'dQw4w9WgXcQ');

        final detected = UnifiedPlayerController.detectMediaFromUrl(ytUrl);
        expect(detected, isNotNull);
        expect(detected!.mediaType, 'youtube');
        expect(detected.mediaId, 'dQw4w9WgXcQ');
      });

      test('YouTube payload serializes and syncs seek position', () {
        final payload = SyncPayload(
          mediaType: 'youtube',
          mediaUrl: ytUrl,
          state: 'playing',
          positionSeconds: 65.0,
          timestampMs: 2000000,
          controllerId: 'host-user',
        );

        final json = payload.toJson();
        final restored = SyncPayload.fromJson(json);

        expect(restored.mediaType, 'youtube');
        expect(restored.mediaUrl, ytUrl);
        expect(restored.positionSeconds, 65.0);

        // Host seeks to 180.0
        final seekPayload = payload.copyWith(positionSeconds: 180.0, timestampMs: 2005000);
        final action = syncEngine.evaluateCorrection(seekPayload, 65.0, 2005000);
        expect(action, DriftAction.hardSeek);
      });
    });


    // -------------------------------------------------------------------------
    // 5. Google Drive Video Synchronization
    // -------------------------------------------------------------------------
    group('5. Google Drive Sync', () {
      const gDriveUrl = 'https://drive.google.com/file/d/1Bxyz987654321_Abcdefghijk/view?usp=sharing';

      test('Google Drive file ID extraction and detection', () {
        final fileId = UnifiedPlayerController.extractGoogleDriveFileId(gDriveUrl);
        expect(fileId, '1Bxyz987654321_Abcdefghijk');

        final detected = UnifiedPlayerController.detectMediaFromUrl(gDriveUrl);
        expect(detected, isNotNull);
        expect(detected!.mediaType, 'google_drive');
        expect(detected.mediaId, '1Bxyz987654321_Abcdefghijk');
      });

      test('Google Drive sync payload propagation', () {
        final payload = SyncPayload(
          mediaType: 'google_drive',
          mediaUrl: gDriveUrl,
          state: 'playing',
          positionSeconds: 88.0,
          timestampMs: 5000000,
          controllerId: 'host-user',
        );

        expect(payload.mediaType, 'google_drive');
        expect(payload.positionSeconds, 88.0);
      });
    });

    // -------------------------------------------------------------------------
    // 6. Dailymotion Video Synchronization
    // -------------------------------------------------------------------------
    group('6. Dailymotion Sync', () {
      const dmUrl = 'https://www.dailymotion.com/video/x7tgad0';

      test('Dailymotion ID extraction and media detection', () {
        final dmId = UnifiedPlayerController.extractDailymotionVideoId(dmUrl);
        expect(dmId, 'x7tgad0');

        final detected = UnifiedPlayerController.detectMediaFromUrl(dmUrl);
        expect(detected, isNotNull);
        expect(detected!.mediaType, 'dailymotion');
        expect(detected.mediaId, 'x7tgad0');
      });

      test('Dailymotion sync payload propagation', () {
        final payload = SyncPayload(
          mediaType: 'dailymotion',
          mediaUrl: dmUrl,
          state: 'paused',
          positionSeconds: 45.0,
          timestampMs: 6000000,
          controllerId: 'host-user',
        );

        expect(payload.mediaType, 'dailymotion');
        expect(payload.isPaused, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 7. Bstation / Bilibili Video Synchronization
    // -------------------------------------------------------------------------
    group('7. Bstation Sync', () {
      const bstationUrl = 'https://www.bilibili.tv/id/play/1004884';

      test('Bstation ID extraction and media detection', () {
        final bId = UnifiedPlayerController.extractBstationVideoId(bstationUrl);
        expect(bId, '1004884');

        final detected = UnifiedPlayerController.detectMediaFromUrl(bstationUrl);
        expect(detected, isNotNull);
        expect(detected!.mediaType, 'bstation');
        expect(detected.mediaId, '1004884');
      });

      test('Bstation sync payload propagation', () {
        final payload = SyncPayload(
          mediaType: 'bstation',
          mediaUrl: bstationUrl,
          state: 'playing',
          positionSeconds: 210.0,
          timestampMs: 7000000,
          controllerId: 'host-user',
        );

        expect(payload.mediaType, 'bstation');
        expect(payload.isPlaying, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // 8. Dynamic Source Switching in a Simulated Multi-Client Room
    // -------------------------------------------------------------------------
    group('8. Multi-Source Seamless Switching in Watch Party Room', () {
      test('Host sequentially changes media sources across all 5 supported types', () {
        const testSources = [
          {'type': 'direct_url', 'url': 'https://example.com/video.mp4'},
          {'type': 'youtube', 'url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'},
          {'type': 'google_drive', 'url': 'https://drive.google.com/file/d/1Bxyz987654321_Abcdefghijk/view'},
          {'type': 'dailymotion', 'url': 'https://www.dailymotion.com/video/x7tgad0'},
          {'type': 'bstation', 'url': 'https://www.bilibili.tv/id/play/1004884'},
        ];

        for (final src in testSources) {
          final payload = SyncPayload(
            mediaType: src['type']!,
            mediaUrl: src['url']!,
            state: 'playing',
            positionSeconds: 0.0,
            timestampMs: 8000000,
            playbackSpeed: 1.0,
            controllerId: 'host-1',
          );

          // Simulate broadcast payload serialization round-trip
          final serialized = payload.toJson();
          final received = SyncPayload.fromJson(serialized);

          expect(received.mediaType, src['type']);
          expect(received.mediaUrl, src['url']);
          expect(received.isPlaying, isTrue);
          expect(received.positionSeconds, 0.0);
          expect(received.controllerId, 'host-1');
        }
      });
    });
  });
}
