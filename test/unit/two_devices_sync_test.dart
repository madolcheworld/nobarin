import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/core/utils/ntp_clock_sync.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/room/controllers/sync_controller.dart';
import 'package:nobarin/features/room/controllers/sync_engine.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/room/models/room_model.dart';
import 'package:nobarin/features/room/models/sync_payload.dart';

/// Controllable in-memory FakePlayerController simulating video playback
/// on native or mobile devices without platform audio/video decoder dependencies.
class FakePlayerController extends UnifiedPlayerController {
  String _fakeMediaType = 'direct_url';
  String _fakeMediaUrl = '';
  bool _fakeIsPlaying = false;
  double _fakePosition = 0.0;
  double _fakeDuration = 300.0;
  double _fakePlaybackSpeed = 1.0;

  int playCount = 0;
  int pauseCount = 0;
  int seekCount = 0;
  int loadMediaCount = 0;
  int speedChangeCount = 0;

  @override
  String get mediaType => _fakeMediaType;

  @override
  String get mediaUrl => _fakeMediaUrl;

  @override
  bool get isPlaying => _fakeIsPlaying;

  @override
  double get position => _fakePosition;

  @override
  double get duration => _fakeDuration;

  @override
  double get playbackSpeed => _fakePlaybackSpeed;

  void setPositionDirectly(double pos, {bool notifyListener = true}) {
    _fakePosition = pos;
    if (notifyListener) {
      notifyListeners();
      onPositionChanged?.call(_fakePosition);
    }
  }

  void setDurationDirectly(double dur) {
    _fakeDuration = dur;
    notifyListeners();
  }

  void setIsPlayingDirectly(bool playing, {bool notifyListener = true}) {
    _fakeIsPlaying = playing;
    if (notifyListener) {
      notifyListeners();
      onPlaybackStateChanged?.call(playing ? 'playing' : 'paused');
    }
  }

  @override
  Future<void> loadMedia(
    String type,
    String url, {
    bool autoPlay = true,
    double startSeconds = 0.0,
  }) async {
    loadMediaCount++;
    _fakeMediaType = type;
    _fakeMediaUrl = url;
    _fakePosition = startSeconds;
    _fakeIsPlaying = autoPlay;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    playCount++;
    _fakeIsPlaying = true;
    notifyListeners();
    onPlaybackStateChanged?.call('playing');
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    _fakeIsPlaying = false;
    notifyListeners();
    onPlaybackStateChanged?.call('paused');
  }

  @override
  Future<void> seekTo(double seconds) async {
    seekCount++;
    _fakePosition = seconds < 0 ? 0 : seconds;
    notifyListeners();
    onPositionChanged?.call(_fakePosition);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    speedChangeCount++;
    _fakePlaybackSpeed = speed;
    notifyListeners();
  }
}

/// A simulated peer-to-peer / Supabase Realtime broadcast channel between 2 devices.
class TwoDeviceTestHarness {
  late RoomModel room;
  late UserProfile hostUser;
  late UserProfile viewerUser;

  late NtpClockSync hostClockSync;
  late NtpClockSync viewerClockSync;

  late FakePlayerController hostPlayer;
  late FakePlayerController viewerPlayer;

  late SyncEngine hostEngine;
  late SyncEngine viewerEngine;

  late SyncController hostSync;
  late SyncController viewerSync;

  final List<Map<String, dynamic>> hostBroadcastLogs = [];
  final List<Map<String, dynamic>> viewerBroadcastLogs = [];

  bool forwardBroadcasts = true;

  bool _isSetup = false;

