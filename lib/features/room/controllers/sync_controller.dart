import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/domain/user_profile.dart';
import '../models/room_model.dart';
import '../models/sync_payload.dart';
import 'sync_engine.dart';
import 'unified_player_controller.dart';

class SyncController extends ChangeNotifier {
  RoomModel room;
  final UserProfile currentUser;
  final UnifiedPlayerController player;
  final SyncEngine syncEngine;
  final SupabaseClient? supabase;
  final bool Function()? isHostProvider;
  final bool Function()? canControlProvider;
  final void Function(String event, Map<String, dynamic> payload)?
      onBroadcastSentForTesting;

  RealtimeChannel? _realtimeChannel;
  Timer? _heartbeatTimer;
  bool _isApplyingRemoteSync = false;
  bool _isDisposed = false;

  // Packet sequence number & ordering guard
  int _seqIdCounter = 0;
  int _lastProcessedSeqId = 0;

  // Track latest known sync payload
  SyncPayload? _latestPayload;
  SyncPayload? get latestPayload => _latestPayload;

  SyncController({
    required this.room,
    required this.currentUser,
    required this.player,
    SyncEngine? engine,
    this.supabase,
    this.isHostProvider,
    this.canControlProvider,
    this.onBroadcastSentForTesting,
  })  : syncEngine = engine ?? SyncEngine() {
    _initChannel();
    _setupPlayerListeners();
    _startHeartbeatTimer();
  }

  void updateRoom(RoomModel updatedRoom) {
    if (room != updatedRoom) {
      room = updatedRoom;
      notifyListeners();
    }
  }

  /// Whether current user has permission to control playback
  bool get canControl {
    if (room.isCollaborative) return true;
    if (canControlProvider?.call() ?? false) return true;
    if (isHostProvider?.call() ?? false) return true;
    if (room.hostId != null &&
        room.hostId!.isNotEmpty &&
        currentUser.id == room.hostId) {
      return true;
    }
    if (room.hostName != null &&
        room.hostName!.isNotEmpty &&
        room.hostName != 'Host' &&
        currentUser.username.trim().toLowerCase() ==
            room.hostName!.trim().toLowerCase()) {
      return true;
    }
    final bool hasExplicitHost = (room.hostId != null && room.hostId!.isNotEmpty) ||
        (room.hostName != null &&
            room.hostName!.isNotEmpty &&
            room.hostName != 'Host');
    if (!hasExplicitHost) {
      if (currentUser.username != 'Host') {
        return true;
      }
    }
    return false;
  }

  /// Current measured drift in seconds from the latest known remote payload
  double get currentDriftSeconds {
    if (_latestPayload == null) return 0.0;
    return syncEngine.calculateDrift(
      _latestPayload!,
      player.position,
      null,
      player.duration > 0 ? player.duration : null,
    );
  }

  /// Human-readable synchronization status for QoE UI badges
  String get syncStatusLabel {
    if (_latestPayload == null) return 'connecting';
    final drift = currentDriftSeconds;
    if (drift < 0.08) return 'synced';
    if (player.playbackSpeed != 1.0) return 'adjusting';
    if (drift >= 1.8) return 'seeking';
    return 'synced';
  }

  void _initChannel() {
    if (supabase == null) return;

    try {
      final channelName = 'room_${room.id}';
      _realtimeChannel = supabase!.channel(channelName);

      _realtimeChannel!.onBroadcast(
        event: 'SYNC_STATE',
        callback: (Map<String, dynamic> payloadMap) {
          if (_isDisposed) return;
          _handleRemoteSync(payloadMap);
        },
      );

      // Instant Join Sync: when a new participant requests current snapshot
      _realtimeChannel!.onBroadcast(
        event: 'REQUEST_SYNC',
        callback: (Map<String, dynamic> payloadMap) {
          if (_isDisposed) return;
          if (canControl) {
            broadcastSync(action: 'snapshot');
          }
        },
      );

      _realtimeChannel!.subscribe((status, error) {
        debugPrint(
            '[SyncController] Realtime channel status: $status (error: $error)');
        // Once subscribed, send REQUEST_SYNC to instantly receive current host state
        if (status == RealtimeSubscribeStatus.subscribed && !_isDisposed) {
          _requestInitialSync();
        }
      });
    } catch (e) {
      debugPrint('[SyncController] Error creating realtime channel: $e');
    }
  }

