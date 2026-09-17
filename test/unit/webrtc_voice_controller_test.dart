import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/voice/controllers/webrtc_voice_controller.dart';
import 'package:nobarin/features/voice/presentation/speaking_avatar_indicator.dart';
import 'package:nobarin/features/voice/presentation/voice_control_bar.dart';

// Fake implementations for WebRTC classes in unit tests
class FakeMediaStreamTrack implements MediaStreamTrack {
  bool _enabled = true;
  bool isStopped = false;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool b) => _enabled = b;

  @override
  String get kind => 'audio';

  @override
  Future<void> stop() async {
    isStopped = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMediaStream implements MediaStream {
  final List<MediaStreamTrack> audioTracks;
  bool isDisposed = false;

  FakeMediaStream([List<MediaStreamTrack>? tracks])
      : audioTracks = tracks ?? [FakeMediaStreamTrack()];

  @override
  List<MediaStreamTrack> getAudioTracks() => audioTracks;

  @override
  List<MediaStreamTrack> getTracks() => audioTracks;

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRTCTrackEvent implements RTCTrackEvent {
  @override
  final MediaStreamTrack track;
  @override
  final List<MediaStream> streams;

  FakeRTCTrackEvent({required this.track, this.streams = const []});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRTCPeerConnection implements RTCPeerConnection {
  RTCSessionDescription? localDesc;
  RTCSessionDescription? remoteDesc;
  final List<RTCIceCandidate> candidates = [];
  final List<MediaStreamTrack> addedTracks = [];
  final List<FakeRtpSender> fakeSenders = [];
  List<StatsReport> statsReports = [];
  @override
  RTCSignalingState signalingState = RTCSignalingState.RTCSignalingStateStable;
  bool isClosed = false;

  @override
  Function(RTCIceCandidate candidate)? onIceCandidate;

  @override
  Function(RTCTrackEvent event)? onTrack;

  @override
  Function(RTCPeerConnectionState state)? onConnectionState;

  @override
  Future<RTCSignalingState> getSignalingState() async => signalingState;

  @override
  Future<List<RTCRtpSender>> getSenders() async => fakeSenders;

  @override
  Future<List<RTCRtpSender>> get senders async => fakeSenders;

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
    return RTCSessionDescription('fake-offer-sdp', 'offer');
  }

  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async {
    return RTCSessionDescription('fake-answer-sdp', 'answer');
  }

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    candidates.add(candidate);
  }

  @override
  Future<RTCRtpSender> addTrack(
    MediaStreamTrack track, [
    MediaStream? stream,
  ]) async {
    addedTracks.add(track);
    final sender = FakeRtpSender(track);
    fakeSenders.add(sender);
    return sender;
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
  Future<List<StatsReport>> getStats([MediaStreamTrack? track]) async =>
      statsReports;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRtpSender implements RTCRtpSender {
  MediaStreamTrack? _track;
  FakeRtpSender([this._track]);

  @override
  MediaStreamTrack? get track => _track;

  @override
  Future<void> replaceTrack(MediaStreamTrack? track) async {
    _track = track;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePlayerController implements UnifiedPlayerController {
  double _volume = 1.0;

  @override
  double get volume => _volume;

  @override
  Future<void> setVolume(double vol) async {
    _volume = vol;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRealtimeChannel implements RealtimeChannel {
  final List<Map<String, dynamic>> broadcastMessages = [];
  final Map<String, void Function(Map<String, dynamic>)> callbacks = {};
  bool unsubscribed = false;

  @override
  RealtimeChannel onBroadcast({
    required String event,
    required void Function(Map<String, dynamic> payload) callback,
  }) {
    callbacks[event] = callback;
    return this;
  }

  @override
  RealtimeChannel subscribe([
    void Function(RealtimeSubscribeStatus status, Object? error)? callback,
    Duration? timeout,
  ]) {
    callback?.call(RealtimeSubscribeStatus.subscribed, null);
    return this;
  }

  @override
  Future<ChannelResponse> sendBroadcastMessage({
    required String event,
    required Map<String, dynamic> payload,
  }) async {
    broadcastMessages.add({'event': event, 'payload': payload});
    return ChannelResponse.ok;
  }

  @override
  Future<String> unsubscribe([Duration? timeout]) async {
    unsubscribed = true;
    return 'ok';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSupabaseClient implements SupabaseClient {
  final FakeRealtimeChannel channelInstance = FakeRealtimeChannel();

  @override
  RealtimeChannel channel(String topic,
      {RealtimeChannelConfig opts = const RealtimeChannelConfig()}) {
    return channelInstance;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('WebRtcVoiceController Unit Tests', () {
    late WebRtcVoiceController controller;
    late FakePlayerController fakePlayer;
    late FakeMediaStream fakeStream;
    late FakeRTCPeerConnection fakePeerConnection;

    setUp(() {
      fakePlayer = FakePlayerController();
      fakeStream = FakeMediaStream();
      fakePeerConnection = FakeRTCPeerConnection();

      controller = WebRtcVoiceController(
        roomId: 'test-room-101',
        userId: 'user-alice',
        userName: 'Alice',
        playerController: fakePlayer,
        supabase: null, // Offline / unconfigured mode
        autoCaptureMic: true,
        userMediaFunction: (_) async => fakeStream,
        peerConnectionFunction: (config, [constraints = const {}]) async =>
            fakePeerConnection,
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('Initial state values are correct', () {
      expect(controller.status, VoiceStatus.disconnected);
      expect(controller.isMicMuted, isTrue);
      expect(controller.isDeafened, isFalse);
      expect(controller.isConnected, isFalse);
      expect(controller.isAudioDuckingEnabled, isTrue);
      expect(controller.isLocalSpeaking, isFalse);
      expect(controller.isDucking, isFalse);
      expect(controller.activeSpeakerIds, isEmpty);
      expect(controller.peerConnections, isEmpty);
    });

    test('connect() sets status to unconfigured in offline mode and mutes stream',
        () async {
      await controller.connect();

      expect(controller.status, VoiceStatus.unconfigured);
      expect(controller.localStream, isNotNull);
      // Mic is muted by default, so track should be disabled
      expect(fakeStream.audioTracks.first.enabled, isFalse);
    });

    test('toggleMic() and setMicMuted() update mute state and track correctly',
        () async {
      await controller.connect();
      expect(controller.isMicMuted, isTrue);
      expect(fakeStream.audioTracks.first.enabled, isFalse);

      // Unmute
      await controller.toggleMic();
      expect(controller.isMicMuted, isFalse);
      expect(fakeStream.audioTracks.first.enabled, isTrue);

      // Mute again
      await controller.toggleMic();
      expect(controller.isMicMuted, isTrue);
      expect(fakeStream.audioTracks.first.enabled, isFalse);

      // setMicMuted explicit
      await controller.setMicMuted(false);
      expect(controller.isMicMuted, isFalse);
      expect(fakeStream.audioTracks.first.enabled, isTrue);

      await controller.setMicMuted(true);
      expect(controller.isMicMuted, isTrue);
      expect(fakeStream.audioTracks.first.enabled, isFalse);
    });

    test('setLocalSpeaking(true) works only when unmuted', () async {
      await controller.connect();

      // Muted: should NOT be able to speak
      controller.setLocalSpeaking(true);
      expect(controller.isLocalSpeaking, isFalse);
      expect(controller.activeSpeakerIds.contains('user-alice'), isFalse);

      // Unmute: now can speak
      await controller.toggleMic();
      controller.setLocalSpeaking(true);
      expect(controller.isLocalSpeaking, isTrue);
      expect(controller.activeSpeakerIds.contains('user-alice'), isTrue);

      // Stop speaking
      controller.setLocalSpeaking(false);
      expect(controller.isLocalSpeaking, isFalse);
      expect(controller.activeSpeakerIds.contains('user-alice'), isFalse);
    });

    test('Muting mic clears local speaking state immediately', () async {
      await controller.connect();
      await controller.toggleMic(); // Unmute
      controller.setLocalSpeaking(true);
      expect(controller.isLocalSpeaking, isTrue);

      await controller.toggleMic(); // Mute
      expect(controller.isMicMuted, isTrue);
      expect(controller.isLocalSpeaking, isFalse);
      expect(controller.activeSpeakerIds.contains('user-alice'), isFalse);
    });

    test('Audio ducking activates when remote participant talks and restores on silence',
        () async {
      await controller.connect();
      expect(fakePlayer.volume, 1.0);

      // Local speaking alone does NOT trigger ducking
      await controller.toggleMic();
      controller.setLocalSpeaking(true);
      expect(controller.isDucking, isFalse);
      expect(fakePlayer.volume, 1.0);

      // Remote participant Bob starts speaking
      controller.setRemoteSpeaking('user-bob', true);
      expect(controller.isDucking, isTrue);
      expect(fakePlayer.volume, closeTo(0.4, 0.01)); // Ducked to 40%

      // Another participant Charlie also starts speaking
      controller.setRemoteSpeaking('user-charlie', true);
      expect(controller.isDucking, isTrue);
      expect(fakePlayer.volume, closeTo(0.4, 0.01));

      // Bob stops, Charlie is still speaking -> remains ducked
      controller.setRemoteSpeaking('user-bob', false);
      expect(controller.isDucking, isTrue);
      expect(fakePlayer.volume, closeTo(0.4, 0.01));

      // Charlie stops -> volume restored
      controller.setRemoteSpeaking('user-charlie', false);
      expect(controller.isDucking, isFalse);
      expect(fakePlayer.volume, closeTo(1.0, 0.01));
    });

    test('Disabling audio ducking restores volume immediately', () async {
      await controller.connect();
      controller.setRemoteSpeaking('user-bob', true);
      expect(controller.isDucking, isTrue);
      expect(fakePlayer.volume, closeTo(0.4, 0.01));

      // Disable ducking
      controller.toggleAudioDucking();
      expect(controller.isAudioDuckingEnabled, isFalse);
      expect(controller.isDucking, isFalse);
      expect(fakePlayer.volume, closeTo(1.0, 0.01));
    });

    test('toggleDeafen() mutes incoming streams and restores volume if ducked',
        () async {
      await controller.connect();
      controller.setRemoteSpeaking('user-bob', true);
      expect(controller.isDucking, isTrue);
      expect(fakePlayer.volume, closeTo(0.4, 0.01));

      // Deafen
      controller.toggleDeafen();
      expect(controller.isDeafened, isTrue);
      // Remote speakers removed from ducking calculation
      expect(controller.isDucking, isFalse);
      expect(fakePlayer.volume, closeTo(1.0, 0.01));

      // Undeafen
      controller.toggleDeafen();
      expect(controller.isDeafened, isFalse);
    });

    test('Signaling: handleVoiceState handles update, speaking, and leave events',
        () async {
      await controller.connect();

      // Self message is ignored
      await controller.handleVoiceState({
        'sender_id': 'user-alice',
        'is_speaking': true,
        'is_muted': false,
      });
      expect(controller.activeSpeakerIds.contains('user-alice'), isFalse);

      // Remote update: Bob is speaking
      await controller.handleVoiceState({
        'sender_id': 'user-bob',
        'user_name': 'Bob',
        'is_speaking': true,
        'is_muted': false,
        'action': 'update',
      });
      expect(controller.activeSpeakerIds.contains('user-bob'), isTrue);
      expect(controller.isDucking, isTrue);

      // Remote update: Bob stops speaking
      await controller.handleVoiceState({
        'sender_id': 'user-bob',
        'user_name': 'Bob',
        'is_speaking': false,
        'is_muted': false,
        'action': 'update',
      });
      expect(controller.activeSpeakerIds.contains('user-bob'), isFalse);
      expect(controller.isDucking, isFalse);

      // Bob speaks again, then leaves
      await controller.handleVoiceState({
        'sender_id': 'user-bob',
        'is_speaking': true,
        'is_muted': false,
        'action': 'update',
      });
      expect(controller.activeSpeakerIds.contains('user-bob'), isTrue);

      await controller.handleVoiceState({
        'sender_id': 'user-bob',
        'action': 'leave',
      });
      expect(controller.activeSpeakerIds.contains('user-bob'), isFalse);
      expect(controller.isDucking, isFalse);
    });

    test('Signaling: handleVoiceOffer creates answer and sets descriptions',
        () async {
      await controller.connect();

      // Message for someone else should be ignored
      await controller.handleVoiceOffer({
        'sender_id': 'user-bob',
        'target_id': 'user-someone-else',
        'sdp': {'type': 'offer', 'sdp': 'v=0...'},
      });
      expect(fakePeerConnection.remoteDesc, isNull);

      // Message for Alice
      await controller.handleVoiceOffer({
        'sender_id': 'user-bob',
        'target_id': 'user-alice',
        'sdp': {'type': 'offer', 'sdp': 'v=0 offer sdp'},
      });

      expect(fakePeerConnection.remoteDesc?.sdp, 'v=0 offer sdp');
      expect(fakePeerConnection.localDesc?.sdp, 'fake-answer-sdp');
    });

    test('Signaling: handleVoiceAnswer sets remote description', () async {
      await controller.connect();

      // First simulate an existing peer connection for Bob
      await controller.handleVoiceOffer({
        'sender_id': 'user-bob',
        'target_id': 'user-alice',
        'sdp': {'type': 'offer', 'sdp': 'v=0 initial'},
      });

      // Now receive answer for Bob
      await controller.handleVoiceAnswer({
        'sender_id': 'user-bob',
        'target_id': 'user-alice',
        'sdp': {'type': 'answer', 'sdp': 'v=0 answer sdp'},
      });

      expect(fakePeerConnection.remoteDesc?.sdp, 'v=0 answer sdp');
    });

    test('Signaling: handleVoiceIce queues and flushes ICE candidates',
        () async {
      await controller.connect();

      // Send ICE before offer/remoteDesc is set -> queued
      await controller.handleVoiceIce({
        'sender_id': 'user-bob',
        'target_id': 'user-alice',
        'candidate': {
          'candidate': 'candidate:1 1 UDP 2130706431 192.168.1.1 5000 typ host',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
      });

      // Not yet added because remoteDesc was null
      expect(fakePeerConnection.candidates, isEmpty);

      // Now offer arrives -> flushes pending candidate!
      await controller.handleVoiceOffer({
        'sender_id': 'user-bob',
        'target_id': 'user-alice',
        'sdp': {'type': 'offer', 'sdp': 'v=0 offer'},
      });

      expect(fakePeerConnection.candidates.length, 1);
      expect(fakePeerConnection.candidates.first.candidate,
          contains('candidate:1 1 UDP'));
    });

    test('disconnect() and dispose() clean up state and restore video volume',
        () async {
      await controller.connect();
      // Establish peer connection for Bob
      await controller.handleVoiceOffer({
        'sender_id': 'user-bob',
        'target_id': 'user-alice',
        'sdp': {'type': 'offer', 'sdp': 'v=0 offer'},
      });

      controller.setRemoteSpeaking('user-bob', true);
      expect(controller.isDucking, isTrue);
      expect(controller.peerConnections.containsKey('user-bob'), isTrue);

      await controller.disconnect();
      expect(controller.status, VoiceStatus.disconnected);
      expect(controller.activeSpeakerIds, isEmpty);
      expect(controller.peerConnections, isEmpty);
      expect(controller.isDucking, isFalse);
      expect(fakePlayer.volume, closeTo(1.0, 0.01));
      expect(fakePeerConnection.isClosed, isTrue);
    });

    test(
        'mutedUserIds tracks local and remote mute states across join, announce, update, and leave',
        () async {
      await controller.connect();
      expect(controller.mutedUserIds.contains('user-alice'), isTrue);

      // Unmute Alice
      await controller.toggleMic();
      expect(controller.mutedUserIds.contains('user-alice'), isFalse);

      // Peer Bob joins muted
      await controller.handleVoiceState({
        'sender_id': 'user-bob',
        'user_name': 'Bob',
        'is_muted': true,
        'action': 'join',
      });
      expect(controller.mutedUserIds.contains('user-bob'), isTrue);

      // Peer Charlie announces unmuted
      await controller.handleVoiceState({
        'sender_id': 'user-charlie',
        'user_name': 'Charlie',
        'is_muted': false,
        'action': 'announce',
      });
      expect(controller.mutedUserIds.contains('user-charlie'), isFalse);

      // Bob updates to unmuted
      await controller.handleVoiceState({
        'sender_id': 'user-bob',
        'user_name': 'Bob',
        'is_muted': false,
        'action': 'update',
      });
      expect(controller.mutedUserIds.contains('user-bob'), isFalse);

      // Bob leaves
      await controller.handleVoiceState({
        'sender_id': 'user-bob',
        'action': 'leave',
      });
      expect(controller.mutedUserIds.contains('user-bob'), isFalse);
    });

    test('VAD: Inbound audio stats detection and drop-off restoration',
        () async {
      final fakeSupabase = FakeSupabaseClient();
      final vadController = WebRtcVoiceController(
        roomId: 'test-room-vad',
        userId: 'user-alice',
        userName: 'Alice',
        playerController: fakePlayer,
        supabase: fakeSupabase,
        userMediaFunction: (_) async => fakeStream,
        peerConnectionFunction: (config, [constraints = const {}]) async =>
            fakePeerConnection,
      );

      await vadController.connect();
      // Establish peer connection for Bob
      await vadController.handleVoiceOffer({
        'sender_id': 'user-bob',
        'target_id': 'user-alice',
        'sdp': {'type': 'offer', 'sdp': 'v=0 offer'},
      });

      // 1. Remote peer Bob talks (audioLevel 0.15)
      fakePeerConnection.statsReports = [
        StatsReport('1', 'inbound-rtp', 1.0, {'audioLevel': '0.15'}),
      ];

      // Wait for VAD timer tick (runs every 300ms)
      await Future.delayed(const Duration(milliseconds: 350));
      expect(vadController.activeSpeakerIds.contains('user-bob'), isTrue);
      expect(vadController.isDucking, isTrue);
      expect(fakePlayer.volume, closeTo(0.4, 0.01));

      // 2. Remote peer Bob stops talking (audioLevel drops to 0.005)
      fakePeerConnection.statsReports = [
        StatsReport('1', 'inbound-rtp', 2.0, {'audioLevel': '0.005'}),
      ];

      await Future.delayed(const Duration(milliseconds: 350));
      // Verify remote peer is removed from activeSpeakerIds and ducking is restored!
      expect(vadController.activeSpeakerIds.contains('user-bob'), isFalse);
      expect(vadController.isDucking, isFalse);
      expect(fakePlayer.volume, closeTo(1.0, 0.01));

      vadController.dispose();
    });

    test(
        'Concurrent _getOrCreatePeerConnection calls return identical instance without duplicate creation',
        () async {
      await controller.connect();

      // Launch multiple simultaneous calls for user-bob
      final f1 = controller.handleVoiceOffer({
        'sender_id': 'user-bob',
        'target_id': 'user-alice',
        'sdp': {'type': 'offer', 'sdp': 'v=0 offer'},
      });
      final f2 = controller.handleVoiceIce({
        'sender_id': 'user-bob',
        'target_id': 'user-alice',
        'candidate': {
          'candidate':
              'candidate:1 1 UDP 2130706431 192.168.1.1 5000 typ host',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
      });

      await Future.wait([f1, f2]);
      expect(controller.peerConnections.length, 1);
      expect(controller.peerConnections['user-bob'], isNotNull);
    });

    test(
        'toggleMic() lazily acquires stream and attaches tracks to existing peer connections if initial mic acquisition failed',
        () async {
      bool failInitialMic = true;
      final lazyController = WebRtcVoiceController(
        roomId: 'test-lazy',
        userId: 'user-lazy',
        userName: 'Lazy User',
        supabase: null,
        userMediaFunction: (_) async {
          if (failInitialMic) {
            throw Exception('Permission denied initially');
          }
          return fakeStream;
        },
        peerConnectionFunction: (config, [constraints = const {}]) async =>
            fakePeerConnection,
      );

      await lazyController.connect();
      expect(lazyController.localStream, isNull);

      // Now establish peer connection with remote Bob while localStream is null
      await lazyController.handleVoiceOffer({
        'sender_id': 'user-bob',
        'target_id': 'user-lazy',
        'sdp': {'type': 'offer', 'sdp': 'v=0 offer'},
      });
      expect(fakePeerConnection.addedTracks, isEmpty);

      // Now user taps "Buka Mic" - mic permission now works
      failInitialMic = false;
      await lazyController.toggleMic();

      expect(lazyController.isMicMuted, isFalse);
      expect(lazyController.localStream, isNotNull);
      expect(fakePeerConnection.addedTracks.length, 1);

      lazyController.dispose();
    });

    test(
        'autoCaptureMic: false does not capture hardware mic on connect, acquires lazily on toggleMic',
        () async {
      int mediaCaptureCallCount = 0;
      final safeController = WebRtcVoiceController(
        roomId: 'room-safe',
        userId: 'user-safe',
        userName: 'UserSafe',
        autoCaptureMic: false,
        userMediaFunction: (_) async {
          mediaCaptureCallCount++;
          return fakeStream;
        },
        peerConnectionFunction: (config, [constraints = const {}]) async =>
            fakePeerConnection,
      );

      // Connect: hardware mic must NOT be acquired!
      await safeController.connect();
      expect(mediaCaptureCallCount, 0);
      expect(safeController.localStream, isNull);
      expect(safeController.isMicMuted, isTrue);

      // Unmute explicitly: hardware mic is now acquired and enabled
      await safeController.toggleMic();
      expect(mediaCaptureCallCount, 1);
      expect(safeController.localStream, isNotNull);
      expect(safeController.isMicMuted, isFalse);
      expect(fakeStream.audioTracks.first.enabled, isTrue);

      // Mute again: track is disabled
      await safeController.toggleMic();
      expect(safeController.isMicMuted, isTrue);
      expect(fakeStream.audioTracks.first.enabled, isFalse);

      safeController.dispose();
    });

    test(
        'toggleAudioDucking() immediately ducks volume if re-enabled while participant is speaking',
        () async {
      await controller.connect();
      controller.setRemoteSpeaking('user-bob', true);
      expect(controller.isDucking, isTrue);
      expect(fakePlayer.volume, closeTo(0.4, 0.01));

      // Disable ducking -> volume restored
      controller.toggleAudioDucking();
      expect(controller.isAudioDuckingEnabled, isFalse);
      expect(controller.isDucking, isFalse);
      expect(fakePlayer.volume, closeTo(1.0, 0.01));

      // Re-enable ducking while Bob is still speaking -> ducks immediately!
      controller.toggleAudioDucking();
      expect(controller.isAudioDuckingEnabled, isTrue);
      expect(controller.isDucking, isTrue);
      expect(fakePlayer.volume, closeTo(0.4, 0.01));
    });

    test('toggleDeafen() mutes audio tracks even when event.streams is empty',
        () async {
      await controller.connect();
      await controller.handleVoiceOffer({
        'sender_id': 'user-bob',
        'target_id': 'user-alice',
        'sdp': {'type': 'offer', 'sdp': 'v=0 offer'},
      });

      final remoteTrack = FakeMediaStreamTrack();
      // Simulate onTrack fired with empty streams (standard Unified Plan)
      fakePeerConnection.onTrack?.call(FakeRTCTrackEvent(
        track: remoteTrack,
        streams: [],
      ));

      expect(remoteTrack.enabled, isTrue);

      // Deafen
      controller.toggleDeafen();
      expect(controller.isDeafened, isTrue);
      expect(remoteTrack.enabled, isFalse);

      // Undeafen
      controller.toggleDeafen();
      expect(controller.isDeafened, isFalse);
      expect(remoteTrack.enabled, isTrue);
    });

    test(
        'disconnect() stops local audio tracks, disposes local stream, and cleans up channel',
        () async {
      final fakeSupabase = FakeSupabaseClient();
      final dController = WebRtcVoiceController(
        roomId: 'test-disc',
        userId: 'user-alice',
        userName: 'Alice',
        supabase: fakeSupabase,
        autoCaptureMic: true,
        userMediaFunction: (_) async => fakeStream,
        peerConnectionFunction: (config, [constraints = const {}]) async =>
            fakePeerConnection,
      );

      await dController.connect();
      expect(dController.localStream, isNotNull);

      await dController.disconnect();
      expect((fakeStream.audioTracks.first as FakeMediaStreamTrack).isStopped,
          isTrue);
      expect(fakeStream.isDisposed, isTrue);
      expect(dController.localStream, isNull);
      expect(fakeSupabase.channelInstance.unsubscribed, isTrue);

      dController.dispose();
    });

    test(
        'default WebRtcVoiceController constructor has autoCaptureMic false and disconnect cleanly without stream',
        () async {
      int mediaCalls = 0;
      final defaultController = WebRtcVoiceController(
        roomId: 'test-default-safe',
        userId: 'user-bob',
        userName: 'Bob',
        supabase: null,
        userMediaFunction: (_) async {
          mediaCalls++;
          return fakeStream;
        },
        peerConnectionFunction: (config, [constraints = const {}]) async =>
            fakePeerConnection,
      );

      expect(defaultController.autoCaptureMic, isFalse);

      await defaultController.connect();
      expect(mediaCalls, 0);
      expect(defaultController.localStream, isNull);
      expect(defaultController.isMicMuted, isTrue);

      // Disconnect without ever unmuting
      await defaultController.disconnect();
      expect(defaultController.localStream, isNull);
      expect(mediaCalls, 0);

      defaultController.dispose();
    });

    test('dispose() broadcasts leave message before cleaning up', () async {
      final fakeSupabase = FakeSupabaseClient();
      final dispController = WebRtcVoiceController(
        roomId: 'test-disp',
        userId: 'user-alice',
        userName: 'Alice',
        supabase: fakeSupabase,
        userMediaFunction: (_) async => fakeStream,
        peerConnectionFunction: (config, [constraints = const {}]) async =>
            fakePeerConnection,
      );

      await dispController.connect();
      dispController.dispose();

      final leaveMessages = fakeSupabase.channelInstance.broadcastMessages
          .where((m) =>
              m['event'] == 'VOICE_STATE' &&
              m['payload']['action'] == 'leave' &&
              m['payload']['sender_id'] == 'user-alice')
          .toList();

      expect(leaveMessages.length, 1);
    });
  });

  group('SpeakingAvatarIndicator Widget Tests', () {
    testWidgets('renders avatar and name correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpeakingAvatarIndicator(
              avatar: '🦊',
              name: 'FoxUser',
              isSpeaking: false,
            ),
          ),
        ),
      );

      expect(find.text('🦊'), findsOneWidget);
      expect(find.text('FoxUser'), findsOneWidget);
      expect(find.text('👑'), findsNothing);
    });

    testWidgets(
        'hides name when showName is false and shows crown when isHost is true',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpeakingAvatarIndicator(
              avatar: '🦊',
              name: 'FoxUser',
              isSpeaking: true,
              isHost: true,
              showName: false,
            ),
          ),
        ),
      );

      expect(find.text('🦊'), findsOneWidget);
      expect(find.text('FoxUser'), findsNothing);
      expect(find.text('👑'), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    });

    testWidgets('shows mute icon when isMuted is true and not speaking',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpeakingAvatarIndicator(
              avatar: '🐼',
              name: 'Panda',
              isSpeaking: false,
              isMuted: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);
    });
  });


  group('VoiceControlBar Widget Tests', () {
    late WebRtcVoiceController controller;
    late FakePlayerController fakePlayer;
    late FakeMediaStream fakeStream;
    late FakeRTCPeerConnection fakePeerConnection;

    setUp(() {
      fakePlayer = FakePlayerController();
      fakeStream = FakeMediaStream();
      fakePeerConnection = FakeRTCPeerConnection();

      controller = WebRtcVoiceController(
        roomId: 'test-room-ui',
        userId: 'user-ui',
        userName: 'UI User',
        playerController: fakePlayer,
        supabase: null,
        audioRouteHandler: (_) async {},
        userMediaFunction: (_) async => fakeStream,
        peerConnectionFunction: (config, [constraints = const {}]) async =>
            fakePeerConnection,
      );
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('renders controls and interacts with mic, deafen, and ducking',
        (tester) async {
      await controller.connect();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceControlBar(voiceController: controller),
          ),
        ),
      );

      // Initially mic is off
      expect(find.text('Voice Siap'), findsOneWidget);
      expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);

      // Tap mic toggle to turn on
      await tester.tap(find.byIcon(Icons.mic_off_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(controller.isMicMuted, isFalse);
      expect(find.text('Voice Aktif'), findsOneWidget);

      // Tap deafen button
      expect(controller.isDeafened, isFalse);
      await tester.tap(find.byIcon(Icons.headset_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.isDeafened, isTrue);

      // Tap ducking toggle button
      expect(controller.isAudioDuckingEnabled, isTrue);
      await tester.tap(find.byIcon(Icons.hearing_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.isAudioDuckingEnabled, isFalse);
    });

    testWidgets(
        'renders without overflow on narrow 360px mobile screen constraint',
        (tester) async {
      await controller.connect();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: VoiceControlBar(voiceController: controller),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(VoiceControlBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