  void setup({
    bool isCollaborative = false,
    int hostClockOffsetMs = 0,
    int viewerClockOffsetMs = 0,
  }) {
    _isSetup = true;
    hostUser = const UserProfile(
      id: 'host-device-uuid',
      username: 'HostDevice',
    );

    viewerUser = const UserProfile(
      id: 'viewer-device-uuid',
      username: 'ViewerDevice',
    );

    room = RoomModel(
      id: 'room-sync-testing-123',
      code: 'TEST12',
      title: 'Nobarin Sync Room',
      hostId: hostUser.id,
      hostName: hostUser.username,
      controlMode: isCollaborative ? 'collaborative' : 'host_only',
      livekitRoomName: 'room-sync-testing-123',
      currentMediaType: 'direct_url',
      currentMediaUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    );

    hostClockSync = NtpClockSync.custom(offsetMs: hostClockOffsetMs);
    viewerClockSync = NtpClockSync.custom(offsetMs: viewerClockOffsetMs);

    hostPlayer = FakePlayerController();
    viewerPlayer = FakePlayerController();

    // Set initial media
    hostPlayer.loadMedia(room.currentMediaType!, room.currentMediaUrl!, autoPlay: false);
    viewerPlayer.loadMedia(room.currentMediaType!, room.currentMediaUrl!, autoPlay: false);

    hostEngine = SyncEngine(clockSync: hostClockSync);
    viewerEngine = SyncEngine(clockSync: viewerClockSync);

    hostSync = SyncController(
      room: room,
      currentUser: hostUser,
      player: hostPlayer,
      engine: hostEngine,
      onBroadcastSentForTesting: (event, payload) {
        hostBroadcastLogs.add({'event': event, 'payload': payload});
        if (forwardBroadcasts && event == 'SYNC_STATE') {
          viewerSync.handleRemoteSyncForTesting(payload);
        }
      },
    );

    viewerSync = SyncController(
      room: room,
      currentUser: viewerUser,
      player: viewerPlayer,
      engine: viewerEngine,
      onBroadcastSentForTesting: (event, payload) {
        viewerBroadcastLogs.add({'event': event, 'payload': payload});
        if (forwardBroadcasts && event == 'REQUEST_SYNC') {
          hostSync.handleRequestSyncForTesting();
        }
      },
    );
  }

