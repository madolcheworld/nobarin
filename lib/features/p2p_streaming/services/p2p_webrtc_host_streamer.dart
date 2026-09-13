import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/webrtc_signaling_helper.dart';
import '../constants/p2p_constants.dart';
import '../models/local_video_file.dart';
import 'file_reader/p2p_file_reader.dart';

class P2pWebRtcHostStreamer extends ChangeNotifier {
  final String roomId;
  final String userId;
  final String userName;
  final SupabaseClient? supabase;
  final RealtimeChannel? sharedChannel;
  final Map<String, dynamic>? iceConfiguration;

  LocalVideoFile? _currentFile;
  P2pFileChunkReader? _chunkReader;
  bool _isDisposed = false;
  bool _isAnnounced = false;

  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, RTCDataChannel> _dataChannels = {};
  final Map<String, StreamSubscription> _dataChannelMessageSubs = {};
  final Map<String, StreamSubscription> _dataChannelStateSubs = {};
  final IceCandidateBuffer _candidateBuffer = IceCandidateBuffer();

  int _bytesSent = 0;
  RealtimeChannel? _signalingChannel;

  LocalVideoFile? get currentFile => _currentFile;
  bool get isStreaming => _currentFile != null;
  int get activeViewersCount => _dataChannels.values
      .where((dc) => dc.state == RTCDataChannelState.RTCDataChannelOpen)
      .length;
  int get totalBytesSent => _bytesSent;

