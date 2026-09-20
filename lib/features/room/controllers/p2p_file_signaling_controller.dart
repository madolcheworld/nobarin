import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/network/p2p_file_stream_service.dart';
import '../../../core/network/webrtc_signaling_helper.dart';

typedef PeerConnectionFactory = Future<RTCPeerConnection> Function(
  Map<String, dynamic> configuration, [
  Map<String, dynamic> constraints,
]);

/// Manages WebRTC DataChannel peer connections for direct P2P file chunk streaming.
/// Enables Hosts to stream local files to remote Viewers over the public internet.
class P2PFileSignalingController extends ChangeNotifier {
  final String roomId;
  final String userId;
  final String userName;
  final bool isHost;
  final RealtimeChannel? sharedChannel;
  final SupabaseClient? supabase;
  final Map<String, dynamic>? iceConfiguration;
  final PeerConnectionFactory _peerConnectionFactory;

  RealtimeChannel? _signalingChannel;
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, RTCDataChannel> _dataChannels = {};
  final IceCandidateBuffer _candidateBuffer = IceCandidateBuffer();
  final Map<String, Future<String?>> _inFlightConnections = {};
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;
  Map<String, RTCPeerConnection> get peerConnections =>
      Map.unmodifiable(_peerConnections);

  P2PFileSignalingController({
    required this.roomId,
    required this.userId,
    required this.userName,
    required this.isHost,
    this.sharedChannel,
    this.supabase,
    this.iceConfiguration,
    PeerConnectionFactory? peerConnectionFactory,
  }) : _peerConnectionFactory =
            peerConnectionFactory ?? _defaultPeerConnection;

