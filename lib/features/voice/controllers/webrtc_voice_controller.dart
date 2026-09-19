import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/network/webrtc_signaling_helper.dart';
import '../../room/controllers/unified_player_controller.dart';
import '../models/audio_ducking_config.dart';

export '../models/audio_ducking_config.dart';

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

typedef AudioRouteHandler = Future<void> Function(bool enableSpeaker);

/// Controller for WebRTC P2P Mesh Voice Chat using Supabase Realtime for signaling.
class WebRtcVoiceController extends ChangeNotifier {
  final String roomId;
  final String userId;
  final String userName;
  final UnifiedPlayerController? playerController;
  final SupabaseClient? supabase;
  final Map<String, dynamic>? iceConfiguration;
  final RealtimeChannel? sharedChannel;

  final UserMediaFunction _userMediaFunction;
  final PeerConnectionFunction _peerConnectionFunction;
  final AudioRouteHandler _audioRouteHandler;

  VoiceStatus _status = VoiceStatus.disconnected;
  bool _isMicMuted = true;
  bool _isDeafened = false;
  AudioDuckingConfig _duckingConfig;
  Timer? _duckingFadeTimer;
  Timer? _duckingReleaseTimer;
  bool _isLocalSpeaking = false;
  bool _isDucking = false;
  double _savedVideoVolume = 1.0;
  bool _isDisposed = false;
  String? _errorMessage;

  RealtimeChannel? _voiceChannel;
  MediaStream? _localStream;
  Timer? _vadTimer;

  // Active peer connections: remotePeerId -> RTCPeerConnection
  final Map<String, RTCPeerConnection> _peerConnections = {};
  // In-flight peer connection creation lock to prevent concurrency race conditions
  final Map<String, Future<RTCPeerConnection>> _creatingPeerConnections = {};
  // In-flight offers to prevent duplicate offer storm / collision
  final Set<String> _inFlightOffers = {};
  // Remote audio streams: remotePeerId -> MediaStream?
  final Map<String, MediaStream?> _remoteStreams = {};
  // Remote audio tracks: remotePeerId -> Set<MediaStreamTrack>
  final Map<String, Set<MediaStreamTrack>> _remoteAudioTracks = {};
  // Queued ICE candidates for peers whose remote descriptions are not yet set
  final IceCandidateBuffer _candidateBuffer = IceCandidateBuffer();
  // Set of user IDs currently speaking (local and/or remote)
  final Set<String> _activeSpeakerIds = {};
  // Set of user IDs currently muted (local and/or remote)
  final Set<String> _mutedUserIds = {};

  VoiceStatus get status => _status;
  bool get isMicMuted => _isMicMuted;
  bool get isDeafened => _isDeafened;
  bool get isConnected => _status == VoiceStatus.connected;
  bool get isAudioDuckingEnabled => _duckingConfig.enabled;
  AudioDuckingConfig get duckingConfig => _duckingConfig;
  double get duckingFactor => _duckingConfig.duckingFactor;
  bool get duckWhenSpeakingLocally => _duckingConfig.duckWhenSpeakingLocally;
  bool get isLocalSpeaking => _isLocalSpeaking;
  bool get isDucking => _isDucking;
  String? get errorMessage => _errorMessage;
  MediaStream? get localStream => _localStream;
  Set<String> get activeSpeakerIds => Set.unmodifiable(_activeSpeakerIds);
  Set<String> get mutedUserIds => Set.unmodifiable(_mutedUserIds);
  Map<String, RTCPeerConnection> get peerConnections =>
      Map.unmodifiable(_peerConnections);

  final bool autoCaptureMic;

  /// High-fidelity studio voice audio constraints with hardware/software AEC, NS, AGC, and 48kHz mono
  static const Map<String, dynamic> highQualityAudioConstraints = {
    'audio': {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
      'googEchoCancellation': true,
      'googAutoGainControl': true,
      'googNoiseSuppression': true,
      'googHighpassFilter': true,
      'googTypingNoiseDetection': true,
      'channelCount': 1,
      'sampleRate': 48000,
      'sampleSize': 16,
    },
    'video': false,
  };

