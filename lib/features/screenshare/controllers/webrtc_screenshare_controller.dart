import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/network/webrtc_signaling_helper.dart';
import '../../room/controllers/unified_player_controller.dart';

typedef DisplayMediaFunction = Future<MediaStream> Function(
  Map<String, dynamic> constraints,
);

typedef ScreenPeerConnectionFunction = Future<RTCPeerConnection> Function(
  Map<String, dynamic> configuration, [
  Map<String, dynamic> constraints,
]);

typedef RendererFactory = RTCVideoRenderer Function();

typedef BackgroundServiceHandler = Future<void> Function(bool enable);

/// Controller for WebRTC P2P Screen Sharing in Watch Party rooms.
class WebRtcScreenShareController extends ChangeNotifier {
  final String roomId;
  final String userId;
  final String userName;
  final UnifiedPlayerController? playerController;
  final SupabaseClient? supabase;
  final Map<String, dynamic>? iceConfiguration;
  final RealtimeChannel? sharedChannel;
  final bool Function()? isHostProvider;
  final bool Function()? isCollaborativeProvider;

  final DisplayMediaFunction _displayMediaFunction;
  final ScreenPeerConnectionFunction _peerConnectionFunction;
  final RendererFactory _rendererFactory;
  final BackgroundServiceHandler _backgroundServiceHandler;

  bool _isSharing = false;
  String? _sharerId;
  String? _sharerName;
  bool _isDisposed = false;
  String? _errorMessage;

  MediaStream? _localStream;
  MediaStream? _remoteStream;

  late final RTCVideoRenderer _localRenderer;
  late final RTCVideoRenderer _remoteRenderer;

  RealtimeChannel? _screenChannel;

  // Active peer connections for screen sharing: peerId -> RTCPeerConnection
  final Map<String, RTCPeerConnection> _peerConnections = {};
  // Pending ICE candidates: peerId -> List<RTCIceCandidate>
  final IceCandidateBuffer _candidateBuffer = IceCandidateBuffer();

  bool get isSharing => _isSharing;
  String? get sharerId => _sharerId;
  String? get sharerName => _sharerName;
  String? get errorMessage => _errorMessage;
  bool get isScreenSharingActive =>
      _isSharing || (_sharerId != null && _sharerId!.isNotEmpty);
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  RTCVideoRenderer get localRenderer => _localRenderer;
  RTCVideoRenderer get remoteRenderer => _remoteRenderer;
  Map<String, RTCPeerConnection> get peerConnections =>
      Map.unmodifiable(_peerConnections);

  WebRtcScreenShareController({
    required this.roomId,
    required this.userId,
    required this.userName,
    this.playerController,
    this.supabase,
    this.iceConfiguration,
    this.sharedChannel,
    this.isHostProvider,
    this.isCollaborativeProvider,
    DisplayMediaFunction? displayMediaFunction,
    ScreenPeerConnectionFunction? peerConnectionFunction,
    RendererFactory? rendererFactory,
    BackgroundServiceHandler? backgroundServiceHandler,
  })  : _displayMediaFunction =
            displayMediaFunction ?? _defaultDisplayMedia,
        _peerConnectionFunction =
            peerConnectionFunction ?? _defaultPeerConnection,
        _rendererFactory = rendererFactory ?? _defaultRendererFactory,
        _backgroundServiceHandler =
            backgroundServiceHandler ?? _defaultBackgroundHandler {
    _localRenderer = _rendererFactory();
    _remoteRenderer = _rendererFactory();
  }