  void _requestInitialSync() {
    final payloadMap = {
      'requester_id': currentUser.id,
      'timestamp_ms': syncEngine.clockSync.synchronizedTimestampMs,
    };
    onBroadcastSentForTesting?.call('REQUEST_SYNC', payloadMap);

    if (_realtimeChannel == null || _isDisposed) return;
    try {
      _realtimeChannel!.sendBroadcastMessage(
        event: 'REQUEST_SYNC',
        payload: payloadMap,
      );
    } catch (e) {
      debugPrint('[SyncController] Failed to send REQUEST_SYNC: $e');
    }
  }

  void _setupPlayerListeners() {
    player.onPlaybackStateChanged = (state) {
      if (_isApplyingRemoteSync || !canControl) return;
      broadcastSync(state: state, action: state);
    };

    player.onPositionChanged = (position) {
      if (_isApplyingRemoteSync) return;
      // If we are currently micro-adjusting speed and drift is now < 0.04s (40ms) with hysteresis,
      // restore normal speed (1.0x) smoothly.
      if (_latestPayload != null && player.playbackSpeed != 1.0 && player.isPlaying) {
        final drift = syncEngine.calculateDrift(
          _latestPayload!,
          position,
          null,
          player.duration > 0 ? player.duration : null,
        );
        if (drift < 0.04) {
          player.setPlaybackSpeed(1.0);
        }
      }
    };
  }

