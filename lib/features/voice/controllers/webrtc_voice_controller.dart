import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/api_constants.dart';
import '../../room/controllers/unified_player_controller.dart';

enum VoiceStatus {
  disconnected,
  connecting,
  connected,
  unconfigured,
  error,
}

typedef UserMediaFunction = Future<MediaStream> Function(
  Map<String, dynamic> constraints,
);

typedef PeerConnectionFunction = Future<RTCPeerConnection> Function(
  Map<String, dynamic> configuration, [
  Map<String, dynamic> constraints,
]);

/// Controller for WebRTC P2P Mesh Voice Chat using Supabase Realtime for signaling.
class WebRtcVoiceController extends ChangeNotifier {
  final String roomId;
  final String userId;
  final String userName;
  final UnifiedPlayerController? playerController;
  final SupabaseClient? supabase;
  final Map<String, dynamic>? iceConfiguration;

  final UserMediaFunction _userMediaFunction;
  final PeerConnectionFunction _peerConnectionFunction;

  VoiceStatus _status = VoiceStatus.disconnected;
  bool _isMicMuted = true;
  bool _isDeafened = false;
  bool _audioDuckingEnabled = true;
  bool _isLocalSpeaking = false;
  bool _isDucking = false;
  double _savedVideoVolume = 1.0;
  bool _isDisposed = false;

  RealtimeChannel? _voiceChannel;
  MediaStream? _localStream;
  Timer? _vadTimer;