  void dispose() {
    if (_isSetup) {
      hostSync.dispose();
      viewerSync.dispose();
    }
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('Two Devices Video Synchronization Full Test Suite', () {
    late TwoDeviceTestHarness harness;

    setUp(() {
      harness = TwoDeviceTestHarness();
    });

    tearDown(() {
      harness.dispose();
    });

    // -------------------------------------------------------------------------
    // 1. Role-Based Permissions (Host-Only Room)
    // -------------------------------------------------------------------------
    test('1. Role-Based Permissions: Viewer cannot control playback in host_only room', () async {
      harness.setup(isCollaborative: false);

      expect(harness.hostSync.canControl, isTrue);
      expect(harness.viewerSync.canControl, isFalse);

      // Viewer attempts to play, pause, seek, and change media
      await harness.viewerSync.requestPlay();
      await harness.viewerSync.requestPause();
      await harness.viewerSync.requestSeek(50.0);
      await harness.viewerSync.requestChangeMedia('youtube', 'https://youtube.com/watch?v=xyz');

      // Ensure no broadcasts were initiated by viewer
      expect(harness.viewerBroadcastLogs, isEmpty);
      // Ensure viewer player state remains unmodified by unauthorised calls
      expect(harness.viewerPlayer.playCount, 0);
      expect(harness.viewerPlayer.pauseCount, 0);
      expect(harness.viewerPlayer.seekCount, 0);
    });

    // -------------------------------------------------------------------------
    // 2. Synchronized Play
    // -------------------------------------------------------------------------
    test('2. Synchronized Play: Host triggers play -> Viewer starts playback in sync', () async {
      harness.setup(isCollaborative: false);

      expect(harness.hostPlayer.isPlaying, isFalse);
      expect(harness.viewerPlayer.isPlaying, isFalse);

      // Host initiates play
      await harness.hostSync.requestPlay();

      // Host player is playing
      expect(harness.hostPlayer.isPlaying, isTrue);
      // Broadcast was sent
      expect(harness.hostBroadcastLogs.any((b) => b['event'] == 'SYNC_STATE'), isTrue);
      final lastPayload = harness.hostBroadcastLogs.last['payload'] as Map<String, dynamic>;
      expect(lastPayload['state'], 'playing');
      expect(lastPayload['action'], 'play');

      // Viewer automatically started playing upon receiving broadcast
      expect(harness.viewerPlayer.isPlaying, isTrue);
      expect(harness.viewerPlayer.playCount, 1);
    });

    // -------------------------------------------------------------------------
    // 3. Synchronized Pause & Frame Alignment
    // -------------------------------------------------------------------------
    test('3. Synchronized Pause: Host pauses -> Viewer pauses and aligns to exact frame', () async {
      harness.setup(isCollaborative: false);

      // Set initial playing state on both
      harness.hostPlayer.setIsPlayingDirectly(true, notifyListener: false);
      harness.viewerPlayer.setIsPlayingDirectly(true, notifyListener: false);
      harness.hostPlayer.setPositionDirectly(45.2, notifyListener: false);
      // Viewer is slightly off by 200ms (> 50ms pause threshold)
      harness.viewerPlayer.setPositionDirectly(45.4, notifyListener: false);

      // Host initiates pause
      await harness.hostSync.requestPause();

      // Host is paused at 45.2s
      expect(harness.hostPlayer.isPlaying, isFalse);
      expect(harness.hostPlayer.position, 45.2);

      // Viewer received pause, paused player, and snapped to exact host frame (45.2)
      expect(harness.viewerPlayer.isPlaying, isFalse);
      expect(harness.viewerPlayer.position, closeTo(45.2, 0.001));
      expect(harness.viewerPlayer.playbackSpeed, 1.0);
    });

    // -------------------------------------------------------------------------
    // 4. Synchronized Seek
    // -------------------------------------------------------------------------
    test('4. Synchronized Seek: Host seeks to 125.5s -> Viewer jumps immediately', () async {
      harness.setup(isCollaborative: false);

      harness.hostPlayer.setPositionDirectly(30.0, notifyListener: false);
      harness.viewerPlayer.setPositionDirectly(30.0, notifyListener: false);

      // Host requests seek to 125.5 seconds
      await harness.hostSync.requestSeek(125.5);

      // Host is at 125.5s
      expect(harness.hostPlayer.position, 125.5);

      // Viewer immediately aligns to 125.5s
      expect(harness.viewerPlayer.position, 125.5);
      expect(harness.viewerPlayer.seekCount, 1);
    });

    // -------------------------------------------------------------------------
    // 5. Network Transit Delay Compensation
    // -------------------------------------------------------------------------
    test('5. Network Transit Delay Compensation: Target position extrapolates elapsed transit time', () {
      harness.setup();

      const hostTimestamp = 1000000;
      final payload = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: harness.room.currentMediaUrl!,
        state: 'playing',
        positionSeconds: 20.0,
        timestampMs: hostTimestamp,
        playbackSpeed: 1.0,
        controllerId: harness.hostUser.id,
      );

      // Packet arrives at Viewer 1500ms later (1.5 seconds network delay)
      const viewerReceiveTime = hostTimestamp + 1500;
      final target = harness.viewerEngine.calculateTargetPosition(payload, viewerReceiveTime);

      // Expected: 20.0 + (1500ms * 1.0 / 1000) = 21.5s
      expect(target, closeTo(21.5, 0.001));
    });

    // -------------------------------------------------------------------------
    // 6. Micro-Speed Slewing: Lagging Viewer Catch-Up and Hysteresis Restore
    // -------------------------------------------------------------------------
    test('6. Micro-Speed Slewing: Viewer lagging by 600ms speeds up, restores to 1.0x when synced', () async {
      harness.setup();
      harness.forwardBroadcasts = false; // Manual packet delivery

      final now = harness.hostClockSync.synchronizedTimestampMs;
      final payload = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: harness.room.currentMediaUrl!,
        state: 'playing',
        positionSeconds: 50.0,
        timestampMs: now,
        playbackSpeed: 1.0,
        controllerId: harness.hostUser.id,
        seqId: 1,
      );

      // Viewer is playing at 49.4s (lagging by 600ms = 0.6s, within micro-adjust window: 0.3s - 1.8s)
      harness.viewerPlayer.setIsPlayingDirectly(true, notifyListener: false);
      harness.viewerPlayer.setPositionDirectly(49.4, notifyListener: false);

      // Viewer processes remote packet
      harness.viewerSync.handleRemoteSyncForTesting(payload.toJson());

      // Should have triggered micro-speed up (greater than 1.0x, typically 1.05x)
      expect(harness.viewerPlayer.playbackSpeed, greaterThan(1.0));
      expect(harness.viewerPlayer.playbackSpeed, closeTo(1.05, 0.03));
      expect(harness.viewerSync.syncStatusLabel, 'adjusting');

      // Allow position listener to trigger hysteresis restore
      // As playback catches up and drift drops below 40ms, hysteresis resets speed to 1.0x
      await Future.delayed(const Duration(milliseconds: 350));
      final currentTarget = harness.viewerEngine.calculateTargetPosition(payload);
      harness.viewerPlayer.setPositionDirectly(currentTarget, notifyListener: true);

      // Speed restored back to standard 1.0x
      expect(harness.viewerPlayer.playbackSpeed, 1.0);
    });

    // -------------------------------------------------------------------------
    // 7. Micro-Speed Slewing: Leading Viewer Slow-Down
    // -------------------------------------------------------------------------
    test('7. Micro-Speed Slewing: Viewer ahead by 600ms slows down smoothly', () async {
      harness.setup();
      harness.forwardBroadcasts = false;

      final now = harness.hostClockSync.synchronizedTimestampMs;
      final payload = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: harness.room.currentMediaUrl!,
        state: 'playing',
        positionSeconds: 50.0,
        timestampMs: now,
        playbackSpeed: 1.0,
        controllerId: harness.hostUser.id,
        seqId: 2,
      );

      // Viewer is ahead at 50.6s (drift = -600ms = -0.6s, within 0.3s - 1.8s window)
      harness.viewerPlayer.setIsPlayingDirectly(true, notifyListener: false);
      harness.viewerPlayer.setPositionDirectly(50.6, notifyListener: false);

      harness.viewerSync.handleRemoteSyncForTesting(payload.toJson());

      // Should have triggered micro-speed slow down (less than 1.0x, typically 0.95x)
      expect(harness.viewerPlayer.playbackSpeed, lessThan(1.0));
      expect(harness.viewerPlayer.playbackSpeed, closeTo(0.95, 0.03));
    });

