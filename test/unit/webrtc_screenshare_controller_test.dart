import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/screenshare/controllers/webrtc_screenshare_controller.dart';

// Fake implementations for WebRTC classes
class FakeVideoTrack implements MediaStreamTrack {
  bool _enabled = true;
  bool isStopped = false;
  @override
  void Function()? onEnded;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool b) => _enabled = b;

  @override
  String get kind => 'video';

  @override
  Future<void> stop() async {
    isStopped = true;
    onEnded?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMediaStream implements MediaStream {
  final List<MediaStreamTrack> videoTracks;
  bool isDisposed = false;

  FakeMediaStream([List<MediaStreamTrack>? tracks])
      : videoTracks = tracks ?? [FakeVideoTrack()];

  @override
  List<MediaStreamTrack> getVideoTracks() => videoTracks;

  @override
  List<MediaStreamTrack> getTracks() => videoTracks;

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRTCPeerConnection implements RTCPeerConnection {
  RTCSessionDescription? localDesc;
  RTCSessionDescription? remoteDesc;
  final List<RTCIceCandidate> candidates = [];
  final List<MediaStreamTrack> addedTracks = [];
  bool isClosed = false;

  @override
  Function(RTCIceCandidate candidate)? onIceCandidate;

  @override
  Function(RTCTrackEvent event)? onTrack;

  @override
  Function(RTCPeerConnectionState state)? onConnectionState;

  @override
  Function(RTCIceConnectionState state)? onIceConnectionState;

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    localDesc = description;
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    remoteDesc = description;
  }

  @override
  Future<RTCSessionDescription?> getLocalDescription() async => localDesc;

  @override
  Future<RTCSessionDescription?> getRemoteDescription() async => remoteDesc;

  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async {
    return RTCSessionDescription('fake-screen-offer-sdp', 'offer');
  }

  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async {
    return RTCSessionDescription('fake-screen-answer-sdp', 'answer');
  }

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    candidates.add(candidate);
  }

  @override
  Future<RTCRtpSender> addTrack(MediaStreamTrack track, [MediaStream? stream]) async {
    addedTracks.add(track);
    return FakeRtpSender();
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  Future<void> dispose() async {
    isClosed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRtpSender implements RTCRtpSender {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRTCVideoRenderer implements RTCVideoRenderer {
  MediaStream? _srcObject;
  bool isInitialized = false;
  bool isDisposed = false;

  @override
  MediaStream? get srcObject => _srcObject;

  @override
  set srcObject(MediaStream? stream) => _srcObject = stream;

  @override
  Future<void> initialize() async {
    isInitialized = true;
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('WebRtcScreenShareController Unit Tests', () {
    late WebRtcScreenShareController controller;
    late UnifiedPlayerController playerController;
    late FakeMediaStream fakeScreenStream;
    late FakeRTCPeerConnection fakePeerConnection;

    setUp(() {
      WidgetsFlutterBinding.ensureInitialized();
      fakeScreenStream = FakeMediaStream([FakeVideoTrack()]);
      fakePeerConnection = FakeRTCPeerConnection();
      playerController = UnifiedPlayerController();

      controller = WebRtcScreenShareController(
        roomId: 'room-ss-101',
        userId: 'user-ss-1',
        userName: 'SharerUser',
        playerController: playerController,
        displayMediaFunction: (constraints) async => fakeScreenStream,
        peerConnectionFunction: (config, [constraints = const {}]) async =>
            fakePeerConnection,
        rendererFactory: () => FakeRTCVideoRenderer(),
        isHostProvider: () => false,
        isCollaborativeProvider: () => true,
      );
    });

    tearDown(() {
      controller.dispose();
      playerController.dispose();
    });

    test('initial state has no active screen share', () {
      expect(controller.isSharing, isFalse);
      expect(controller.isScreenSharingActive, isFalse);
      expect(controller.sharerId, isNull);
      expect(controller.sharerName, isNull);
      expect(controller.canShareScreen, isTrue);
      expect(controller.localStream, isNull);
      expect(controller.remoteStream, isNull);
    });

    test('permission check respects host only and collaborative rules', () {
      // In host-only room when user is NOT host: cannot share
      final hostOnlyNonHost = WebRtcScreenShareController(
        roomId: 'room-1',
        userId: 'user-guest',
        userName: 'Guest',
        isHostProvider: () => false,
        isCollaborativeProvider: () => false,
        rendererFactory: () => FakeRTCVideoRenderer(),
      );
      expect(hostOnlyNonHost.canShareScreen, isFalse);
      hostOnlyNonHost.dispose();

      // In host-only room when user IS host: can share
      final hostOnlyHost = WebRtcScreenShareController(
        roomId: 'room-1',
        userId: 'user-host',
        userName: 'Host',
        isHostProvider: () => true,
        isCollaborativeProvider: () => false,
        rendererFactory: () => FakeRTCVideoRenderer(),
      );
      expect(hostOnlyHost.canShareScreen, isTrue);
      hostOnlyHost.dispose();
    });

    test('startScreenShare captures stream and marks sharing state', () async {
      final success = await controller.startScreenShare();
      expect(success, isTrue);
      expect(controller.isSharing, isTrue);
      expect(controller.isScreenSharingActive, isTrue);
      expect(controller.sharerId, equals('user-ss-1'));
      expect(controller.sharerName, equals('SharerUser'));
      expect(controller.localStream, isNotNull);
      expect(controller.localRenderer.srcObject, equals(fakeScreenStream));
    });

    test('stopScreenShare cleans up local stream and resets state', () async {
      await controller.startScreenShare();
      expect(controller.isSharing, isTrue);

      await controller.stopScreenShare();
      expect(controller.isSharing, isFalse);
      expect(controller.isScreenSharingActive, isFalse);
      expect(controller.sharerId, isNull);
      expect(controller.localStream, isNull);
      expect(fakeScreenStream.isDisposed, isTrue);
    });

    test('handles incoming SCREEN_SHARE_STATE start and stop from peer', () async {
      await controller.handleScreenShareState({
        'action': 'start',
        'sharer_id': 'peer-ss-99',
        'sharer_name': 'RemotePresenter',
      });

      expect(controller.isSharing, isFalse);
      expect(controller.isScreenSharingActive, isTrue);
      expect(controller.sharerId, equals('peer-ss-99'));
      expect(controller.sharerName, equals('RemotePresenter'));

      // Peer stops sharing
      await controller.handleScreenShareState({
        'action': 'stop',
        'sharer_id': 'peer-ss-99',
      });

      expect(controller.isScreenSharingActive, isFalse);
      expect(controller.sharerId, isNull);
    });

    test('handles incoming SCREEN_OFFER and creates answer with video reception', () async {
      await controller.handleScreenOffer({
        'sender_id': 'peer-presenter',
        'target_id': 'user-ss-1',
        'sharer_name': 'Presenter',
        'sdp': {
          'type': 'offer',
          'sdp': 'v=0..fake-offer',
        },
      });

      expect(controller.sharerId, equals('peer-presenter'));
      expect(controller.sharerName, equals('Presenter'));
      expect(fakePeerConnection.remoteDesc, isNotNull);
      expect(fakePeerConnection.remoteDesc?.type, equals('offer'));
      expect(fakePeerConnection.localDesc, isNotNull);
      expect(fakePeerConnection.localDesc?.type, equals('answer'));
    });

    test('handles force_stop action when targeted at local sharer', () async {
      await controller.startScreenShare();
      expect(controller.isSharing, isTrue);

      await controller.handleScreenShareState({
        'action': 'force_stop',
        'target_id': 'user-ss-1',
        'sender_id': 'host-admin',
      });

      expect(controller.isSharing, isFalse);
      expect(controller.isScreenSharingActive, isFalse);
    });

    test('queued ICE candidates are flushed once remote description is set', () async {
      await controller.handleScreenIce({
        'sender_id': 'peer-remote',
        'target_id': 'user-ss-1',
        'candidate': {
          'candidate': 'candidate:1 1 UDP 2122260223 192.168.1.5 50000 typ host',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
      });

      // No remote description yet -> candidate queued
      expect(fakePeerConnection.candidates, isEmpty);

      // Now offer arrives and remote description is set
      await controller.handleScreenOffer({
        'sender_id': 'peer-remote',
        'target_id': 'user-ss-1',
        'sdp': {'type': 'offer', 'sdp': 'v=0..'},
      });

      // Flushed candidate into peer connection
      expect(fakePeerConnection.candidates.length, equals(1));
    });
  });
}