  P2pWebRtcHostStreamer({
    required this.roomId,
    required this.userId,
    required this.userName,
    this.supabase,
    this.sharedChannel,
    this.iceConfiguration,
  }) {
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
        event: P2pConstants.eventSignalOffer,
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          _handleViewerOffer(WebRtcSignalingHelper.extractPayload(payload));
        },
      );

      _signalingChannel!.onBroadcast(
        event: P2pConstants.eventSignalIce,
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed) return;
          _handleViewerIce(WebRtcSignalingHelper.extractPayload(payload));
        },
      );

      _signalingChannel!.onBroadcast(
        event: 'P2P_STREAM_QUERY',
        callback: (Map<String, dynamic> payload) {
          if (_isDisposed || _currentFile == null) return;
          announceStream();
        },
      );

      if (sharedChannel == null) {
        _signalingChannel!.subscribe();
      }
    } catch (e) {
      debugPrint('[P2pHostStreamer] Error setup signaling: $e');
    }
  }

  /// Sets the local video file to be streamed over WebRTC DataChannel
  Future<void> setLocalVideoFile(LocalVideoFile file) async {
    await stopStreaming(notify: false);

    _currentFile = file;
    _chunkReader = P2pFileChunkReader.create(file);
    await _chunkReader!.open();
    _bytesSent = 0;
    _isAnnounced = true;

    notifyListeners();
    await announceStream();
  }

  /// Announces the stream to all room participants via Supabase Realtime
  Future<void> announceStream() async {
    if (_currentFile == null || _signalingChannel == null) return;

    try {
      await _signalingChannel!.sendBroadcastMessage(
        event: P2pConstants.eventAnnounce,
        payload: {
          'host_id': userId,
          'host_name': userName,
          'file_id': _currentFile!.id,
          'file_name': _currentFile!.name,
          'file_size': _currentFile!.size,
          'mime_type': _currentFile!.mimeType,
          'extension': _currentFile!.extension,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (e) {
      debugPrint('[P2pHostStreamer] Error broadcasting announce: $e');
    }
  }

  Future<void> _handleViewerOffer(Map<String, dynamic> payload) async {
    final senderId = payload['sender_id'] as String?;
    final targetId = payload['target_id'] as String?;
    if (senderId == null || targetId != userId || _currentFile == null) return;

    final sdpDesc = WebRtcSignalingHelper.parseSdp(payload['sdp']);
    if (sdpDesc == null) return;

    try {
      // Clean up previous connection with this viewer if any
      await _closeViewerConnection(senderId);

      final config = WebRtcSignalingHelper.defaultPeerConnectionConfig(
        iceConfiguration ?? ApiConstants.rtcIceConfiguration,
      );
      final pc = await createPeerConnection(
        config,
        WebRtcSignalingHelper.defaultPeerConstraints,
      );
      _peerConnections[senderId] = pc;

      pc.onIceCandidate = (candidate) {
        if (_isDisposed) return;
        _signalingChannel?.sendBroadcastMessage(
          event: P2pConstants.eventSignalIce,
          payload: WebRtcSignalingHelper.buildIcePayload(
            senderId: userId,
            targetId: senderId,
            candidate: candidate,
          ),
        );
      };

      pc.onDataChannel = (channel) {
        if (_isDisposed) return;
        if (channel.label == P2pConstants.dataChannelLabel) {
          _registerDataChannel(senderId, channel);
        }
      };

      pc.onConnectionState = (state) {
        debugPrint('[P2pHostStreamer] Viewer $senderId connectionState: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _closeViewerConnection(senderId);
        }
      };

      await pc.setRemoteDescription(sdpDesc);
      await _candidateBuffer.drain(senderId, pc);

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      await _signalingChannel?.sendBroadcastMessage(
        event: P2pConstants.eventSignalAnswer,
        payload: WebRtcSignalingHelper.buildSdpPayload(
          senderId: userId,
          targetId: senderId,
          sdp: answer,
        ),
      );
    } catch (e) {
      debugPrint('[P2pHostStreamer] Error processing offer from $senderId: $e');
    }
  }

  void _handleViewerIce(Map<String, dynamic> payload) {
    final senderId = payload['sender_id'] as String?;
    final targetId = payload['target_id'] as String?;
    if (senderId == null || targetId != userId) return;

    final candidate = WebRtcSignalingHelper.parseIceCandidate(payload['candidate']);
    if (candidate == null) return;

    final pc = _peerConnections[senderId];
    if (pc != null) {
      pc.addCandidate(candidate);
    } else {
      _candidateBuffer.add(senderId, candidate);
    }
  }

  void _registerDataChannel(String viewerId, RTCDataChannel channel) {
    _dataChannels[viewerId] = channel;

    _dataChannelStateSubs[viewerId] = channel.stateChangeStream.listen((state) {
      debugPrint('[P2pHostStreamer] DataChannel to $viewerId state: $state');
      notifyListeners();
      if (state == RTCDataChannelState.RTCDataChannelOpen && _currentFile != null) {
        _sendMetadata(channel);
      }
    });

    _dataChannelMessageSubs[viewerId] = channel.messageStream.listen((msg) {
      if (_isDisposed) return;
      _handleDataChannelMessage(viewerId, channel, msg);
    });

    if (channel.state == RTCDataChannelState.RTCDataChannelOpen && _currentFile != null) {
      _sendMetadata(channel);
    }
    notifyListeners();
  }

  void _sendMetadata(RTCDataChannel channel) {
    if (_currentFile == null) return;
    try {
      channel.send(
        RTCDataChannelMessage(
          jsonEncode({
            'type': P2pConstants.msgMetadataRes,
            'file_id': _currentFile!.id,
            'name': _currentFile!.name,
            'size': _currentFile!.size,
            'mime_type': _currentFile!.mimeType,
            'extension': _currentFile!.extension,
          }),
        ),
      );
    } catch (e) {
      debugPrint('[P2pHostStreamer] Error sending metadata: $e');
    }
  }

  Future<void> _handleDataChannelMessage(
    String viewerId,
    RTCDataChannel channel,
    RTCDataChannelMessage message,
  ) async {
    if (message.isBinary) return;

    try {
      final text = message.text;
      final json = jsonDecode(text) as Map<String, dynamic>;
      final type = json['type'] as String?;

      if (type == P2pConstants.msgMetadataReq) {
        _sendMetadata(channel);
      } else if (type == P2pConstants.msgChunkReq) {
        final reqId = json['req_id'] as int? ?? 0;
        final start = json['start'] as int? ?? 0;
        final length = json['length'] as int? ?? P2pConstants.chunkSize;

        await _serveChunk(channel, reqId, start, length);
      } else if (type == P2pConstants.msgPing) {
        channel.send(RTCDataChannelMessage(jsonEncode({'type': P2pConstants.msgPong})));
      }
    } catch (e) {
      debugPrint('[P2pHostStreamer] Error handling data channel message: $e');
    }
  }

  Future<void> _serveChunk(
    RTCDataChannel channel,
    int reqId,
    int start,
    int length,
  ) async {
    if (_chunkReader == null || _currentFile == null) return;

    try {
      // Respect flow control: pause briefly if buffer is congested
      while ((channel.bufferedAmount ?? 0) > P2pConstants.maxBufferedAmount) {
        await Future.delayed(const Duration(milliseconds: 20));
        if (_isDisposed || channel.state != RTCDataChannelState.RTCDataChannelOpen) {
          return;
        }
      }

      final Uint8List chunk = await _chunkReader!.readChunk(start, length);

      if (chunk.isEmpty || start >= _currentFile!.size) {
        channel.send(
          RTCDataChannelMessage(
            jsonEncode({
              'type': P2pConstants.msgChunkEof,
              'req_id': reqId,
              'start': start,
            }),
          ),
        );
        return;
      }

      // Binary format: [4 bytes reqId (uint32)] + [4 bytes start (uint32)] + [payload]
      final packet = Uint8List(8 + chunk.length);
      final bdata = ByteData.view(packet.buffer);
      bdata.setUint32(0, reqId, Endian.big);
      bdata.setUint32(4, start, Endian.big);
      packet.setAll(8, chunk);

      channel.send(RTCDataChannelMessage.fromBinary(packet));
      _bytesSent += chunk.length;
      notifyListeners();
    } catch (e) {
      debugPrint('[P2pHostStreamer] Error serving chunk $start ($length bytes): $e');
    }
  }

  Future<void> _closeViewerConnection(String viewerId) async {
    try {
      await _dataChannelMessageSubs[viewerId]?.cancel();
      await _dataChannelStateSubs[viewerId]?.cancel();
      _dataChannelMessageSubs.remove(viewerId);
      _dataChannelStateSubs.remove(viewerId);

      await _dataChannels[viewerId]?.close();
      _dataChannels.remove(viewerId);

      await _peerConnections[viewerId]?.close();
      _peerConnections.remove(viewerId);
    } catch (_) {}
    notifyListeners();
  }

  /// Stops streaming and notifies peers
  Future<void> stopStreaming({bool notify = true}) async {
    if (_currentFile == null) return;

    if (_isAnnounced && _signalingChannel != null) {
      try {
        await _signalingChannel!.sendBroadcastMessage(
          event: P2pConstants.eventOffline,
          payload: {
            'host_id': userId,
            'file_id': _currentFile!.id,
          },
        );
      } catch (_) {}
      _isAnnounced = false;
    }

    await _chunkReader?.close();
    _chunkReader = null;
    _currentFile = null;

    final viewerIds = _peerConnections.keys.toList();
    for (final vId in viewerIds) {
      await _closeViewerConnection(vId);
    }

    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    stopStreaming(notify: false);
    _candidateBuffer.clearAll();
    super.dispose();
  }
}