  bool _hasCustomDuckingConfig;

  WebRtcVoiceController({
    required this.roomId,
    required this.userId,
    required this.userName,
    this.playerController,
    this.supabase,
    this.iceConfiguration,
    this.sharedChannel,
    AudioDuckingConfig? duckingConfig,
    bool? autoCaptureMic,
    UserMediaFunction? userMediaFunction,
    PeerConnectionFunction? peerConnectionFunction,
    AudioRouteHandler? audioRouteHandler,
  })  : _hasCustomDuckingConfig = duckingConfig != null,
        _duckingConfig = duckingConfig ?? const AudioDuckingConfig(),
        autoCaptureMic = autoCaptureMic ?? false,
        _userMediaFunction = userMediaFunction ?? _defaultUserMedia,
        _peerConnectionFunction =
            peerConnectionFunction ?? _defaultPeerConnection,
        _audioRouteHandler = audioRouteHandler ?? _defaultAudioRouteHandler {
    _mutedUserIds.add(userId);
  }

  static Future<void> _defaultAudioRouteHandler(bool enable) async {
    if (kIsWeb) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Configure Android audio for Hi-Fi multimedia & watch-party:
        // 1. manageAudioFocus: false ensures WebRTC NEVER steals audio focus or ducks the video media player.
        // 2. AndroidAudioMode.normal keeps full 48kHz stereo media fidelity and disables telephony hardware AEC
        //    which causes video audio to sound "kresek-kresek" (crackly/distorted) and "kecil" (ducked/muffled).
        // 3. AndroidAudioStreamType.music mixes WebRTC voice chat seamlessly into STREAM_MUSIC alongside video audio.
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration(
            manageAudioFocus: false,
            androidAudioMode: AndroidAudioMode.normal,
            androidAudioFocusMode: AndroidAudioFocusMode.gainTransientMayDuck,
            androidAudioStreamType: AndroidAudioStreamType.music,
            androidAudioAttributesUsageType:
                AndroidAudioAttributesUsageType.media,
            androidAudioAttributesContentType:
                AndroidAudioAttributesContentType.movie,
            forceHandleAudioRouting: false,
          ),
        );
        await Helper.setSpeakerphoneOn(enable);
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        await Helper.setAppleAudioConfiguration(
          AppleAudioConfiguration(
            appleAudioCategory: AppleAudioCategory.playAndRecord,
            appleAudioCategoryOptions: {
              AppleAudioCategoryOption.mixWithOthers,
              AppleAudioCategoryOption.defaultToSpeaker,
              AppleAudioCategoryOption.allowBluetooth,
              AppleAudioCategoryOption.allowBluetoothA2DP,
            },
            appleAudioMode: AppleAudioMode.moviePlayback,
          ),
        );
      }
    } catch (e) {
      debugPrint('[WebRtcVoiceController] Audio route configuration note: $e');
    }
  }

  /// Optimizes WebRTC SDP for Opus audio: sets 20ms ptime (halves packet loss / prevents jitter buffer underruns),
  /// FEC (packet loss recovery), 64kbps bitrate, and enforces mono for optimal AEC performance.
  static String optimizeAudioSdp(String sdp) {
    // Find opus payload type from a=rtpmap:<pt> opus/48000
    final rtpmapRegex =
        RegExp(r'a=rtpmap:(\d+)\s+opus/48000', caseSensitive: false);
    final match = rtpmapRegex.firstMatch(sdp);
    if (match == null) return sdp;
    final pt = match.group(1);

    final fmtpRegex = RegExp('a=fmtp:$pt (.*)');
    const optimalParams =
        'ptime=20;minptime=20;useinbandfec=1;usedtx=0;stereo=0;sprop-stereo=0;maxaveragebitrate=64000';

    if (fmtpRegex.hasMatch(sdp)) {
      return sdp.replaceAllMapped(fmtpRegex, (m) {
        final existing = m.group(1) ?? '';
        final params = existing
            .split(';')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        final paramMap = <String, String>{};
        for (final p in params) {
          final parts = p.split('=');
          if (parts.length == 2) {
            paramMap[parts[0].trim()] = parts[1].trim();
          }
        }
        paramMap['ptime'] = '20';
        paramMap['minptime'] = '20';
        paramMap['useinbandfec'] = '1';
        paramMap['usedtx'] = '0';
        paramMap['stereo'] = '0';
        paramMap['sprop-stereo'] = '0';
        paramMap['maxaveragebitrate'] = '64000';
        final newParams =
            paramMap.entries.map((e) => '${e.key}=${e.value}').join(';');
        return 'a=fmtp:$pt $newParams';
      });
    } else {
      return sdp.replaceFirst(
        'a=rtpmap:$pt opus/48000/2',
        'a=rtpmap:$pt opus/48000/2\r\na=fmtp:$pt $optimalParams',
      );
    }
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

    _errorMessage = null;
    _status = VoiceStatus.connecting;
    notifyListeners();

    try {
      // 1. Acquire local microphone stream only if autoCaptureMic is enabled
      // By default in production, hardware microphone is NEVER captured until user explicitly unmutes.
      if (autoCaptureMic) {
        try {
          final stream = await _userMediaFunction(highQualityAudioConstraints);
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

      // 2. Engage speakerphone & hardware AEC on Android
      await _audioRouteHandler(true);

      // Load persistent ducking preferences if not passed
      unawaited(_loadDuckingConfigFromPrefs());

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
      _errorMessage = 'Gagal menghubungkan voice chat: $e';
      _status = VoiceStatus.error;
      notifyListeners();
    }
  }

  /// Reconnects to voice chat after failure or disconnection
  Future<void> reconnect() async {
    await disconnect();
    _errorMessage = null;
    await connect();
  }

  void _setupSignaling() {
    if (sharedChannel != null) {
      _voiceChannel = sharedChannel;
    } else if (supabase != null) {
      final channelName = 'voice_$roomId';
      _voiceChannel = supabase!.channel(channelName);
    } else {
      return;
    }

    try {
      _voiceChannel!.onBroadcast(
        event: 'VOICE_STATE',
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          handleVoiceState(WebRtcSignalingHelper.extractPayload(payload));
        },
      );

      _voiceChannel!.onBroadcast(
        event: 'VOICE_OFFER',
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          handleVoiceOffer(WebRtcSignalingHelper.extractPayload(payload));
        },
      );

      _voiceChannel!.onBroadcast(
        event: 'VOICE_ANSWER',
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          handleVoiceAnswer(WebRtcSignalingHelper.extractPayload(payload));
        },
      );

      _voiceChannel!.onBroadcast(
        event: 'VOICE_ICE',
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          handleVoiceIce(WebRtcSignalingHelper.extractPayload(payload));
        },
      );

      if (sharedChannel == null) {
        _voiceChannel!.subscribe((status, error) {
          debugPrint(
              '[WebRtcVoiceController] Realtime status: $status (error: $error)');
        });
      }
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
      _handleAudioDucking(immediate: true);
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
      // Existing peer announced itself in response to our join.
      // Only initiate offer if connection does not already exist to avoid duplicate offer collisions!
      if (!_peerConnections.containsKey(senderId) &&
          userId.compareTo(senderId) > 0) {
        await _initiateOfferTo(senderId);
      }
      _handleAudioDucking();
      notifyListeners();
      return;
    }

    _handleAudioDucking();
    notifyListeners();
  }

  /// Creates and sends an SDP offer to [remotePeerId] with Opus optimization and in-flight guard
  Future<void> _initiateOfferTo(String remotePeerId) async {
    if (_isDisposed || _inFlightOffers.contains(remotePeerId)) return;

    _inFlightOffers.add(remotePeerId);
    try {
      final pc = await _getOrCreatePeerConnection(remotePeerId);

      // Verify signaling state is stable before creating offer
      try {
        final state = await pc.getSignalingState();
        if (state != RTCSignalingState.RTCSignalingStateStable) {
          debugPrint(
              '[WebRtcVoiceController] Skipping offer to $remotePeerId; state is $state');
          return;
        }
      } catch (_) {}

      final offer = await pc.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });

      final optimizedSdp = optimizeAudioSdp(offer.sdp ?? '');
      final optimizedOffer = RTCSessionDescription(optimizedSdp, offer.type);
      await pc.setLocalDescription(optimizedOffer);

      await _sendSignalingMessage(
        'VOICE_OFFER',
        WebRtcSignalingHelper.buildSdpPayload(
          senderId: userId,
          targetId: remotePeerId,
          sdp: optimizedOffer,
        ),
      );
    } catch (e) {
      debugPrint(
          '[WebRtcVoiceController] Error initiating offer to $remotePeerId: $e');
    } finally {
      _inFlightOffers.remove(remotePeerId);
    }
  }

  /// Handles incoming VOICE_OFFER targeted at this user with Opus optimization
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

      final optimizedSdp = optimizeAudioSdp(answer.sdp ?? '');
      final optimizedAnswer = RTCSessionDescription(optimizedSdp, answer.type);
      await pc.setLocalDescription(optimizedAnswer);

      // Flush any queued ICE candidates after local description is set (state is stable)
      await _flushPendingCandidates(senderId, pc);

      await _sendSignalingMessage(
        'VOICE_ANSWER',
        WebRtcSignalingHelper.buildSdpPayload(
          senderId: userId,
          targetId: senderId,
          sdp: optimizedAnswer,
        ),
      );
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
    final candMap = payload['candidate'];

    if (senderId == null || targetId != userId || candMap == null) return;

    final candidate = WebRtcSignalingHelper.parseIceCandidate(candMap);
    if (candidate == null) return;

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
    _candidateBuffer.enqueue(senderId, candidate);
  }

  Future<void> _flushPendingCandidates(
    String remotePeerId,
    RTCPeerConnection pc,
  ) async {
    await _candidateBuffer.flush(
      remotePeerId,
      pc,
      tag: 'WebRtcVoiceController',
    );
  }

  /// Safely attaches local audio tracks to [pc], reusing existing audio senders if present
  /// to avoid duplicate audio senders / m-lines in WebRTC unified-plan.
  Future<void> _attachLocalAudioTracksTo(RTCPeerConnection pc) async {
    if (_localStream == null) return;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !_isMicMuted;
      try {
        final senders = await pc.getSenders();
        final existingSender = senders.where((s) {
          try {
            return s.track?.kind == 'audio' || s.track == null;
          } catch (_) {
            return false;
          }
        }).firstOrNull;

        if (existingSender != null) {
          await existingSender.replaceTrack(track);
        } else {
          await pc.addTrack(track, _localStream!);
        }
      } catch (_) {
        try {
          await pc.addTrack(track, _localStream!);
        } catch (_) {}
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
      final pcConfig =
          WebRtcSignalingHelper.defaultPeerConnectionConfig(iceConfiguration);
      final pc = await _peerConnectionFunction(
        pcConfig,
        WebRtcSignalingHelper.defaultPeerConstraints,
      );

      _peerConnections[remotePeerId] = pc;

      // Attach local audio track if available, reusing existing sender if any
      if (_localStream != null) {
        await _attachLocalAudioTracksTo(pc);
      }

      // Send local ICE candidates to peer
      pc.onIceCandidate = (candidate) {
        if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
        _sendSignalingMessage(
          'VOICE_ICE',
          WebRtcSignalingHelper.buildIcePayload(
            senderId: userId,
            targetId: remotePeerId,
            candidate: candidate,
          ),
        );
      };

      // Track remote audio stream and tracks with deduplication
      pc.onTrack = (event) {
        if (event.track.kind == 'audio') {
          // Disable any prior active tracks from this remote peer to prevent duplicate/echo audio
          final existingTracks = _remoteAudioTracks[remotePeerId];
          if (existingTracks != null) {
            for (final oldTrack in existingTracks) {
              if (oldTrack.id != event.track.id) {
                oldTrack.enabled = false;
              }
            }
          }

          _remoteStreams[remotePeerId] =
              event.streams.isNotEmpty ? event.streams[0] : null;
          _remoteAudioTracks[remotePeerId] = {event.track};

          event.track.enabled = !_isDeafened;

          // Ensure speakerphone is active on mobile so audio routes to speaker with hardware AEC
          _audioRouteHandler(true);
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
    _candidateBuffer.clear(remotePeerId);
  }

  /// Toggles microphone mute state and broadcasts updated VOICE_STATE
  Future<void> toggleMic() async {
    _isMicMuted = !_isMicMuted;

    // Lazily acquire mic if not yet available and user wants to unmute
    if (!_isMicMuted && _localStream == null) {
      try {
        final stream = await _userMediaFunction(highQualityAudioConstraints);
        _localStream = stream;
        for (final entry in _peerConnections.entries) {
          final peerId = entry.key;
          final pc = entry.value;
          await _attachLocalAudioTracksTo(pc);
          await _initiateOfferTo(peerId);
        }
      } catch (e) {
        debugPrint(
            '[WebRtcVoiceController] Mic lazy acquisition failed on unmute: $e');
        _errorMessage = 'Gagal mengakses mikrofon: $e';
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

  /// Forces local microphone to mute (e.g. remotely muted by Host/Co-Host)
  Future<void> forceMute() async {
    await setMicMuted(true);
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
      _handleAudioDucking(immediate: true);
    }

    notifyListeners();
  }

  /// Sets or triggers local speaking status (VAD or manual push-to-talk)
  void setLocalSpeaking(bool speaking, {bool immediate = false}) {
    if (_isMicMuted && speaking) return;
    if (_isLocalSpeaking == speaking) return;

    _isLocalSpeaking = speaking;
    if (_isLocalSpeaking) {
      _activeSpeakerIds.add(userId);
    } else {
      _activeSpeakerIds.remove(userId);
    }

    if (_duckingConfig.duckWhenSpeakingLocally) {
      _handleAudioDucking(immediate: immediate || !_duckingConfig.smoothTransition);
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
  void setRemoteSpeaking(String peerId, bool speaking, {bool immediate = true}) {
    if (speaking && !_isDeafened) {
      _activeSpeakerIds.add(peerId);
    } else {
      _activeSpeakerIds.remove(peerId);
    }
    _handleAudioDucking(immediate: immediate);
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
                  if (lvl > 0.05) {
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
                  if (lvl > 0.05) {
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
              _handleAudioDucking(immediate: !_duckingConfig.smoothTransition);
              notifyListeners();
            } else if (!remoteSpeakingDetected && wasSpeaking) {
              // Remote peer stopped speaking: clear speaker state and restore ducking
              _activeSpeakerIds.remove(peerId);
              _handleAudioDucking(immediate: !_duckingConfig.smoothTransition);
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

  /// Loads saved ducking preferences from SharedPreferences
  Future<void> _loadDuckingConfigFromPrefs() async {
    if (_hasCustomDuckingConfig) return;
    try {
      final loaded = await AudioDuckingConfig.loadFromPrefs();
      if (!_isDisposed && !_hasCustomDuckingConfig) {
        _duckingConfig = loaded;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Audio ducking: dynamically lowers video volume when participants talk
  void _handleAudioDucking({bool immediate = false}) {
    if (!_duckingConfig.enabled || playerController == null) {
      if (_isDucking) {
        _duckingReleaseTimer?.cancel();
        _duckingReleaseTimer = null;
        _duckingFadeTimer?.cancel();
        _duckingFadeTimer = null;
        _isDucking = false;
        playerController!.setVolume(_savedVideoVolume);
        notifyListeners();
      }
      return;
    }

    final bool someoneElseTalking =
        !_isDeafened && _activeSpeakerIds.any((id) => id != userId);
    final bool selfTalking = !_isMicMuted &&
        _isLocalSpeaking &&
        _duckingConfig.duckWhenSpeakingLocally;
    final bool shouldDuck = someoneElseTalking || selfTalking;

    if (shouldDuck) {
      // Cancel any pending release hold timer since active speech is present
      _duckingReleaseTimer?.cancel();
      _duckingReleaseTimer = null;

      if (!_isDucking) {
        _isDucking = true;
        final vol = playerController!.volume;
        _savedVideoVolume = vol > 0.05 ? vol : 1.0;
        notifyListeners();
      }

      final targetVolume =
          (_savedVideoVolume * _duckingConfig.duckingFactor).clamp(0.0, 1.0);

      final bool useFade = !immediate &&
          _duckingConfig.smoothTransition &&
          _duckingConfig.attackDuration > Duration.zero;

      if (!useFade) {
        _duckingFadeTimer?.cancel();
        _duckingFadeTimer = null;
        playerController!.setVolume(targetVolume);
      } else {
        _fadeToVolume(targetVolume, _duckingConfig.attackDuration);
      }
    } else if (!shouldDuck && _isDucking) {
      // Speech stopped: engage release hold timer or restore volume immediately
      final bool useHold = !immediate &&
          _duckingConfig.smoothTransition &&
          _duckingConfig.releaseHoldDuration > Duration.zero;

      if (!useHold) {
        _duckingReleaseTimer?.cancel();
        _duckingReleaseTimer = null;
        _isDucking = false;

        final bool useReleaseFade = !immediate &&
            _duckingConfig.smoothTransition &&
            _duckingConfig.releaseDuration > Duration.zero;

        if (!useReleaseFade) {
          _duckingFadeTimer?.cancel();
          _duckingFadeTimer = null;
          playerController!.setVolume(_savedVideoVolume);
        } else {
          _fadeToVolume(_savedVideoVolume, _duckingConfig.releaseDuration);
        }
        notifyListeners();
      } else {
        // Wait for releaseHoldDuration before restoring volume (anti-pumping protection)
        if (_duckingReleaseTimer == null || !_duckingReleaseTimer!.isActive) {
          _duckingReleaseTimer =
              Timer(_duckingConfig.releaseHoldDuration, () {
            if (_isDisposed || !_isDucking) return;
            _isDucking = false;
            if (!_duckingConfig.smoothTransition ||
                _duckingConfig.releaseDuration == Duration.zero) {
              _duckingFadeTimer?.cancel();
              _duckingFadeTimer = null;
              playerController?.setVolume(_savedVideoVolume);
            } else {
              _fadeToVolume(_savedVideoVolume, _duckingConfig.releaseDuration);
            }
            notifyListeners();
          });
        }
      }
    }
  }

  void _fadeToVolume(double targetVolume, Duration duration) {
    _duckingFadeTimer?.cancel();
    if (playerController == null || duration == Duration.zero) {
      playerController?.setVolume(targetVolume);
      return;
    }

    final startVolume = playerController!.volume;
    if ((startVolume - targetVolume).abs() < 0.01) {
      playerController!.setVolume(targetVolume);
      return;
    }

    final totalSteps = (duration.inMilliseconds / 25).round().clamp(2, 20);
    final volumeDelta = targetVolume - startVolume;
    int step = 0;

    _duckingFadeTimer =
        Timer.periodic(const Duration(milliseconds: 25), (timer) {
      if (_isDisposed || playerController == null) {
        timer.cancel();
        return;
      }
      step++;
      if (step >= totalSteps) {
        timer.cancel();
        _duckingFadeTimer = null;
        playerController!.setVolume(targetVolume);
      } else {
        final progress = step / totalSteps;
        final eased = 1.0 - (1.0 - progress) * (1.0 - progress);
        final currentVol =
            (startVolume + (volumeDelta * eased)).clamp(0.0, 1.0);
        playerController!.setVolume(currentVol);
      }
    });
  }

  /// Toggles audio ducking feature
  void toggleAudioDucking() {
    _hasCustomDuckingConfig = true;
    _duckingConfig = _duckingConfig.copyWith(enabled: !_duckingConfig.enabled);
    _duckingConfig.saveToPrefs();
    _duckingReleaseTimer?.cancel();
    _duckingReleaseTimer = null;

    if (!_duckingConfig.enabled && _isDucking && playerController != null) {
      _duckingFadeTimer?.cancel();
      _duckingFadeTimer = null;
      _isDucking = false;
      playerController!.setVolume(_savedVideoVolume);
    } else if (_duckingConfig.enabled) {
      _handleAudioDucking(immediate: true);
    }
    notifyListeners();
  }

  /// Updates complete ducking configuration and persists preferences
  Future<void> updateDuckingConfig(AudioDuckingConfig newConfig) async {
    _hasCustomDuckingConfig = true;
    _duckingConfig = newConfig;
    await _duckingConfig.saveToPrefs();

    if (!_duckingConfig.enabled && _isDucking && playerController != null) {
      _duckingReleaseTimer?.cancel();
      _duckingReleaseTimer = null;
      _duckingFadeTimer?.cancel();
      _duckingFadeTimer = null;
      _isDucking = false;
      await playerController!.setVolume(_savedVideoVolume);
    } else if (_duckingConfig.enabled) {
      _handleAudioDucking(immediate: !_duckingConfig.smoothTransition);
    }
    notifyListeners();
  }

  /// Sets custom ducking factor (attenuation factor, e.g. 0.4 for 40%)
  Future<void> setDuckingFactor(double factor) async {
    await updateDuckingConfig(_duckingConfig.copyWith(duckingFactor: factor));
  }

  /// Sets whether local user speaking also ducks video audio
  Future<void> setDuckWhenSpeakingLocally(bool enable) async {
    await updateDuckingConfig(
      _duckingConfig.copyWith(duckWhenSpeakingLocally: enable),
    );
  }

  /// Disconnects from voice room and cleans up active peer connections
  Future<void> disconnect() async {
    if (_status == VoiceStatus.disconnected) return;

    _vadTimer?.cancel();
    _duckingReleaseTimer?.cancel();
    _duckingReleaseTimer = null;
    _duckingFadeTimer?.cancel();
    _duckingFadeTimer = null;

    await _sendSignalingMessage('VOICE_STATE', {
      'sender_id': userId,
      'user_name': userName,
      'is_muted': true,
      'is_speaking': false,
      'action': 'leave',
    });

    await WebRtcSignalingHelper.closeAndDisposePeers(
      _peerConnections,
      tag: 'WebRtcVoiceController',
    );
    _creatingPeerConnections.clear();
    _inFlightOffers.clear();
    _remoteStreams.clear();
    _remoteAudioTracks.clear();
    _candidateBuffer.clear();
    _activeSpeakerIds.clear();
    _mutedUserIds.clear();
    _mutedUserIds.add(userId);

    await _audioRouteHandler(false);

    await WebRtcSignalingHelper.disposeMediaStream(
      _localStream,
      tag: 'WebRtcVoiceController',
    );
    _localStream = null;

    if (sharedChannel == null) {
      try {
        await _voiceChannel?.unsubscribe();
      } catch (_) {}
    }
    _voiceChannel = null;

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
    _duckingReleaseTimer?.cancel();
    _duckingReleaseTimer = null;
    _duckingFadeTimer?.cancel();
    _duckingFadeTimer = null;

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
    _candidateBuffer.clear();
    _activeSpeakerIds.clear();
    _mutedUserIds.clear();

    WebRtcSignalingHelper.disposeMediaStream(
      _localStream,
      tag: 'WebRtcVoiceController',
    );
    _localStream = null;

    if (sharedChannel == null) {
      try {
        _voiceChannel?.unsubscribe();
      } catch (_) {}
    }
    _voiceChannel = null;

    if (_isDucking && playerController != null) {
      _isDucking = false;
      playerController!.setVolume(_savedVideoVolume);
    }

    super.dispose();
  }
}
