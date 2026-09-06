import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/ntp_clock_sync.dart';
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

  RealtimeChannel? _realtimeChannel;
  Timer? _heartbeatTimer;
  bool _isApplyingRemoteSync = false;
  bool _isDisposed = false;

  // Track latest known sync payload
  SyncPayload? _latestPayload;
  SyncPayload? get latestPayload => _latestPayload;

  // Drift info for debugging/UI stats
  double _lastCalculatedDrift = 0.0;
  double get lastCalculatedDrift => _lastCalculatedDrift;

  SyncController({
    required this.room,
    required this.currentUser,
    required this.player,
    SyncEngine? engine,
    this.supabase,
    this.isHostProvider,
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
    if (isHostProvider?.call() ?? false) return true;
    if (room.hostId != null &&
        room.hostId!.isNotEmpty &&
        currentUser.id == room.hostId) {
      return true;
    }
    if (room.hostName != null &&
        room.hostName!.isNotEmpty &&
        room.hostName != 'Host' &&
        currentUser.username == room.hostName) {
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

      _realtimeChannel!.subscribe((status, error) {
        debugPrint(
            '[SyncController] Realtime channel status: $status (error: $error)');
      });
    } catch (e) {
      debugPrint('[SyncController] Error creating realtime channel: $e');
    }
  }

  void _setupPlayerListeners() {
    player.onPlaybackStateChanged = (state) {
      if (_isApplyingRemoteSync || !canControl) return;
      broadcastSync(state: state);
    };

    player.onPositionChanged = (position) {
      if (_isApplyingRemoteSync) return;
      // If we are currently micro-adjusting speed and drift is now < 0.1s (100ms),
      // restore normal speed (1.0x) per Section 3 of plan.md
      if (_latestPayload != null && player.playbackSpeed != 1.0) {
        final drift = syncEngine.calculateDrift(_latestPayload!, position);
        if (drift < 0.1) {
          player.setPlaybackSpeed(1.0);
        }
      }
    };
  }

  void _startHeartbeatTimer() {
    // Periodic heartbeat every 3.5 seconds
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      if (_isDisposed) return;
      if (canControl && player.isPlaying) {
        broadcastSync(state: 'playing');
      }
    });
  }

  /// Handle incoming SYNC_STATE broadcast from host/controller
  void _handleRemoteSync(Map<String, dynamic> payloadMap) async {
    final payload = SyncPayload.fromJson(payloadMap);
    _latestPayload = payload;

    // Ignore self-broadcasts
    if (payload.controllerId == currentUser.id) {
      return;
    }

    _isApplyingRemoteSync = true;
    try {
      // 1. Media Type or URL Change
      if (payload.mediaUrl.isNotEmpty &&
          (payload.mediaUrl != player.mediaUrl ||
              payload.mediaType != player.mediaType)) {
        await player.loadMedia(
          payload.mediaType,
          payload.mediaUrl,
          autoPlay: payload.isPlaying,
          startSeconds: payload.positionSeconds,
        );
      }

      // 2. Play / Pause State Synchronization
      if (payload.isPlaying && !player.isPlaying) {
        await player.play();
      } else if (payload.isPaused && player.isPlaying) {
        await player.pause();
      }

      // 3. Drift Calculation & Multi-Tier Correction
      final drift = syncEngine.calculateDrift(payload, player.position);
      _lastCalculatedDrift = drift;
      notifyListeners();

      final action = syncEngine.evaluateCorrection(payload, player.position);
      switch (action) {
        case DriftAction.noAction:
          // In sync (< 300ms) - keep smooth
          if (player.playbackSpeed != 1.0) {
            await player.setPlaybackSpeed(1.0);
          }
          break;

        case DriftAction.microSpeedUp:
          // Lagging behind (300ms - 2000ms): speed up slightly (1.06x)
          await player.setPlaybackSpeed(1.06);
          break;

        case DriftAction.microSlowDown:
          // Ahead of host (300ms - 2000ms): slow down slightly (0.94x)
          await player.setPlaybackSpeed(0.94);
          break;

        case DriftAction.hardSeek:
          // Major desync (>= 2000ms): hard seek to target position
          final target = syncEngine.calculateTargetPosition(payload);
          await player.seekTo(target);
          if (player.playbackSpeed != 1.0) {
            await player.setPlaybackSpeed(1.0);
          }
          break;
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
  }) async {
    if (!canControl) return;

    final targetState = state ?? (player.isPlaying ? 'playing' : 'paused');
    final targetPos = position ?? player.position;
    final targetType = mediaType ?? player.mediaType;
    final targetUrl = mediaUrl ?? player.mediaUrl;

    final payload = SyncPayload(
      mediaType: targetType,
      mediaUrl: targetUrl,
      state: targetState,
      positionSeconds: targetPos,
      timestampMs: NtpClockSync().synchronizedTimestampMs,
      playbackSpeed: player.playbackSpeed,
      controllerId: currentUser.id,
    );

    _latestPayload = payload;

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
    await broadcastSync(state: 'playing');
  }

  Future<void> requestPause() async {
    if (!canControl) return;
    await player.pause();
    await broadcastSync(state: 'paused');
  }

  Future<void> requestSeek(double seconds) async {
    if (!canControl) return;
    await player.seekTo(seconds);
    await broadcastSync(position: seconds);
  }

  Future<void> requestChangeMedia(String type, String url) async {
    if (!canControl) return;
    await player.loadMedia(type, url, autoPlay: true);
    await broadcastSync(
      mediaType: type,
      mediaUrl: url,
      state: 'playing',
      position: 0.0,
    );
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
