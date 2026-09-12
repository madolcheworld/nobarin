import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:nobarin/core/constants/api_constants.dart';
import 'package:nobarin/core/network/webrtc_signaling_helper.dart';

class TestMediaStreamTrack implements MediaStreamTrack {
  bool isStopped = false;

  @override
  bool enabled = true;

  @override
  String get kind => 'audio';

  @override
  Future<void> stop() async {
    isStopped = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestMediaStream implements MediaStream {
  final List<MediaStreamTrack> tracks;
  bool isDisposed = false;

  TestMediaStream([List<MediaStreamTrack>? tracks])
      : tracks = tracks ?? [TestMediaStreamTrack()];

  @override
  List<MediaStreamTrack> getTracks() => tracks;

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestRTCPeerConnection implements RTCPeerConnection {
  final List<RTCIceCandidate> candidates = [];
  bool isClosed = false;
  bool isDisposed = false;
  bool throwOnClose = false;

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    candidates.add(candidate);
  }

  @override
  Future<void> close() async {
    if (throwOnClose) throw Exception('Simulated close failure');
    isClosed = true;
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('WebRtcSignalingHelper', () {
    test('defaultPeerConstraints contains DtlsSrtpKeyAgreement', () {
      expect(WebRtcSignalingHelper.defaultPeerConstraints['optional'], isNotEmpty);
      final list = WebRtcSignalingHelper.defaultPeerConstraints['optional'] as List;
      expect(list.first, equals({'DtlsSrtpKeyAgreement': true}));
    });

    test('defaultPeerConnectionConfig uses unified-plan and fallback iceServers', () {
      final config = WebRtcSignalingHelper.defaultPeerConnectionConfig();
      expect(config['sdpSemantics'], equals('unified-plan'));
      expect(config['iceServers'], equals(ApiConstants.rtcIceConfiguration['iceServers']));

      final custom = WebRtcSignalingHelper.defaultPeerConnectionConfig({
        'iceServers': [{'urls': 'stun:custom.stun.com:19302'}],
      });
      expect(custom['sdpSemantics'], equals('unified-plan'));
      expect(custom['iceServers'], equals([{'urls': 'stun:custom.stun.com:19302'}]));
    });

    test('extractPayload unwraps nested payload or returns raw map', () {
      final rawWithoutPayload = {'sender_id': 'u1', 'type': 'offer'};
      expect(WebRtcSignalingHelper.extractPayload(rawWithoutPayload), equals(rawWithoutPayload));

      final withNested = {
        'event': 'VOICE_OFFER',
        'payload': {'sender_id': 'u2', 'sdp': 'test_sdp'},
      };
      expect(WebRtcSignalingHelper.extractPayload(withNested), equals({
        'sender_id': 'u2',
        'sdp': 'test_sdp',
      }));

      final withGenericMap = {
        'payload': <dynamic, dynamic>{'sender_id': 'u3'},
      };
      expect(WebRtcSignalingHelper.extractPayload(withGenericMap), equals({
        'sender_id': 'u3',
      }));
    });

    test('buildIcePayload and parseIceCandidate roundtrip correctly', () {
      final candidate = RTCIceCandidate('candidate:12345', 'audio', 0);
      final payload = WebRtcSignalingHelper.buildIcePayload(
        senderId: 'alice',
        targetId: 'bob',
        candidate: candidate,
        extra: {'channel': 'voice'},
      );

      expect(payload['sender_id'], equals('alice'));
      expect(payload['target_id'], equals('bob'));
      expect(payload['channel'], equals('voice'));

      final parsed = WebRtcSignalingHelper.parseIceCandidate(payload['candidate']);
      expect(parsed, isNotNull);
      expect(parsed!.candidate, equals('candidate:12345'));
      expect(parsed.sdpMid, equals('audio'));
      expect(parsed.sdpMLineIndex, equals(0));
    });

    test('parseIceCandidate returns null for invalid inputs', () {
      expect(WebRtcSignalingHelper.parseIceCandidate(null), isNull);
      expect(WebRtcSignalingHelper.parseIceCandidate('string'), isNull);
      expect(WebRtcSignalingHelper.parseIceCandidate({}), isNull);
      expect(WebRtcSignalingHelper.parseIceCandidate({'candidate': ''}), isNull);
    });

    test('buildSdpPayload and parseSdp roundtrip correctly', () {
      final sdp = RTCSessionDescription('v=0\r\no=alice', 'offer');
      final payload = WebRtcSignalingHelper.buildSdpPayload(
        senderId: 'alice',
        targetId: 'bob',
        sdp: sdp,
        extra: {'voice_state': true},
      );

      expect(payload['sender_id'], equals('alice'));
      expect(payload['target_id'], equals('bob'));
      expect(payload['voice_state'], isTrue);

      final parsed = WebRtcSignalingHelper.parseSdp(payload['sdp']);
      expect(parsed, isNotNull);
      expect(parsed!.sdp, equals('v=0\r\no=alice'));
      expect(parsed.type, equals('offer'));
    });

    test('parseSdp returns null for null/non-map data and uses fallback defaults', () {
      expect(WebRtcSignalingHelper.parseSdp(null), isNull);
      expect(WebRtcSignalingHelper.parseSdp(123), isNull);

      final fallback = WebRtcSignalingHelper.parseSdp({});
      expect(fallback, isNotNull);
      expect(fallback!.sdp, isEmpty);
      expect(fallback.type, equals('offer'));
    });

    test('closeAndDisposePeers closes all connections and clears map safely', () async {
      final pc1 = TestRTCPeerConnection();
      final pc2 = TestRTCPeerConnection()..throwOnClose = true;
      final map = <String, RTCPeerConnection>{'p1': pc1, 'p2': pc2};

      await WebRtcSignalingHelper.closeAndDisposePeers(map, tag: 'Test');

      expect(pc1.isClosed, isTrue);
      expect(pc1.isDisposed, isTrue);
      expect(map, isEmpty);
    });

    test('disposeMediaStream stops tracks and disposes stream safely', () async {
      final track1 = TestMediaStreamTrack();
      final track2 = TestMediaStreamTrack();
      final stream = TestMediaStream([track1, track2]);

      await WebRtcSignalingHelper.disposeMediaStream(stream, tag: 'Test');

      expect(track1.isStopped, isTrue);
      expect(track2.isStopped, isTrue);
      expect(stream.isDisposed, isTrue);

      // Should not throw on null stream
      await WebRtcSignalingHelper.disposeMediaStream(null);
    });
  });

  group('IceCandidateBuffer', () {
    late IceCandidateBuffer buffer;

    setUp(() {
      buffer = IceCandidateBuffer();
    });

    test('enqueues and checks pending candidates', () {
      expect(buffer.hasPending('peer1'), isFalse);

      final cand1 = RTCIceCandidate('c1', 'mid0', 0);
      buffer.enqueue('peer1', cand1);

      expect(buffer.hasPending('peer1'), isTrue);
      expect(buffer.pendingCandidates['peer1']?.length, equals(1));
      expect(buffer.pendingCandidates['peer1']?.first.candidate, equals('c1'));
    });

    test('flushes queued candidates into peer connection and clears peer buffer', () async {
      final pc = TestRTCPeerConnection();
      final cand1 = RTCIceCandidate('c1', 'mid0', 0);
      final cand2 = RTCIceCandidate('c2', 'mid1', 1);

      buffer.enqueue('peer1', cand1);
      buffer.enqueue('peer1', cand2);
      buffer.enqueue('peer2', RTCIceCandidate('c3', 'mid0', 0));

      await buffer.flush('peer1', pc);

      expect(pc.candidates.length, equals(2));
      expect(pc.candidates[0].candidate, equals('c1'));
      expect(pc.candidates[1].candidate, equals('c2'));

      expect(buffer.hasPending('peer1'), isFalse);
      expect(buffer.hasPending('peer2'), isTrue);
    });

    test('clear resets single peer or all peers', () {
      buffer.enqueue('p1', RTCIceCandidate('c1', 'm0', 0));
      buffer.enqueue('p2', RTCIceCandidate('c2', 'm0', 0));

      buffer.clear('p1');
      expect(buffer.hasPending('p1'), isFalse);
      expect(buffer.hasPending('p2'), isTrue);

      buffer.clear();
      expect(buffer.hasPending('p2'), isFalse);
      expect(buffer.pendingCandidates, isEmpty);
    });
  });
}