  static Future<RTCPeerConnection> _defaultPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) {
    return createPeerConnection(configuration, constraints);
  }

  /// Initializes signaling listeners on the shared room signaling channel.
  void initialize() {
    _signalingChannel = sharedChannel ?? supabase?.channel('signaling_$roomId');

    _signalingChannel?.onBroadcast(
      event: 'P2P_FILE_SDP_OFFER',
      callback: (payload) {
        if (_isDisposed) return;
        final data = WebRtcSignalingHelper.extractPayload(payload);
        handleFileOffer(data);
      },
    );

    _signalingChannel?.onBroadcast(
      event: 'P2P_FILE_SDP_ANSWER',
      callback: (payload) {
        if (_isDisposed) return;
        final data = WebRtcSignalingHelper.extractPayload(payload);
        handleFileAnswer(data);
      },
    );

    _signalingChannel?.onBroadcast(
      event: 'P2P_FILE_ICE',
      callback: (payload) {
        if (_isDisposed) return;
        final data = WebRtcSignalingHelper.extractPayload(payload);
        handleFileIce(data);
      },
    );
  }

  /// Connects a Viewer to a Host via WebRTC DataChannel (or LAN if reachable).
  /// Returns the stream URL (LAN direct URL or local loopback URL `http://127.0.0.1:...`).
  Future<String?> connectToHost({
    required String hostUserId,
    required P2PFileMetadata metadata,
  }) async {
    if (_isDisposed) return null;

    final key = '${hostUserId}_${metadata.fileName}_${metadata.fileSize}';
    if (_inFlightConnections.containsKey(key)) {
      return _inFlightConnections[key]!;
    }

    final future = _connectToHostInternal(
      hostUserId: hostUserId,
      metadata: metadata,
    );
    _inFlightConnections[key] = future;
    try {
      return await future;
    } finally {
      _inFlightConnections.remove(key);
    }
  }

  Future<String?> _connectToHostInternal({
    required String hostUserId,
    required P2PFileMetadata metadata,
  }) async {
    if (_isDisposed) return null;

    // 1. If on same LAN and reachable, use direct LAN URL without WebRTC overhead
    if (metadata.lanUrl != null && metadata.lanUrl!.isNotEmpty) {
      try {
        final streamUrl = await P2PFileStreamService.instance
            .prepareViewerStream(metadata: metadata);
        if (streamUrl == metadata.lanUrl) {
          debugPrint(
              '[P2PFileSignaling] Connected to host via LAN: $streamUrl');
          return streamUrl;
        }
      } catch (e) {
        debugPrint('[P2PFileSignaling] LAN ping check note: $e');
      }
    }

    // 2. Web check: Web cannot open loopback server
    if (kIsWeb) {
      debugPrint('[P2PFileSignaling] Web does not support local loopback streaming.');
      return null;
    }

    // 3. Connect via WebRTC DataChannel over Internet
    debugPrint(
        '[P2PFileSignaling] Connecting to host $hostUserId over WebRTC DataChannel...');

    try {
      final pc = await _getOrCreatePeerConnection(hostUserId, isInitiator: true);

      final dcInit = RTCDataChannelInit()..ordered = true;
      final dataChannel =
          await pc.createDataChannel('p2p_file_stream', dcInit);
      _dataChannels[hostUserId] = dataChannel;

      final openCompleter = Completer<void>();
      if (dataChannel.state == RTCDataChannelState.RTCDataChannelOpen) {
        openCompleter.complete();
      } else {
        dataChannel.onDataChannelState = (state) {
          debugPrint(
              '[P2PFileSignaling] DataChannel to host $hostUserId state: $state');
          if (state == RTCDataChannelState.RTCDataChannelOpen &&
              !openCompleter.isCompleted) {
            openCompleter.complete();
          }
        };
      }

      // Create and send SDP Offer
      final offer = await pc.createOffer({
        'offerToReceiveVideo': 0,
        'offerToReceiveAudio': 0,
      });
      await pc.setLocalDescription(offer);

      await _sendSignalingMessage(
        'P2P_FILE_SDP_OFFER',
        WebRtcSignalingHelper.buildSdpPayload(
          senderId: userId,
          targetId: hostUserId,
          sdp: offer,
          extra: {'metadata': metadata.toJson()},
        ),
      );

      // Wait for DataChannel to establish (10 second timeout)
      await openCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint(
              '[P2PFileSignaling] DataChannel open timed out for host $hostUserId');
        },
      );

      if (dataChannel.state != RTCDataChannelState.RTCDataChannelOpen) {
        debugPrint(
            '[P2PFileSignaling] DataChannel is not open (state=${dataChannel.state})');
        return null;
      }

      // Initialize loopback server backed by the DataChannel
      final loopbackUrl = await P2PFileStreamService.instance
          .prepareViewerStream(metadata: metadata, dataChannel: dataChannel);

      debugPrint(
          '[P2PFileSignaling] P2P stream ready for playback: $loopbackUrl');
      return loopbackUrl;
    } catch (e) {
      debugPrint('[P2PFileSignaling] Error connecting to host: $e');
      return null;
    }
  }

  /// Handles incoming SDP Offer from a Viewer requesting P2P file chunks (Host side).
  @visibleForTesting
  Future<void> handleFileOffer(Map<String, dynamic> payload) async {
    final senderId = payload['sender_id'] as String?;
    final targetId = payload['target_id'] as String?;
    final sdpMap = payload['sdp'] as Map<String, dynamic>?;

    if (senderId == null || targetId != userId || sdpMap == null) return;
    if (_isDisposed) return;

    debugPrint(
        '[P2PFileSignaling] Host received P2P_FILE_SDP_OFFER from viewer $senderId');

    try {
      final pc = await _getOrCreatePeerConnection(senderId, isInitiator: false);

      // Register DataChannel when received on the peer connection
      pc.onDataChannel = (RTCDataChannel channel) {
        debugPrint(
            '[P2PFileSignaling] Host received DataChannel from viewer $senderId (label: ${channel.label})');
        _dataChannels[senderId] = channel;

        if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
          P2PFileStreamService.instance
              .registerHostDataChannel(senderId, channel);
        } else {
          channel.onDataChannelState = (state) {
            debugPrint(
                '[P2PFileSignaling] Host DataChannel state with $senderId: $state');
            if (state == RTCDataChannelState.RTCDataChannelOpen) {
              P2PFileStreamService.instance
                  .registerHostDataChannel(senderId, channel);
            }
          };
        }
      };

      final sdp = sdpMap['sdp'] as String? ?? '';
      final type = sdpMap['type'] as String? ?? 'offer';
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));

      final answer = await pc.createAnswer({
        'offerToReceiveVideo': 0,
        'offerToReceiveAudio': 0,
      });
      await pc.setLocalDescription(answer);

      await _flushPendingCandidates(senderId, pc);

      await _sendSignalingMessage(
        'P2P_FILE_SDP_ANSWER',
        WebRtcSignalingHelper.buildSdpPayload(
          senderId: userId,
          targetId: senderId,
          sdp: answer,
        ),
      );

      debugPrint(
          '[P2PFileSignaling] Host sent P2P_FILE_SDP_ANSWER to viewer $senderId');
    } catch (e) {
      debugPrint('[P2PFileSignaling] Error handling file offer: $e');
    }
  }

  /// Handles incoming SDP Answer from the Host (Viewer side).
  @visibleForTesting
  Future<void> handleFileAnswer(Map<String, dynamic> payload) async {
    final senderId = payload['sender_id'] as String?;
    final targetId = payload['target_id'] as String?;
    final sdpMap = payload['sdp'] as Map<String, dynamic>?;

    if (senderId == null || targetId != userId || sdpMap == null) return;
    if (_isDisposed) return;

    debugPrint(
        '[P2PFileSignaling] Viewer received P2P_FILE_SDP_ANSWER from host $senderId');

    final pc = _peerConnections[senderId];
    if (pc == null) return;

    try {
      final sdp = sdpMap['sdp'] as String? ?? '';
      final type = sdpMap['type'] as String? ?? 'answer';
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      await _flushPendingCandidates(senderId, pc);
    } catch (e) {
      debugPrint('[P2PFileSignaling] Error handling file answer: $e');
    }
  }

  /// Handles incoming ICE candidates for P2P file transfer.
  @visibleForTesting
  Future<void> handleFileIce(Map<String, dynamic> payload) async {
    final senderId = payload['sender_id'] as String?;
    final targetId = payload['target_id'] as String?;
    final candMap = payload['candidate'];

    if (senderId == null || targetId != userId || candMap == null) return;
    if (_isDisposed) return;

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

  Future<RTCPeerConnection> _getOrCreatePeerConnection(
    String remotePeerId, {
    required bool isInitiator,
  }) async {
    if (_peerConnections.containsKey(remotePeerId)) {
      return _peerConnections[remotePeerId]!;
    }

    final pcConfig =
        WebRtcSignalingHelper.defaultPeerConnectionConfig(iceConfiguration);
    final pc = await _peerConnectionFactory(
      pcConfig,
      WebRtcSignalingHelper.defaultPeerConstraints,
    );

    _peerConnections[remotePeerId] = pc;

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      _sendSignalingMessage(
        'P2P_FILE_ICE',
        WebRtcSignalingHelper.buildIcePayload(
          senderId: userId,
          targetId: remotePeerId,
          candidate: candidate,
        ),
      );
    };

    pc.onConnectionState = (state) {
      debugPrint(
          '[P2PFileSignaling] Peer $remotePeerId connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _cleanupPeer(remotePeerId);
      }
    };

    return pc;
  }

  Future<void> _flushPendingCandidates(
    String remotePeerId,
    RTCPeerConnection pc,
  ) async {
    await _candidateBuffer.flush(
      remotePeerId,
      pc,
      tag: 'P2PFileSignaling',
    );
  }

  Future<void> _sendSignalingMessage(
    String event,
    Map<String, dynamic> payload,
  ) async {
    if (_signalingChannel != null) {
      try {
        await _signalingChannel!.sendBroadcastMessage(
          event: event,
          payload: payload,
        );
      } catch (e) {
        debugPrint('[P2PFileSignaling] Error sending $event: $e');
      }
    }
  }

  void _cleanupPeer(String peerId) {
    try {
      _dataChannels[peerId]?.close();
    } catch (_) {}
    _dataChannels.remove(peerId);

    try {
      _peerConnections[peerId]?.close();
    } catch (_) {}
    _peerConnections.remove(peerId);

    _candidateBuffer.clear(peerId);
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (final channel in _dataChannels.values) {
      try {
        channel.close();
      } catch (_) {}
    }
    _dataChannels.clear();

    for (final pc in _peerConnections.values) {
      try {
        pc.close();
      } catch (_) {}
    }
    _peerConnections.clear();
    _candidateBuffer.clear();

    super.dispose();
  }
}