  // Active peer connections: remotePeerId -> RTCPeerConnection
  final Map<String, RTCPeerConnection> _peerConnections = {};
  // In-flight peer connection creation lock to prevent concurrency race conditions
  final Map<String, Future<RTCPeerConnection>> _creatingPeerConnections = {};
  // Remote audio streams: remotePeerId -> MediaStream?
  final Map<String, MediaStream?> _remoteStreams = {};
  // Remote audio tracks: remotePeerId -> Set<MediaStreamTrack>
  final Map<String, Set<MediaStreamTrack>> _remoteAudioTracks = {};
  // Queued ICE candidates for peers whose remote descriptions are not yet set
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};
  // Set of user IDs currently speaking (local and/or remote)
  final Set<String> _activeSpeakerIds = {};
  // Set of user IDs currently muted (local and/or remote)
  final Set<String> _mutedUserIds = {};

  VoiceStatus get status => _status;
  bool get isMicMuted => _isMicMuted;
  bool get isDeafened => _isDeafened;
  bool get isConnected => _status == VoiceStatus.connected;
  bool get isAudioDuckingEnabled => _audioDuckingEnabled;
  bool get isLocalSpeaking => _isLocalSpeaking;
  bool get isDucking => _isDucking;
  MediaStream? get localStream => _localStream;
  Set<String> get activeSpeakerIds => Set.unmodifiable(_activeSpeakerIds);
  Set<String> get mutedUserIds => Set.unmodifiable(_mutedUserIds);
  Map<String, RTCPeerConnection> get peerConnections =>
      Map.unmodifiable(_peerConnections);

  final bool autoCaptureMic;

  WebRtcVoiceController({
    required this.roomId,
    required this.userId,
    required this.userName,
    this.playerController,
    this.supabase,
    this.iceConfiguration,
    bool? autoCaptureMic,
    UserMediaFunction? userMediaFunction,
    PeerConnectionFunction? peerConnectionFunction,
  })  : autoCaptureMic = autoCaptureMic ?? false,
        _userMediaFunction = userMediaFunction ?? _defaultUserMedia,
        _peerConnectionFunction =
            peerConnectionFunction ?? _defaultPeerConnection {
    _mutedUserIds.add(userId);
  }

  static Future<MediaStream> _defaultUserMedia(
    Map<String, dynamic> constraints,
  ) {
    return navigator.mediaDevices.getUserMedia(constraints);
  }

  static Future<RTCPeerConnection> _defaultPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) {
    return createPeerConnection(configuration, constraints);
  }

  /// Connects to Voice room, sets up Supabase Realtime signaling channel,
  /// and announces presence. Local microphone is NOT captured until explicit unmute.
  Future<void> connect() async {
    if (_status == VoiceStatus.connected || _status == VoiceStatus.connecting) {
      return;
    }

    _status = VoiceStatus.connecting;
    notifyListeners();

    try {
      // 1. Acquire local microphone stream only if autoCaptureMic is enabled
      // By default in production, hardware microphone is NEVER captured until user explicitly unmutes.
      if (autoCaptureMic) {
        try {
          final stream = await _userMediaFunction({
            'audio': {
              'echoCancellation': true,
              'noiseSuppression': true,
              'autoGainControl': true,
            },
            'video': false,
          });
          _localStream = stream;
          // Ensure track is disabled when muted
          for (final track in _localStream!.getAudioTracks()) {
            track.enabled = !_isMicMuted;
          }
        } catch (e) {
          debugPrint('[WebRtcVoiceController] Mic acquisition skipped/failed: $e');
        }
      } else {
        _localStream = null;
      }

      // 2. Setup Supabase Realtime signaling
      if (supabase == null) {
        _status = VoiceStatus.unconfigured;
        notifyListeners();
        debugPrint('[WebRtcVoiceController] Offline/unconfigured mode.');
        return;
      }

      _setupSignaling();
      _startVadTimer();

      _status = VoiceStatus.connected;
      notifyListeners();

      // 3. Announce presence to room peers
      await _sendSignalingMessage('VOICE_STATE', {
        'sender_id': userId,
        'user_name': userName,
        'is_muted': _isMicMuted,
        'is_speaking': false,
        'action': 'join',
      });
    } catch (e) {
      debugPrint('[WebRtcVoiceController] Connect failed: $e');
      _status = VoiceStatus.error;
      notifyListeners();
    }
  }

  void _setupSignaling() {
    if (supabase == null) return;

    try {
      final channelName = 'voice_$roomId';
      _voiceChannel = supabase!.channel(channelName);

      Map<String, dynamic> extractPayload(Map<String, dynamic> raw) {
        if (raw['payload'] is Map<String, dynamic>) {
          return raw['payload'] as Map<String, dynamic>;
        } else if (raw['payload'] is Map) {
          return Map<String, dynamic>.from(raw['payload'] as Map);
        }
        return raw;
      }

      _voiceChannel!.onBroadcast(
        event: 'VOICE_STATE',
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          handleVoiceState(extractPayload(payload));
        },
      );

      _voiceChannel!.onBroadcast(
        event: 'VOICE_OFFER',
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          handleVoiceOffer(extractPayload(payload));
        },
      );

      _voiceChannel!.onBroadcast(
        event: 'VOICE_ANSWER',
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          handleVoiceAnswer(extractPayload(payload));
        },
      );

      _voiceChannel!.onBroadcast(
        event: 'VOICE_ICE',
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          handleVoiceIce(extractPayload(payload));
        },
      );

      _voiceChannel!.subscribe((status, error) {
        debugPrint(
            '[WebRtcVoiceController] Realtime status: $status (error: $error)');
      });
    } catch (e) {
      debugPrint('[WebRtcVoiceController] Error setting up signaling: $e');
    }
  }

  /// Sends a broadcast signaling message via Supabase Realtime
  Future<void> _sendSignalingMessage(
    String event,
    Map<String, dynamic> payload,
  ) async {
    if (_isDisposed || _voiceChannel == null || supabase == null) return;
    try {
      await _voiceChannel!.sendBroadcastMessage(
        event: event,
        payload: payload,
      );
    } catch (e) {
      debugPrint(
          '[WebRtcVoiceController] Error broadcasting $event: $e');
    }
  }

  /// Handles incoming VOICE_STATE events (join, leave, announce, update)
  @visibleForTesting
  Future<void> handleVoiceState(Map<String, dynamic> payload) async {
    final senderId = payload['sender_id'] as String?;
    if (senderId == null || senderId == userId) return;

    final action = payload['action'] as String? ?? 'update';
    final isMuted = payload['is_muted'] as bool? ?? true;
    final isSpeaking = payload['is_speaking'] as bool? ?? false;

    if (action == 'leave') {
      _activeSpeakerIds.remove(senderId);
      _mutedUserIds.remove(senderId);
      await _closePeerConnection(senderId);
      _handleAudioDucking();
      notifyListeners();
      return;
    }

    // Update muted and speaking state for this peer
    if (isMuted) {
      _mutedUserIds.add(senderId);
    } else {
      _mutedUserIds.remove(senderId);
    }

    if (isSpeaking && !isMuted && !_isDeafened) {
      _activeSpeakerIds.add(senderId);
    } else {
      _activeSpeakerIds.remove(senderId);
    }

    if (action == 'join') {
      // Announce our presence back so new peer knows we are in the room
      await _sendSignalingMessage('VOICE_STATE', {
        'sender_id': userId,
        'user_name': userName,
        'is_muted': _isMicMuted,
        'is_speaking': _isLocalSpeaking,
        'action': 'announce',
      });

      // Deterministic initiator: peer with higher userId creates offer
      if (userId.compareTo(senderId) > 0) {
        await _initiateOfferTo(senderId);
      }
      _handleAudioDucking();
      notifyListeners();
      return;
    }

    if (action == 'announce') {
      // Existing peer announced itself in response to our join
      if (userId.compareTo(senderId) > 0) {
        await _initiateOfferTo(senderId);
      }
      _handleAudioDucking();
      notifyListeners();
      return;
    }

    _handleAudioDucking();
    notifyListeners();
  }

  /// Creates and sends an SDP offer to [remotePeerId]
  Future<void> _initiateOfferTo(String remotePeerId) async {
    try {
      final pc = await _getOrCreatePeerConnection(remotePeerId);
      final offer = await pc.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await pc.setLocalDescription(offer);

      await _sendSignalingMessage('VOICE_OFFER', {
        'sender_id': userId,
        'target_id': remotePeerId,
        'sdp': {
          'type': offer.type,
          'sdp': offer.sdp,
        },
      });
    } catch (e) {
      debugPrint(
          '[WebRtcVoiceController] Error initiating offer to $remotePeerId: $e');
    }
  }

  /// Handles incoming VOICE_OFFER targeted at this user
  @visibleForTesting
  Future<void> handleVoiceOffer(Map<String, dynamic> payload) async {
    final senderId = payload['sender_id'] as String?;
    final targetId = payload['target_id'] as String?;
    final sdpMap = payload['sdp'] as Map<String, dynamic>?;

    if (senderId == null || targetId != userId || sdpMap == null) return;

    try {
      final pc = await _getOrCreatePeerConnection(senderId);
      final sdp = sdpMap['sdp'] as String? ?? '';
      final type = sdpMap['type'] as String? ?? 'offer';

      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));

      final answer = await pc.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await pc.setLocalDescription(answer);

      // Flush any queued ICE candidates after local description is set (state is stable)
      await _flushPendingCandidates(senderId, pc);

      await _sendSignalingMessage('VOICE_ANSWER', {
        'sender_id': userId,
        'target_id': senderId,
        'sdp': {
          'type': answer.type,
          'sdp': answer.sdp,
        },
      });
    } catch (e) {
      debugPrint(
          '[WebRtcVoiceController] Error handling offer from $senderId: $e');
    }
  }

  /// Handles incoming VOICE_ANSWER targeted at this user
  @visibleForTesting
  Future<void> handleVoiceAnswer(Map<String, dynamic> payload) async {
    final senderId = payload['sender_id'] as String?;
    final targetId = payload['target_id'] as String?;
    final sdpMap = payload['sdp'] as Map<String, dynamic>?;

    if (senderId == null || targetId != userId || sdpMap == null) return;

    final pc = _peerConnections[senderId];
    if (pc == null) return;

    try {
      final sdp = sdpMap['sdp'] as String? ?? '';
      final type = sdpMap['type'] as String? ?? 'answer';
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));

      // Flush any queued ICE candidates
      await _flushPendingCandidates(senderId, pc);
    } catch (e) {
      debugPrint(
          '[WebRtcVoiceController] Error handling answer from $senderId: $e');
    }
  }

  /// Handles incoming VOICE_ICE candidate targeted at this user
  @visibleForTesting
  Future<void> handleVoiceIce(Map<String, dynamic> payload) async {
    final senderId = payload['sender_id'] as String?;
    final targetId = payload['target_id'] as String?;
    final candMap = payload['candidate'] as Map<String, dynamic>?;

    if (senderId == null || targetId != userId || candMap == null) return;

    final candString = candMap['candidate'] as String?;
    if (candString == null || candString.isEmpty) return;

    final candidate = RTCIceCandidate(
      candString,
      candMap['sdpMid'] as String?,
      candMap['sdpMLineIndex'] as int?,
    );

    final pc = _peerConnections[senderId];
    if (pc != null) {
      try {
        final remoteDesc = await pc.getRemoteDescription();
        if (remoteDesc != null && remoteDesc.sdp != null) {
          await pc.addCandidate(candidate);
          return;
        }
      } catch (_) {}
    }

    // Queue candidate until remote description is set
    _pendingCandidates.putIfAbsent(senderId, () => []).add(candidate);
  }

  Future<void> _flushPendingCandidates(
    String remotePeerId,
    RTCPeerConnection pc,
  ) async {
    final candidates = _pendingCandidates.remove(remotePeerId);
    if (candidates != null && candidates.isNotEmpty) {
      for (final candidate in candidates) {
        try {
          await pc.addCandidate(candidate);
        } catch (e) {
          debugPrint(
              '[WebRtcVoiceController] Error adding queued ICE candidate: $e');
        }
      }
    }
  }

  /// Creates or retrieves existing RTCPeerConnection for [remotePeerId]
  Future<RTCPeerConnection> _getOrCreatePeerConnection(
    String remotePeerId,
  ) async {
    if (_peerConnections.containsKey(remotePeerId)) {
      return _peerConnections[remotePeerId]!;
    }
    if (_creatingPeerConnections.containsKey(remotePeerId)) {
      return await _creatingPeerConnections[remotePeerId]!;
    }

    final completer = Completer<RTCPeerConnection>();
    _creatingPeerConnections[remotePeerId] = completer.future;

    try {
      final pcConfig = iceConfiguration ?? ApiConstants.rtcIceConfiguration;
      final pc = await _peerConnectionFunction(pcConfig, {
        'mandatory': {},
        'optional': [
          {'DtlsSrtpKeyAgreement': true},
        ],
      });

      _peerConnections[remotePeerId] = pc;

      // Attach local audio track if available
      if (_localStream != null) {
        for (final track in _localStream!.getAudioTracks()) {
          await pc.addTrack(track, _localStream!);
        }
      }

      // Send local ICE candidates to peer
      pc.onIceCandidate = (candidate) {
        if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
        _sendSignalingMessage('VOICE_ICE', {
          'sender_id': userId,
          'target_id': remotePeerId,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        });
      };

      // Track remote audio stream and tracks
      pc.onTrack = (event) {
        if (event.track.kind == 'audio') {
          _remoteStreams[remotePeerId] =
              event.streams.isNotEmpty ? event.streams[0] : null;
          _remoteAudioTracks
              .putIfAbsent(remotePeerId, () => {})
              .add(event.track);

          if (_isDeafened) {
            event.track.enabled = false;
          }
        }
      };

      pc.onConnectionState = (state) {
        debugPrint(
            '[WebRtcVoiceController] Peer $remotePeerId state: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _activeSpeakerIds.remove(remotePeerId);
          _mutedUserIds.remove(remotePeerId);
          _handleAudioDucking();
          notifyListeners();
          if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
              state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
            _closePeerConnection(remotePeerId);
          }
        }
      };

      completer.complete(pc);
      return pc;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _creatingPeerConnections.remove(remotePeerId);
    }
  }

  Future<void> _closePeerConnection(String remotePeerId) async {
    _creatingPeerConnections.remove(remotePeerId);
    final pc = _peerConnections.remove(remotePeerId);
    if (pc != null) {
      try {
        await pc.close();
        await pc.dispose();
      } catch (_) {}
    }
    _remoteStreams.remove(remotePeerId);
    _remoteAudioTracks.remove(remotePeerId);
    _pendingCandidates.remove(remotePeerId);
  }

  /// Toggles microphone mute state and broadcasts updated VOICE_STATE
  Future<void> toggleMic() async {
    _isMicMuted = !_isMicMuted;

    // Lazily acquire mic if not yet available and user wants to unmute
    if (!_isMicMuted && _localStream == null) {
      try {
        final stream = await _userMediaFunction({
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          },
          'video': false,
        });
        _localStream = stream;
        for (final entry in _peerConnections.entries) {
          final peerId = entry.key;
          final pc = entry.value;
          for (final track in _localStream!.getAudioTracks()) {
            track.enabled = true;
            await pc.addTrack(track, _localStream!);
          }
          await _initiateOfferTo(peerId);
        }
      } catch (e) {
        debugPrint(
            '[WebRtcVoiceController] Mic lazy acquisition failed on unmute: $e');
        _isMicMuted = true;
        _mutedUserIds.add(userId);
        notifyListeners();
        return;
      }
    }

    // Toggle hardware audio track
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = !_isMicMuted;
      }
    }

    // Update local mute state in set
    if (_isMicMuted) {
      _mutedUserIds.add(userId);
      if (_isLocalSpeaking) {
        _isLocalSpeaking = false;
        _activeSpeakerIds.remove(userId);
      }
    } else {
      _mutedUserIds.remove(userId);
    }

    await _sendSignalingMessage('VOICE_STATE', {
      'sender_id': userId,
      'user_name': userName,
      'is_muted': _isMicMuted,
      'is_speaking': _isLocalSpeaking,
      'action': 'update',
    });

    notifyListeners();
  }

  /// Explicitly sets microphone mute state
  Future<void> setMicMuted(bool muted) async {
    if (_isMicMuted == muted) return;
    await toggleMic();
  }

  /// Toggles deafen state (mutes all incoming remote voice streams)
  void toggleDeafen() {
    _isDeafened = !_isDeafened;

    // Mute or unmute all tracked remote audio tracks
    for (final tracks in _remoteAudioTracks.values) {
      for (final track in tracks) {
        track.enabled = !_isDeafened;
      }
    }
    for (final stream in _remoteStreams.values) {
      if (stream != null) {
        for (final track in stream.getAudioTracks()) {
          track.enabled = !_isDeafened;
        }
      }
    }

    if (_isDeafened) {
      _activeSpeakerIds.removeWhere((id) => id != userId);
      _handleAudioDucking();
    }

    notifyListeners();
  }

  /// Sets or triggers local speaking status (VAD or manual push-to-talk)
  void setLocalSpeaking(bool speaking) {
    if (_isMicMuted && speaking) return;
    if (_isLocalSpeaking == speaking) return;

    _isLocalSpeaking = speaking;
    if (_isLocalSpeaking) {
      _activeSpeakerIds.add(userId);
    } else {
      _activeSpeakerIds.remove(userId);
    }

    _sendSignalingMessage('VOICE_STATE', {
      'sender_id': userId,
      'user_name': userName,
      'is_muted': _isMicMuted,
      'is_speaking': _isLocalSpeaking,
      'action': 'update',
    });

    notifyListeners();
  }

  /// Manually marks a remote participant as speaking (for tests / manual VAD)
  @visibleForTesting
  void setRemoteSpeaking(String peerId, bool speaking) {
    if (speaking && !_isDeafened) {
      _activeSpeakerIds.add(peerId);
    } else {
      _activeSpeakerIds.remove(peerId);
    }
    _handleAudioDucking();
    notifyListeners();
  }

  /// Periodic VAD check querying audio level stats from WebRTC
  void _startVadTimer() {
    _vadTimer?.cancel();
    _vadTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (_isDisposed || _status != VoiceStatus.connected) return;

      // 1. Check local audio level if unmuted
      if (!_isMicMuted && _peerConnections.isNotEmpty) {
        bool localAudioDetected = false;
        for (final pc in _peerConnections.values) {
          try {
            final stats = await pc.getStats();
            for (final report in stats) {
              if (report.type == 'media-source' ||
                  report.type == 'track' ||
                  report.type == 'outbound-rtp') {
                final val =
                    report.values['audioLevel'] ?? report.values['energyLevel'];
                if (val != null) {
                  final lvl = double.tryParse(val.toString()) ?? 0.0;
                  if (lvl > 0.02) {
                    localAudioDetected = true;
                    break;
                  }
                }
              }
            }
          } catch (_) {}
          if (localAudioDetected) break;
        }

        if (localAudioDetected != _isLocalSpeaking) {
          setLocalSpeaking(localAudioDetected);
        }
      } else if (_isMicMuted || _peerConnections.isEmpty) {
        if (_isLocalSpeaking) {
          setLocalSpeaking(false);
        }
      }

      // 2. Check inbound audio stats for remote peers
      if (!_isDeafened) {
        for (final entry in _peerConnections.entries) {
          final peerId = entry.key;
          final pc = entry.value;
          bool hasAudioLevelReport = false;
          bool remoteSpeakingDetected = false;

          try {
            final stats = await pc.getStats();
            for (final report in stats) {
              if (report.type == 'inbound-rtp' || report.type == 'track') {
                final val = report.values['audioLevel'];
                if (val != null) {
                  hasAudioLevelReport = true;
                  final lvl = double.tryParse(val.toString()) ?? 0.0;
                  if (lvl > 0.02) {
                    remoteSpeakingDetected = true;
                    break;
                  }
                }
              }
            }
          } catch (_) {}

          if (hasAudioLevelReport) {
            final wasSpeaking = _activeSpeakerIds.contains(peerId);
            if (remoteSpeakingDetected && !wasSpeaking) {
              _activeSpeakerIds.add(peerId);
              _handleAudioDucking();
              notifyListeners();
            } else if (!remoteSpeakingDetected && wasSpeaking) {
              // Remote peer stopped speaking: clear speaker state and restore ducking
              _activeSpeakerIds.remove(peerId);
              _handleAudioDucking();
              notifyListeners();
            }
          }
        }
      } else {
        if (_activeSpeakerIds.any((id) => id != userId)) {
          _activeSpeakerIds.removeWhere((id) => id != userId);
          _handleAudioDucking();
          notifyListeners();
        }
      }
    });
  }

  /// Audio ducking: dynamically lowers video volume to 40% when participants talk
  void _handleAudioDucking() {
    if (!_audioDuckingEnabled || playerController == null) return;

    final bool someoneElseTalking =
        _activeSpeakerIds.any((id) => id != userId);

    if (someoneElseTalking && !_isDucking) {
      _isDucking = true;
      _savedVideoVolume = playerController!.volume;
      // Duck down to 40% of normal volume
      playerController!.setVolume(_savedVideoVolume * 0.4);
    } else if (!someoneElseTalking && _isDucking) {
      _isDucking = false;
      // Restore original video volume
      playerController!.setVolume(_savedVideoVolume);
    }
  }

  /// Toggles audio ducking feature
  void toggleAudioDucking() {
    _audioDuckingEnabled = !_audioDuckingEnabled;
    if (!_audioDuckingEnabled && _isDucking && playerController != null) {
      _isDucking = false;
      playerController!.setVolume(_savedVideoVolume);
    } else if (_audioDuckingEnabled) {
      _handleAudioDucking();
    }
    notifyListeners();
  }

  /// Disconnects from voice room and cleans up active peer connections
  Future<void> disconnect() async {
    if (_status == VoiceStatus.disconnected) return;

    _vadTimer?.cancel();

    await _sendSignalingMessage('VOICE_STATE', {
      'sender_id': userId,
      'user_name': userName,
      'is_muted': true,
      'is_speaking': false,
      'action': 'leave',
    });

    for (final pc in _peerConnections.values) {
      try {
        await pc.close();
        await pc.dispose();
      } catch (_) {}
    }
    _peerConnections.clear();
    _creatingPeerConnections.clear();
    _remoteStreams.clear();
    _remoteAudioTracks.clear();
    _pendingCandidates.clear();
    _activeSpeakerIds.clear();
    _mutedUserIds.clear();
    _mutedUserIds.add(userId);

    try {
      _localStream?.getTracks().forEach((t) => t.stop());
      await _localStream?.dispose();
      _localStream = null;
    } catch (_) {}

    try {
      await _voiceChannel?.unsubscribe();
      _voiceChannel = null;
    } catch (_) {}

    if (_isDucking && playerController != null) {
      _isDucking = false;
      playerController!.setVolume(_savedVideoVolume);
    }

    if (!_isDisposed) {
      _status = VoiceStatus.disconnected;
      notifyListeners();
    }
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _vadTimer?.cancel();

    if (_status == VoiceStatus.connected && _voiceChannel != null) {
      try {
        _voiceChannel!.sendBroadcastMessage(
          event: 'VOICE_STATE',
          payload: {
            'sender_id': userId,
            'user_name': userName,
            'is_muted': true,
            'is_speaking': false,
            'action': 'leave',
          },
        );
      } catch (_) {}
    }

    _isDisposed = true;

    for (final pc in _peerConnections.values) {
      try {
        pc.close();
        pc.dispose();
      } catch (_) {}
    }
    _peerConnections.clear();
    _creatingPeerConnections.clear();
    _remoteStreams.clear();
    _remoteAudioTracks.clear();
    _pendingCandidates.clear();
    _activeSpeakerIds.clear();
    _mutedUserIds.clear();

    try {
      _localStream?.getTracks().forEach((t) => t.stop());
      _localStream?.dispose();
      _localStream = null;
    } catch (_) {}

    try {
      _voiceChannel?.unsubscribe();
      _voiceChannel = null;
    } catch (_) {}

    if (_isDucking && playerController != null) {
      _isDucking = false;
      playerController!.setVolume(_savedVideoVolume);
    }

    super.dispose();
  }
}