  void _startHeartbeatTimer() {
    // Periodic heartbeat every 3.0 seconds
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 3000), (_) {
      if (_isDisposed) return;
      if (canControl && player.isPlaying) {
        broadcastSync(state: 'playing', action: 'heartbeat');
      }
    });
  }

  /// Handle incoming SYNC_STATE broadcast from host/controller
  void _handleRemoteSync(Map<String, dynamic> payloadMap) async {
    final payload = SyncPayload.fromJson(payloadMap);

    // Ignore self-broadcasts
    if (payload.controllerId == currentUser.id) {
      return;
    }

    // Monotonic sequence numbering: discard out-of-order stale packets
    if (payload.seqId > 0 && payload.seqId < _lastProcessedSeqId) {
      debugPrint(
        '[SyncController] Discarded out-of-order packet (seqId ${payload.seqId} < $_lastProcessedSeqId)',
      );
      return;
    }
    if (payload.seqId > 0) {
      _lastProcessedSeqId = payload.seqId;
    }

    _latestPayload = payload;
    _isApplyingRemoteSync = true;

    debugPrint(
      '[SyncController] Remote sync: action=${payload.action}, state=${payload.state}, pos=${payload.positionSeconds}, type=${payload.mediaType}, url=${payload.mediaUrl.isNotEmpty}',
    );

    try {
      final bool isP2pStream = payload.mediaUrl.startsWith('p2p://') ||
          payload.mediaType == 'local_p2p';
      final bool isAlreadyPlayingP2p = isP2pStream &&
          (player.mediaUrl.startsWith('http://127.0.0.1') ||
              player.mediaUrl.startsWith('http://localhost') ||
              player.mediaUrl.startsWith('p2p://'));

      // 1. Media Type or URL Change
      if (payload.mediaUrl.isNotEmpty &&
          !isAlreadyPlayingP2p &&
          (payload.mediaUrl != player.mediaUrl ||
              payload.mediaType != player.mediaType)) {
        await player.loadMedia(
          payload.mediaType,
          payload.mediaUrl,
          autoPlay: payload.isPlaying,
          startSeconds: payload.positionSeconds,
        );
        syncEngine.resetFilter();
      }

      // 2. State-Aware Synchronization: Paused vs Playing
      if (payload.isPaused) {
        if (player.isPlaying) {
          await player.pause();
        }
        // When paused, ensure viewer is on exact target frame (if drift > 50ms)
        final target = payload.positionSeconds;
        if ((player.position - target).abs() > 0.05) {
          await player.seekTo(target);
          syncEngine.recordSeek();
        }
        if (player.playbackSpeed != 1.0) {
          await player.setPlaybackSpeed(1.0);
        }
        notifyListeners();
        return;
      }

      // 3. Explicit Remote Seek Handling
      if (payload.action == 'seek') {
        await player.seekTo(payload.positionSeconds);
        syncEngine.recordSeek();
        if (payload.isPlaying && !player.isPlaying) {
          await player.play();
        }
        notifyListeners();
        return;
      }

      // 4. Playing State Synchronization & Multi-Tier Slewing
      if (payload.isPlaying && !player.isPlaying) {
        await player.play();
      }

      notifyListeners();

      final durationLimit = player.duration > 0 ? player.duration : null;
      final action = syncEngine.evaluateCorrection(
        payload,
        player.position,
        null,
        durationLimit,
      );

      final bool inSeekCooldown = syncEngine.isSeekInCooldown();

      if (action == DriftAction.hardSeek && !inSeekCooldown) {
        // Major desync (>= 1800ms): hard seek to target position with cooldown guard
        final target = syncEngine.calculateTargetPosition(payload, null, durationLimit);
        await player.seekTo(target);
        syncEngine.recordSeek();
        if (player.playbackSpeed != 1.0) {
          await player.setPlaybackSpeed(1.0);
        }
      } else if (action != DriftAction.hardSeek) {
        // Multi-tier proportional adaptive speed
        final double targetSpeed = syncEngine.calculateAdaptiveSpeed(
          payload: payload,
          currentLocalPositionSeconds: player.position,
          maxDurationSeconds: durationLimit,
          isYouTube: player.mediaType == 'youtube',
        );

        if ((player.playbackSpeed - targetSpeed).abs() > 0.005) {
          await player.setPlaybackSpeed(targetSpeed);
        }
      }
    } finally {
      // Delay releasing flag briefly to avoid local echo
      Future.delayed(const Duration(milliseconds: 300), () {
        _isApplyingRemoteSync = false;
      });
    }
  }

  /// Broadcasts current playback state to other room participants
  Future<void> broadcastSync({
    String? state,
    double? position,
    String? mediaType,
    String? mediaUrl,
    String? action,
  }) async {
    if (!canControl) return;

    final targetState = state ?? (player.isPlaying ? 'playing' : 'paused');
    final targetPos = position ?? player.position;
    final targetType = mediaType ??
        (player.mediaType.isNotEmpty ? player.mediaType : (room.currentMediaType ?? 'youtube'));
    final String defaultUrl;
    if (player.mediaUrl.isNotEmpty && !player.mediaUrl.startsWith('p2p://')) {
      defaultUrl = player.mediaUrl;
    } else if (room.currentMediaUrl != null && room.currentMediaUrl!.isNotEmpty) {
      defaultUrl = room.currentMediaUrl!;
    } else {
      defaultUrl = player.mediaUrl;
    }
    final targetUrl = mediaUrl ?? defaultUrl;

    _seqIdCounter++;
    final payload = SyncPayload(
      mediaType: targetType,
      mediaUrl: targetUrl,
      state: targetState,
      positionSeconds: targetPos,
      timestampMs: syncEngine.clockSync.synchronizedTimestampMs,
      playbackSpeed: player.playbackSpeed,
      controllerId: currentUser.id,
      seqId: _seqIdCounter,
      action: action ?? (state ?? (position != null ? 'seek' : 'heartbeat')),
      actionEpoch: syncEngine.clockSync.synchronizedTimestampMs,
      maxDurationSeconds: player.duration > 0 ? player.duration : null,
    );

    _latestPayload = payload;
    onBroadcastSentForTesting?.call('SYNC_STATE', payload.toJson());

    if (_realtimeChannel != null) {
      try {
        await _realtimeChannel!.sendBroadcastMessage(
          event: 'SYNC_STATE',
          payload: payload.toJson(),
        );
      } catch (e) {
        debugPrint('[SyncController] Broadcast failed: $e');
      }
    }
  }

  // User Actions (Checked with permissions)
  Future<void> requestPlay() async {
    if (!canControl) return;
    await player.play();
    await broadcastSync(state: 'playing', action: 'play');
  }

  Future<void> requestPause() async {
    if (!canControl) return;
    await player.pause();
    await broadcastSync(state: 'paused', action: 'pause');
  }

  Future<void> requestSeek(double seconds) async {
    if (!canControl) return;
    syncEngine.recordSeek();
    await player.seekTo(seconds);
    await broadcastSync(position: seconds, action: 'seek');
  }

  Future<void> requestChangeMedia(String type, String url) async {
    if (!canControl) return;
    syncEngine.resetFilter();
    await player.loadMedia(type, url, autoPlay: true);
    await broadcastSync(
      mediaType: type,
      mediaUrl: url,
      state: 'playing',
      position: 0.0,
      action: 'media_change',
    );
  }

  @visibleForTesting
  void handleRemoteSyncForTesting(Map<String, dynamic> payloadMap) {
    _handleRemoteSync(payloadMap);
  }

  @visibleForTesting
  void handleRequestSyncForTesting() {
    if (canControl) {
      broadcastSync(action: 'snapshot');
    }
  }

  @visibleForTesting
  void requestInitialSyncForTesting() {
    _requestInitialSync();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _heartbeatTimer?.cancel();
    if (_realtimeChannel != null && supabase != null) {
      supabase!.removeChannel(_realtimeChannel!);
    }
    super.dispose();
  }
}