    // -------------------------------------------------------------------------
    // 8. Severe Desync Recovery: Hard Seek
    // -------------------------------------------------------------------------
    test('8. Severe Desync Recovery: Drift >= 1800ms triggers hard seek to target', () async {
      harness.setup();
      harness.forwardBroadcasts = false;

      final now = harness.hostClockSync.synchronizedTimestampMs;
      final payload = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: harness.room.currentMediaUrl!,
        state: 'playing',
        positionSeconds: 100.0,
        timestampMs: now,
        playbackSpeed: 1.0,
        controllerId: harness.hostUser.id,
        seqId: 3,
      );

      // Viewer is lagging by 10 seconds at position 90.0s (>= 1.8s threshold)
      harness.viewerPlayer.setIsPlayingDirectly(true, notifyListener: false);
      harness.viewerPlayer.setPositionDirectly(90.0, notifyListener: false);

      harness.viewerSync.handleRemoteSyncForTesting(payload.toJson());

      // Hard seek executed to align directly to host position (100.0s)
      expect(harness.viewerPlayer.position, closeTo(100.0, 0.5));
      expect(harness.viewerPlayer.playbackSpeed, 1.0);
    });

    // -------------------------------------------------------------------------
    // 9. Media Switching Across All 4 Video Platforms
    // -------------------------------------------------------------------------
    test('9. Media Switching: Host changes media source -> Viewer loads each platform seamlessly', () async {
      harness.setup(isCollaborative: false);

      // 9a. Dailymotion
      const dmUrl = 'https://www.dailymotion.com/video/x7tgad0';
      await harness.hostSync.requestChangeMedia('dailymotion', dmUrl);
      expect(harness.hostPlayer.mediaType, 'dailymotion');
      expect(harness.hostPlayer.mediaUrl, dmUrl);
      expect(harness.viewerPlayer.mediaType, 'dailymotion');
      expect(harness.viewerPlayer.mediaUrl, dmUrl);
      expect(harness.viewerPlayer.isPlaying, isTrue);

      // 9b. Bstation (Bilibili)
      const bstationUrl = 'https://www.bilibili.tv/id/play/1004884';
      await harness.hostSync.requestChangeMedia('bstation', bstationUrl);
      expect(harness.viewerPlayer.mediaType, 'bstation');
      expect(harness.viewerPlayer.mediaUrl, bstationUrl);

      // 9c. YouTube
      const ytUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
      await harness.hostSync.requestChangeMedia('youtube', ytUrl);
      expect(harness.viewerPlayer.mediaType, 'youtube');
      expect(harness.viewerPlayer.mediaUrl, ytUrl);

      // 9d. Direct MP4 Video
      const mp4Url = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4';
      await harness.hostSync.requestChangeMedia('direct_url', mp4Url);
      expect(harness.viewerPlayer.mediaType, 'direct_url');
      expect(harness.viewerPlayer.mediaUrl, mp4Url);

      // 9e. Google Drive Video
      const gdriveUrl = 'https://drive.google.com/file/d/1Bxyz987654321_Abcdefghijk/view';
      await harness.hostSync.requestChangeMedia('direct_url', gdriveUrl);
      expect(harness.viewerPlayer.mediaType, 'direct_url');
      expect(harness.viewerPlayer.mediaUrl, gdriveUrl);

      // 9f. Local P2P Stream
      const p2pUrl = 'p2p://room-sync-testing-123/movie.mp4';
      await harness.hostSync.requestChangeMedia('local_p2p', p2pUrl);
      expect(harness.viewerPlayer.mediaType, 'local_p2p');
      expect(harness.viewerPlayer.mediaUrl, p2pUrl);
    });

    // -------------------------------------------------------------------------
    // 10. NTP Hardware Clock Skew Compensation
    // -------------------------------------------------------------------------
    test('10. NTP Clock Skew: Devices with skewed OS clocks compute identical UTC target', () {
      harness.setup();

      // True UTC server epoch
      const trueServerEpoch = 1700000000000;

      // Device 1 (Host) hardware clock is 4000ms slow (offset = +4000ms)
      const hostHardwareClock = trueServerEpoch - 4000;
      const hostNtpOffset = 4000;
      final hostSynchronizedEpoch = hostHardwareClock + hostNtpOffset;

      // 200ms transit delay across network
      const transitDelayMs = 200;

      // Device 2 (Viewer) hardware clock is 2500ms fast (offset = -2500ms)
      const viewerHardwareClock = (trueServerEpoch + transitDelayMs) + 2500;
      const viewerNtpOffset = -2500;
      final viewerSynchronizedEpoch = viewerHardwareClock + viewerNtpOffset;

      // 1. Without NTP compensation, raw clocks produce a massive 6.7s error:
      final rawTransitDelay = viewerHardwareClock - hostHardwareClock;
      expect(rawTransitDelay, 6700);

      // 2. With NTP compensation, calibrated timestamps reflect the true 200ms delay:
      final ntpTransitDelay = viewerSynchronizedEpoch - hostSynchronizedEpoch;
      expect(ntpTransitDelay, transitDelayMs);

      // Verify viewer accurately extrapolates target position without clock skew distortion:
      final payload = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: 'https://example.com/movie.mp4',
        state: 'playing',
        positionSeconds: 30.0,
        timestampMs: hostSynchronizedEpoch,
        playbackSpeed: 1.0,
        controllerId: 'host-id',
      );

      final target = harness.viewerEngine.calculateTargetPosition(
        payload,
        viewerSynchronizedEpoch,
      );

      // Exact 30.0s + 0.2s = 30.2s
      expect(target, closeTo(30.2, 0.001));
    });

    // -------------------------------------------------------------------------
    // 11. Stale & Out-of-Order Packet Rejection
    // -------------------------------------------------------------------------
    test('11. Packet Ordering: Out-of-order and stale packets are rejected by Viewer', () async {
      harness.setup();
      harness.forwardBroadcasts = false;

      final now = harness.hostClockSync.synchronizedTimestampMs;

      final packetSeq1 = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: harness.room.currentMediaUrl!,
        state: 'playing',
        positionSeconds: 10.0,
        timestampMs: now,
        controllerId: harness.hostUser.id,
        seqId: 1,
        action: 'seek',
      );

      final packetSeq2 = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: harness.room.currentMediaUrl!,
        state: 'playing',
        positionSeconds: 20.0,
        timestampMs: now + 500,
        controllerId: harness.hostUser.id,
        seqId: 2,
        action: 'seek',
      );

      // Packet 2 arrives first
      harness.viewerSync.handleRemoteSyncForTesting(packetSeq2.toJson());
      expect(harness.viewerPlayer.position, 20.0);

      // Packet 1 arrives late (out of order)
      harness.viewerSync.handleRemoteSyncForTesting(packetSeq1.toJson());

      // Viewer stays on Packet 2's position and ignores the stale packet #1
      expect(harness.viewerPlayer.position, 20.0);
    });

    // -------------------------------------------------------------------------
    // 12. Instant Join Sync (REQUEST_SYNC -> Host Snapshot)
    // -------------------------------------------------------------------------
    test('12. Instant Join: Newly joined Viewer receives Host Snapshot immediately', () async {
      harness.setup(isCollaborative: false);

      // Host has been playing for a while at 88.5 seconds
      await harness.hostPlayer.loadMedia(
        'dailymotion',
        'https://www.dailymotion.com/video/x7tgad0',
        autoPlay: true,
      );
      harness.hostPlayer.setPositionDirectly(88.5, notifyListener: false);

      // New Viewer joins and emits REQUEST_SYNC
      harness.viewerSync.requestInitialSyncForTesting();

      // Host replied with a snapshot broadcast
      expect(harness.hostBroadcastLogs.any((b) => b['payload']['action'] == 'snapshot'), isTrue);

      // Viewer received the snapshot and synchronized playback state and position
      expect(harness.viewerPlayer.mediaType, 'dailymotion');
      expect(harness.viewerPlayer.mediaUrl, 'https://www.dailymotion.com/video/x7tgad0');
      expect(harness.viewerPlayer.isPlaying, isTrue);
      expect(harness.viewerPlayer.position, closeTo(88.5, 0.5));
    });

    // -------------------------------------------------------------------------
    // 13. Rapid Remote Sync Packets & Session Token Echo Guard
    // -------------------------------------------------------------------------
    test('13. Rapid Remote Sync Packets do not prematurely clear remote sync guard', () async {
      harness.setup(isCollaborative: true);

      final now = harness.hostClockSync.synchronizedTimestampMs;

      final packet1 = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: harness.room.currentMediaUrl!,
        state: 'playing',
        positionSeconds: 15.0,
        timestampMs: now,
        controllerId: harness.hostUser.id,
        seqId: 1,
        action: 'seek',
      );

      final packet2 = SyncPayload(
        mediaType: 'direct_url',
        mediaUrl: harness.room.currentMediaUrl!,
        state: 'playing',
        positionSeconds: 30.0,
        timestampMs: now + 50,
        controllerId: harness.hostUser.id,
        seqId: 2,
        action: 'seek',
      );

      // Packet 1 received
      harness.viewerSync.handleRemoteSyncForTesting(packet1.toJson());

      // Rapidly after (before 300ms delayed cleanup of packet 1), packet 2 is received
      harness.viewerSync.handleRemoteSyncForTesting(packet2.toJson());

      expect(harness.viewerPlayer.position, 30.0);

      // Wait 350ms for session 1's stale timer to expire
      await Future.delayed(const Duration(milliseconds: 350));

      expect(harness.viewerPlayer.position, 30.0);
    });
  });
}
