import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/webrtc_signaling_helper.dart';
import '../constants/p2p_constants.dart';
import 'proxy/p2p_loopback_proxy.dart';

enum P2pViewerState {
  idle,
  connecting,
  connected,
  streaming,
  error,
}

class P2pWebRtcViewerClient extends ChangeNotifier {
  final String roomId;
  final String userId;
  final String userName;
  final SupabaseClient? supabase;
  final RealtimeChannel? sharedChannel;
  final Map<String, dynamic>? iceConfiguration;

  String? _hostId;
  String? _hostName;
  String? _fileId;
  String? _fileName;
  int _fileSize = 0;
  String _mimeType = 'video/mp4';

  P2pViewerState _state = P2pViewerState.idle;
  String? _errorMessage;
  int _bytesReceived = 0;
  bool _isDisposed = false;

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  StreamSubscription? _dataChannelStateSub;
  StreamSubscription? _dataChannelMessageSub;
  RealtimeChannel? _signalingChannel;

  final IceCandidateBuffer _candidateBuffer = IceCandidateBuffer();
  final Map<int, Completer<Uint8List>> _pendingRequests = {};
  int _nextReqId = 1;

  late final P2pLoopbackProxy _loopbackProxy;

  P2pViewerState get state => _state;
  String? get errorMessage => _errorMessage;
  String? get hostId => _hostId;
  String? get fileName => _fileName;
  int get fileSize => _fileSize;
  int get bytesReceived => _bytesReceived;
  bool get isConnected => _state == P2pViewerState.connected || _state == P2pViewerState.streaming;
  String get streamUrl => _loopbackProxy.streamUrl;

  P2pWebRtcViewerClient({
    required this.roomId,
    required this.userId,
    required this.userName,
    this.supabase,
    this.sharedChannel,
    this.iceConfiguration,
  }) {
    _loopbackProxy = P2pLoopbackProxy.create();
    _setupSignaling();
  }

  void _setupSignaling() {
    if (sharedChannel != null) {
      _signalingChannel = sharedChannel;
    } else if (supabase != null) {
      final channelName = 'p2p_streaming_$roomId';
      _signalingChannel = supabase!.channel(channelName);
    } else {
      return;
    }

    try {
      _signalingChannel!.onBroadcast(
        event: P2pConstants.eventAnnounce,
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          _handleHostAnnounce(WebRtcSignalingHelper.extractPayload(payload));
        },
      );

      _signalingChannel!.onBroadcast(
        event: P2pConstants.eventSignalAnswer,
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          _handleHostAnswer(WebRtcSignalingHelper.extractPayload(payload));
        },
      );

