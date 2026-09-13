import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../constants/api_constants.dart';

/// Helper and abstraction utility for WebRTC signaling, ICE candidate queuing,
/// SDP serialization, and peer connection lifecycle management.
class WebRtcSignalingHelper {
  const WebRtcSignalingHelper._();

  /// Default peer connection constraints supporting DTLS SRTP key agreement
  static const Map<String, dynamic> defaultPeerConstraints = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  /// Constructs the default peer connection configuration using Unified Plan semantics
  /// merged with [customIceConfig] or [ApiConstants.rtcIceConfiguration].
  static Map<String, dynamic> defaultPeerConnectionConfig([
    Map<String, dynamic>? customIceConfig,
  ]) {
    return <String, dynamic>{
      ...customIceConfig ?? ApiConstants.rtcIceConfiguration,
      'sdpSemantics': 'unified-plan',
    };
  }

  /// Extracts the nested payload from a Supabase Realtime broadcast message map.
  static Map<String, dynamic> extractPayload(Map<String, dynamic> raw) {
    if (raw['payload'] is Map<String, dynamic>) {
      return raw['payload'] as Map<String, dynamic>;
    } else if (raw['payload'] is Map) {
      return Map<String, dynamic>.from(raw['payload'] as Map);
    }
    return raw;
  }

  /// Formats an ICE candidate payload for signaling broadcasts.
  static Map<String, dynamic> buildIcePayload({
    required String senderId,
    required String targetId,
    required RTCIceCandidate candidate,
    Map<String, dynamic>? extra,
  }) {
    return {
      'sender_id': senderId,
      'target_id': targetId,
      'candidate': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
      ...?extra,
    };
  }

  /// Safely parses an [RTCIceCandidate] from a candidate map.
  static RTCIceCandidate? parseIceCandidate(dynamic candidateData) {
    if (candidateData == null) return null;
    if (candidateData is! Map) return null;

    final candMap = candidateData is Map<String, dynamic>
        ? candidateData
        : Map<String, dynamic>.from(candidateData);

    final candStr = candMap['candidate'] as String?;
    if (candStr == null || candStr.isEmpty) return null;

    final sdpMid = candMap['sdpMid'] as String?;
    final sdpMLineIndex = candMap['sdpMLineIndex'] as int?;

    return RTCIceCandidate(candStr, sdpMid, sdpMLineIndex);
  }

  /// Formats an SDP session description payload (Offer / Answer) for signaling broadcasts.
  static Map<String, dynamic> buildSdpPayload({
    required String senderId,
    String? targetId,
    required RTCSessionDescription sdp,
    Map<String, dynamic>? extra,
  }) {
    return {
      'sender_id': senderId,
      'target_id': ?targetId,
      'sdp': {
        'type': sdp.type,
        'sdp': sdp.sdp,
      },
      ...?extra,
    };
  }

  /// Safely parses an [RTCSessionDescription] from an SDP map.
  static RTCSessionDescription? parseSdp(dynamic sdpData) {
    if (sdpData == null) return null;
    if (sdpData is! Map) return null;

    final sdpMap = sdpData is Map<String, dynamic>
        ? sdpData
        : Map<String, dynamic>.from(sdpData);

    final sdp = sdpMap['sdp'] as String? ?? '';
    final type = sdpMap['type'] as String? ?? 'offer';

    return RTCSessionDescription(sdp, type);
  }

  /// Iterates and safely closes and disposes all peer connections in [peerConnections].
  static Future<void> closeAndDisposePeers(
    Map<String, RTCPeerConnection> peerConnections, {
    String tag = 'WebRTC',
  }) async {
    for (final entry in peerConnections.entries) {
      try {
        await entry.value.close();
        await entry.value.dispose();
      } catch (e) {
        debugPrint('[$tag] Note closing peer ${entry.key}: $e');
      }
    }
    peerConnections.clear();
  }

  /// Safely stops all tracks and disposes the given [MediaStream].
  static Future<void> disposeMediaStream(
    MediaStream? stream, {
    String tag = 'WebRTC',
  }) async {
    if (stream == null) return;
    try {
      for (final track in stream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      await stream.dispose();
    } catch (e) {
      debugPrint('[$tag] Note disposing stream: $e');
    }
  }
}

/// Buffer manager for queuing and flushing ICE candidates before remote description is set.
class IceCandidateBuffer {
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};

  /// Retrieves an unmodifiable view of pending candidates for testing/inspection.
  Map<String, List<RTCIceCandidate>> get pendingCandidates =>
      Map.unmodifiable(_pendingCandidates);

  /// Checks if there are pending candidates for [peerId].
  bool hasPending(String peerId) =>
      _pendingCandidates.containsKey(peerId) &&
      _pendingCandidates[peerId]!.isNotEmpty;

  /// Enqueues an [RTCIceCandidate] for the given [peerId].
  void enqueue(String peerId, RTCIceCandidate candidate) {
    _pendingCandidates.putIfAbsent(peerId, () => []).add(candidate);
  }

  /// Alias for [enqueue].
  void add(String peerId, RTCIceCandidate candidate) => enqueue(peerId, candidate);

  /// Flushes all queued candidates for [peerId] into the provided [pc].
  Future<void> flush(
    String peerId,
    RTCPeerConnection pc, {
    String tag = 'WebRTC',
  }) async {
    final candidates = _pendingCandidates.remove(peerId);
    if (candidates != null && candidates.isNotEmpty) {
      for (final candidate in candidates) {
        try {
          await pc.addCandidate(candidate);
        } catch (e) {
          debugPrint('[$tag] Error adding queued ICE candidate for $peerId: $e');
        }
      }
    }
  }

  /// Alias for [flush].
  Future<void> drain(String peerId, RTCPeerConnection pc) => flush(peerId, pc);

  /// Clears candidates for a specific [peerId] or all peers if [peerId] is null.
  void clear([String? peerId]) {
    if (peerId != null) {
      _pendingCandidates.remove(peerId);
    } else {
      _pendingCandidates.clear();
    }
  }

  /// Alias for [clear] clearing all peers.
  void clearAll() => clear();
}