  static Future<void> _defaultBackgroundHandler(bool enable) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      if (enable) {
        var hasPermissions = await FlutterBackground.hasPermissions;
        if (!hasPermissions) {
          const androidConfig = FlutterBackgroundAndroidConfig(
            notificationTitle: 'Nobarin - Berbagi Layar',
            notificationText: 'Sedang membagikan layar Anda.',
            notificationImportance: AndroidNotificationImportance.normal,
            notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
          );
          hasPermissions = await FlutterBackground.initialize(androidConfig: androidConfig);
        }
        if (hasPermissions && !FlutterBackground.isBackgroundExecutionEnabled) {
          await FlutterBackground.enableBackgroundExecution();
        }
      } else {
        if (FlutterBackground.isBackgroundExecutionEnabled) {
          await FlutterBackground.disableBackgroundExecution();
        }
      }
    } catch (e) {
      debugPrint('[WebRtcScreenShareController] flutter_background note: $e');
    }
  }

  static Future<MediaStream> _defaultDisplayMedia(
    Map<String, dynamic> constraints,
  ) {
    return navigator.mediaDevices.getDisplayMedia(constraints);
  }

  static Future<RTCPeerConnection> _defaultPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) {
    return createPeerConnection(configuration, constraints);
  }

  static RTCVideoRenderer _defaultRendererFactory() {
    return RTCVideoRenderer();
  }

  /// Initializes renderers and connects to the screen share signaling channel.
  Future<void> initialize() async {
    try {
      await _localRenderer.initialize();
    } catch (e) {
      debugPrint('[WebRtcScreenShareController] Local renderer init note: $e');
    }

    try {
      await _remoteRenderer.initialize();
    } catch (e) {
      debugPrint('[WebRtcScreenShareController] Remote renderer init note: $e');
    }

    _setupSignaling();

    // Query if anyone is already sharing screen in this room
    await _sendSignalingMessage('SCREEN_SHARE_STATE', {
      'sender_id': userId,
      'user_name': userName,
      'action': 'query',
    });
  }

  /// Checks whether current user is permitted to start sharing their screen
  bool get canShareScreen {
    if (_isDisposed) return false;
    // If someone else is already sharing, cannot share
    if (isScreenSharingActive && !_isSharing) return false;

    final isHost = isHostProvider?.call() ?? false;
    final isCollaborative = isCollaborativeProvider?.call() ?? true;

    // Host can always share; participants can share if room is collaborative
    return isHost || isCollaborative;
  }

  void _setupSignaling() {
    if (sharedChannel != null) {
      _screenChannel = sharedChannel;
    } else if (supabase != null) {
      final channelName = 'screenshare_$roomId';
      _screenChannel = supabase!.channel(channelName);
    } else {
      return;
    }

    try {
      _screenChannel!.onBroadcast(
        event: 'SCREEN_SHARE_STATE',
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          handleScreenShareState(WebRtcSignalingHelper.extractPayload(payload));
        },
      );

      _screenChannel!.onBroadcast(
        event: 'SCREEN_OFFER',
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          handleScreenOffer(WebRtcSignalingHelper.extractPayload(payload));
        },
      );

      _screenChannel!.onBroadcast(
        event: 'SCREEN_ANSWER',
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          handleScreenAnswer(WebRtcSignalingHelper.extractPayload(payload));
        },
      );

      _screenChannel!.onBroadcast(
        event: 'SCREEN_ICE',
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          handleScreenIce(WebRtcSignalingHelper.extractPayload(payload));
        },
      );

      if (sharedChannel == null) {
        _screenChannel!.subscribe((status, error) {
          debugPrint(
              '[WebRtcScreenShareController] Realtime status: $status (error: $error)');
        });
      }
    } catch (e) {
      debugPrint('[WebRtcScreenShareController] Error setting up signaling: $e');
    }
  }

  Future<void> _sendSignalingMessage(
    String event,
    Map<String, dynamic> payload,
  ) async {
    if (_isDisposed || _screenChannel == null || supabase == null) return;
    try {
      await _screenChannel!.sendBroadcastMessage(
        event: event,
        payload: payload,
      );
    } catch (e) {
      debugPrint(
          '[WebRtcScreenShareController] Error broadcasting $event: $e');
    }
  }

  /// Starts screen sharing by acquiring display media and broadcasting state to peers.
  Future<bool> startScreenShare() async {
    if (!canShareScreen || _isSharing) {
      if (isScreenSharingActive && !_isSharing) {
        _errorMessage = 'Seseorang sedang membagikan layar saat ini.';
      } else {
        _errorMessage = 'Anda tidak memiliki izin untuk membagikan layar.';
      }
      return false;
    }

    _errorMessage = null;

    try {
      await _backgroundServiceHandler(true);
      final stream = await _displayMediaFunction({
        'video': true,
        'audio': false,
      });

      _localStream = stream;
      try {
        _localRenderer.srcObject = _localStream;
      } catch (e) {
        debugPrint('[WebRtcScreenShareController] Error setting local srcObject: $e');
      }

      // Listen for system/browser stop event
      for (final track in stream.getVideoTracks()) {
        track.onEnded = () {
          debugPrint('[WebRtcScreenShareController] Screen capture ended by OS/Browser');
          stopScreenShare();
        };
      }

      // Automatically pause regular video player to prevent media overlap
      if (playerController != null && playerController!.isPlaying) {
        playerController!.pause();
      }

      _isSharing = true;
      _sharerId = userId;
      _sharerName = userName;
      notifyListeners();

      // Broadcast start event
      await _sendSignalingMessage('SCREEN_SHARE_STATE', {
        'action': 'start',
        'sharer_id': userId,
        'sharer_name': userName,
      });

      return true;
    } catch (e) {
      debugPrint('[WebRtcScreenShareController] startScreenShare error: $e');
      try {
        await _backgroundServiceHandler(false);
      } catch (_) {}
      _isSharing = false;
      _sharerId = null;
      _sharerName = null;
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('permission') ||
          errStr.contains('denied') ||
          errStr.contains('notallowederror')) {
        _errorMessage = 'Izin berbagi layar ditolak.';
      } else if (errStr.contains('notsupportederror') ||
          errStr.contains('unsupported')) {
        _errorMessage = 'Berbagi layar tidak didukung di perangkat ini.';
      } else {
        _errorMessage = 'Gagal memulai berbagi layar: $e';
      }
      notifyListeners();
      return false;
    }
  }

  /// Stops screen sharing, cleans up resources, and notifies peers.
  Future<void> stopScreenShare({bool forcedByHost = false}) async {
    if (_isSharing) {
      try {
        await _backgroundServiceHandler(false);
      } catch (e) {
        debugPrint('[WebRtcScreenShareController] Error stopping background service: $e');
      }

      try {
        _localStream?.getTracks().forEach((track) => track.stop());
        await _localStream?.dispose();
        _localStream = null;
        _localRenderer.srcObject = null;
      } catch (e) {
        debugPrint('[WebRtcScreenShareController] Error stopping local stream: $e');
      }

      await WebRtcSignalingHelper.closeAndDisposePeers(
        _peerConnections,
        tag: 'WebRtcScreenShareController',
      );
      _candidateBuffer.clear();

      _isSharing = false;
      _sharerId = null;
      _sharerName = null;

      await _sendSignalingMessage('SCREEN_SHARE_STATE', {
        'action': 'stop',
        'sharer_id': userId,
        'forced_by_host': forcedByHost,
      });

      notifyListeners();
    } else if (isHostProvider?.call() == true && isScreenSharingActive) {
      // Host force-stopping someone else's screen share
      await _sendSignalingMessage('SCREEN_SHARE_STATE', {
        'action': 'force_stop',
        'target_id': _sharerId,
        'sender_id': userId,
      });
    }
  }

  /// Handles incoming SCREEN_SHARE_STATE events
  @visibleForTesting
  Future<void> handleScreenShareState(Map<String, dynamic> payload) async {
    final action = payload['action'] as String? ?? '';
    final senderId = payload['sender_id'] as String?;
    final incomingSharerId = payload['sharer_id'] as String?;
    final incomingSharerName = payload['sharer_name'] as String?;

    if (action == 'start') {
      if (incomingSharerId != null && incomingSharerId != userId) {
        _sharerId = incomingSharerId;
        _sharerName = incomingSharerName ?? 'Peserta';
        _isSharing = false;

        // Auto pause local video playback when someone else starts sharing
        if (playerController != null && playerController!.isPlaying) {
          playerController!.pause();
        }

        notifyListeners();

        // Signal readiness to receive offer from the sharer
        await _sendSignalingMessage('SCREEN_SHARE_STATE', {
          'action': 'ready',
          'sender_id': userId,
          'target_id': incomingSharerId,
        });
      }
    } else if (action == 'ready') {
      final targetId = payload['target_id'] as String?;
      if (_isSharing && targetId == userId && senderId != null) {
        // Send SDP offer with local screen video track to the ready peer
        await _initiateOfferTo(senderId);
      }
    } else if (action == 'query') {
      // New peer asks if someone is sharing; if we are sharing, respond with start and initiate offer
      if (_isSharing && senderId != null && senderId != userId) {
        await _initiateOfferTo(senderId);
      }
    } else if (action == 'stop') {
      if (incomingSharerId == _sharerId || incomingSharerId == null) {
        _cleanUpRemoteView();
        notifyListeners();
      }
    } else if (action == 'force_stop') {
      final targetId = payload['target_id'] as String?;
      if (targetId == userId && _isSharing) {
        await stopScreenShare(forcedByHost: true);
      }
    }
  }

  void _cleanUpRemoteView() {
    _sharerId = null;
    _sharerName = null;
    _remoteStream = null;
    try {
      _remoteRenderer.srcObject = null;
    } catch (_) {}

    WebRtcSignalingHelper.closeAndDisposePeers(
      _peerConnections,
      tag: 'WebRtcScreenShareController',
    );
    _candidateBuffer.clear();
  }

  /// Initiates WebRTC SDP offer to [remotePeerId] containing the screen track
  Future<void> _initiateOfferTo(String remotePeerId) async {
    if (!_isSharing || _localStream == null) return;

    try {
      final pc = await _getOrCreatePeerConnection(remotePeerId, isSharer: true);

      final offer = await pc.createOffer({
        'offerToReceiveVideo': 0,
        'offerToReceiveAudio': 0,
      });
      await pc.setLocalDescription(offer);

      await _sendSignalingMessage(
        'SCREEN_OFFER',
        WebRtcSignalingHelper.buildSdpPayload(
          senderId: userId,
          targetId: remotePeerId,
          sdp: offer,
          extra: {'sharer_name': userName},
        ),
      );
    } catch (e) {
      debugPrint(
          '[WebRtcScreenShareController] Error initiating offer to $remotePeerId: $e');
    }
  }

  /// Handles incoming SCREEN_OFFER from the screen sharer
  @visibleForTesting
  Future<void> handleScreenOffer(Map<String, dynamic> payload) async {
    final senderId = payload['sender_id'] as String?;
    final targetId = payload['target_id'] as String?;
    final incomingSharerName = payload['sharer_name'] as String?;
    final sdpMap = payload['sdp'] as Map<String, dynamic>?;

    if (senderId == null || targetId != userId || sdpMap == null) return;

    _sharerId = senderId;
    if (incomingSharerName != null) {
      _sharerName = incomingSharerName;
    }

    try {
      final pc = await _getOrCreatePeerConnection(senderId, isSharer: false);
      final sdp = sdpMap['sdp'] as String? ?? '';
      final type = sdpMap['type'] as String? ?? 'offer';

      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));

      final answer = await pc.createAnswer({
        'offerToReceiveVideo': 1,
        'offerToReceiveAudio': 0,
      });
      await pc.setLocalDescription(answer);

      await _flushPendingCandidates(senderId, pc);

      await _sendSignalingMessage(
        'SCREEN_ANSWER',
        WebRtcSignalingHelper.buildSdpPayload(
          senderId: userId,
          targetId: senderId,
          sdp: answer,
        ),
      );

      notifyListeners();
    } catch (e) {
      debugPrint(
          '[WebRtcScreenShareController] Error handling screen offer: $e');
    }
  }

  /// Handles incoming SCREEN_ANSWER from a viewer
  @visibleForTesting
  Future<void> handleScreenAnswer(Map<String, dynamic> payload) async {
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
      await _flushPendingCandidates(senderId, pc);
    } catch (e) {
      debugPrint(
          '[WebRtcScreenShareController] Error handling screen answer: $e');
    }
  }

  /// Handles incoming SCREEN_ICE candidate
  @visibleForTesting
  Future<void> handleScreenIce(Map<String, dynamic> payload) async {
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

    _candidateBuffer.enqueue(senderId, candidate);
  }

  Future<void> _flushPendingCandidates(
    String remotePeerId,
    RTCPeerConnection pc,
  ) async {
    await _candidateBuffer.flush(
      remotePeerId,
      pc,
      tag: 'WebRtcScreenShareController',
    );
  }

  Future<RTCPeerConnection> _getOrCreatePeerConnection(
    String remotePeerId, {
    required bool isSharer,
  }) async {
    if (_peerConnections.containsKey(remotePeerId)) {
      return _peerConnections[remotePeerId]!;
    }

    final pcConfig =
        WebRtcSignalingHelper.defaultPeerConnectionConfig(iceConfiguration);
    final pc = await _peerConnectionFunction(
      pcConfig,
      WebRtcSignalingHelper.defaultPeerConstraints,
    );

    _peerConnections[remotePeerId] = pc;

    if (isSharer && _localStream != null) {
      for (final track in _localStream!.getVideoTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      _sendSignalingMessage(
        'SCREEN_ICE',
        WebRtcSignalingHelper.buildIcePayload(
          senderId: userId,
          targetId: remotePeerId,
          candidate: candidate,
        ),
      );
    };

    pc.onTrack = (event) {
      if (event.track.kind == 'video') {
        _remoteStream = event.streams.isNotEmpty ? event.streams[0] : null;
        try {
          _remoteRenderer.srcObject = _remoteStream;
        } catch (e) {
          debugPrint('[WebRtcScreenShareController] Error setting remote srcObject: $e');
        }
        notifyListeners();
      }
    };

    pc.onConnectionState = (state) {
      debugPrint(
          '[WebRtcScreenShareController] Peer $remotePeerId state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (!isSharer && remotePeerId == _sharerId) {
          _cleanUpRemoteView();
          notifyListeners();
        }
      }
    };

    pc.onIceConnectionState = (state) {
      debugPrint(
          '[WebRtcScreenShareController] Peer $remotePeerId ICE state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateClosed ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        if (!isSharer && remotePeerId == _sharerId) {
          _cleanUpRemoteView();
          notifyListeners();
        }
      }
    };

    return pc;
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;

    if (_isSharing) {
      try {
        _screenChannel?.sendBroadcastMessage(
          event: 'SCREEN_SHARE_STATE',
          payload: {
            'action': 'stop',
            'sharer_id': userId,
          },
        );
      } catch (_) {}
    }

    WebRtcSignalingHelper.closeAndDisposePeers(
      _peerConnections,
      tag: 'WebRtcScreenShareController',
    );
    _candidateBuffer.clear();

    WebRtcSignalingHelper.disposeMediaStream(
      _localStream,
      tag: 'WebRtcScreenShareController',
    );
    _localStream = null;

    try {
      _localRenderer.dispose();
    } catch (_) {}

    try {
      _remoteRenderer.dispose();
    } catch (_) {}

    if (sharedChannel == null) {
      try {
        _screenChannel?.unsubscribe();
      } catch (_) {}
    }
    _screenChannel = null;

    try {
      _backgroundServiceHandler(false);
    } catch (_) {}

    super.dispose();
  }
}