      _signalingChannel!.onBroadcast(
        event: P2pConstants.eventSignalIce,
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          _handleHostIce(WebRtcSignalingHelper.extractPayload(payload));
        },
      );

      _signalingChannel!.onBroadcast(
        event: P2pConstants.eventOffline,
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          final host = payload['host_id'] as String?;
          if (host == _hostId) {
            disconnect();
          }
        },
      );

      if (sharedChannel == null) {
        _signalingChannel!.subscribe();
      }
    } catch (e) {
      debugPrint('[P2pViewerClient] Error setup signaling: $e');
    }
  }

  /// Sends a query asking if any host is currently streaming a local video
  Future<void> queryActiveStream() async {
    if (_signalingChannel == null) return;
    try {
      await _signalingChannel!.sendBroadcastMessage(
        event: 'P2P_STREAM_QUERY',
        payload: {'sender_id': userId},
      );
    } catch (_) {}
  }

  void _handleHostAnnounce(Map<String, dynamic> payload) {
    final hostId = payload['host_id'] as String?;
    if (hostId == null || hostId == userId) return;

    _hostId = hostId;
    _hostName = payload['host_name'] as String?;
    _fileId = payload['file_id'] as String?;
    _fileName = payload['file_name'] as String?;
    _fileSize = (payload['file_size'] as num?)?.toInt() ?? 0;
    _mimeType = payload['mime_type'] as String? ?? 'video/mp4';

    notifyListeners();

    // Automatically connect to host if not already connected
    if (_state == P2pViewerState.idle || _state == P2pViewerState.error) {
      connectToHost(hostId);
    }
  }

  /// Connects to the host using WebRTC DataChannel
  Future<void> connectToHost(String hostId) async {
    if (_isDisposed) return;
    _hostId = hostId;
    _state = P2pViewerState.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      await _cleanupConnection();

      final config = WebRtcSignalingHelper.defaultPeerConnectionConfig(
        iceConfiguration ?? ApiConstants.rtcIceConfiguration,
      );
      final pc = await createPeerConnection(
        config,
        WebRtcSignalingHelper.defaultPeerConstraints,
      );
      _peerConnection = pc;

      pc.onIceCandidate = (candidate) {
        if (_isDisposed) return;
        _signalingChannel?.sendBroadcastMessage(
          event: P2pConstants.eventSignalIce,
          payload: WebRtcSignalingHelper.buildIcePayload(
            senderId: userId,
            targetId: hostId,
            candidate: candidate,
          ),
        );
      };

      pc.onConnectionState = (state) {
        debugPrint('[P2pViewerClient] Peer connection state: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _state = P2pViewerState.connected;
          notifyListeners();
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _state = P2pViewerState.error;
          _errorMessage = 'Koneksi P2P terputus ($state)';
          notifyListeners();
        }
      };

      // Viewer creates the DataChannel
      final dcInit = RTCDataChannelInit()
        ..ordered = true
        ..maxRetransmits = 30;

      final dc = await pc.createDataChannel(P2pConstants.dataChannelLabel, dcInit);
      _setupDataChannel(dc);

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      await _signalingChannel?.sendBroadcastMessage(
        event: P2pConstants.eventSignalOffer,
        payload: WebRtcSignalingHelper.buildSdpPayload(
          senderId: userId,
          targetId: hostId,
          sdp: offer,
        ),
      );
    } catch (e) {
      debugPrint('[P2pViewerClient] Error connecting to host: $e');
      _state = P2pViewerState.error;
      _errorMessage = 'Gagal menghubungkan ke host: $e';
      notifyListeners();
    }
  }

  void _setupDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;

    _dataChannelStateSub = channel.stateChangeStream.listen((state) {
      debugPrint('[P2pViewerClient] DataChannel state: $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _state = P2pViewerState.connected;
        notifyListeners();
        _requestMetadata();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _state = P2pViewerState.idle;
        notifyListeners();
      }
    });

    _dataChannelMessageSub = channel.messageStream.listen((msg) {
      if (_isDisposed) return;
      _handleDataChannelMessage(msg);
    });

    if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      _state = P2pViewerState.connected;
      notifyListeners();
      _requestMetadata();
    }
  }

  void _requestMetadata() {
    if (_dataChannel == null || _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    try {
      _dataChannel!.send(
        RTCDataChannelMessage(jsonEncode({'type': P2pConstants.msgMetadataReq})),
      );
    } catch (e) {
      debugPrint('[P2pViewerClient] Error requesting metadata: $e');
    }
  }

  void _handleHostAnswer(Map<String, dynamic> payload) async {
    final senderId = payload['sender_id'] as String?;
    final targetId = payload['target_id'] as String?;
    if (senderId != _hostId || targetId != userId || _peerConnection == null) return;

    final sdpDesc = WebRtcSignalingHelper.parseSdp(payload['sdp']);
    if (sdpDesc == null) return;

    try {
      await _peerConnection!.setRemoteDescription(sdpDesc);
      await _candidateBuffer.drain(senderId!, _peerConnection!);
    } catch (e) {
      debugPrint('[P2pViewerClient] Error setting remote description: $e');
    }
  }

  void _handleHostIce(Map<String, dynamic> payload) {
    final senderId = payload['sender_id'] as String?;
    final targetId = payload['target_id'] as String?;
    if (senderId != _hostId || targetId != userId) return;

    final candidate = WebRtcSignalingHelper.parseIceCandidate(payload['candidate']);
    if (candidate == null) return;

    if (_peerConnection != null) {
      _peerConnection!.addCandidate(candidate);
    } else {
      _candidateBuffer.add(senderId!, candidate);
    }
  }

  void _handleDataChannelMessage(RTCDataChannelMessage message) {
    if (message.isBinary) {
      final data = message.binary;
      if (data.length < 8) return;

      final bdata = ByteData.view(data.buffer, data.offsetInBytes, data.lengthInBytes);
      final reqId = bdata.getUint32(0, Endian.big);
      final start = bdata.getUint32(4, Endian.big);
      final payload = data.sublist(8);

      final completer = _pendingRequests.remove(reqId);
      if (completer != null && !completer.isCompleted) {
        _bytesReceived += payload.length;
        completer.complete(payload);
        if (_state != P2pViewerState.streaming) {
          _state = P2pViewerState.streaming;
          notifyListeners();
        }
      }
      return;
    }

    try {
      final json = jsonDecode(message.text) as Map<String, dynamic>;
      final type = json['type'] as String?;

      if (type == P2pConstants.msgMetadataRes) {
        _fileName = json['name'] as String? ?? _fileName;
        _fileSize = (json['size'] as num?)?.toInt() ?? _fileSize;
        _mimeType = json['mime_type'] as String? ?? _mimeType;
        _startLoopbackProxy();
        notifyListeners();
      } else if (type == P2pConstants.msgChunkEof) {
        final reqId = json['req_id'] as int?;
        if (reqId != null) {
          final completer = _pendingRequests.remove(reqId);
          if (completer != null && !completer.isCompleted) {
            completer.complete(Uint8List(0));
          }
        }
      }
    } catch (e) {
      debugPrint('[P2pViewerClient] Error decoding message: $e');
    }
  }

  Future<void> _startLoopbackProxy() async {
    if (_fileSize <= 0) return;

    try {
      await _loopbackProxy.start(
        fileSize: _fileSize,
        mimeType: _mimeType,
        fileName: _fileName ?? 'p2p_stream.mp4',
        fetchChunk: (start, length) => fetchChunk(start, length),
      );
      notifyListeners();
    } catch (e) {
      debugPrint('[P2pViewerClient] Error starting loopback proxy: $e');
    }
  }

  /// Requests a byte chunk from the host over the WebRTC DataChannel
  Future<Uint8List> fetchChunk(int start, int length) async {
    if (_dataChannel == null ||
        _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      return Uint8List(0);
    }

    final reqId = _nextReqId++;
    final completer = Completer<Uint8List>();
    _pendingRequests[reqId] = completer;

    try {
      _dataChannel!.send(
        RTCDataChannelMessage(
          jsonEncode({
            'type': P2pConstants.msgChunkReq,
            'req_id': reqId,
            'start': start,
            'length': length,
          }),
        ),
      );

      // 10-second timeout per chunk
      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _pendingRequests.remove(reqId);
          return Uint8List(0);
        },
      );
    } catch (e) {
      _pendingRequests.remove(reqId);
      return Uint8List(0);
    }
  }

  Future<void> _cleanupConnection() async {
    for (final c in _pendingRequests.values) {
      if (!c.isCompleted) c.complete(Uint8List(0));
    }
    _pendingRequests.clear();

    await _dataChannelStateSub?.cancel();
    await _dataChannelMessageSub?.cancel();
    _dataChannelStateSub = null;
    _dataChannelMessageSub = null;

    await _dataChannel?.close();
    _dataChannel = null;

    await _peerConnection?.close();
    _peerConnection = null;

    await _loopbackProxy.stop();
  }

  Future<void> disconnect() async {
    await _cleanupConnection();
    _state = P2pViewerState.idle;
    _hostId = null;
    _fileName = null;
    _fileSize = 0;
    _bytesReceived = 0;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cleanupConnection();
    _candidateBuffer.clearAll();
    super.dispose();
  }
}
