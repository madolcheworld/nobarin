import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/core/errors/failures.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/chat/controllers/chat_controller.dart';
import 'package:nobarin/features/chat/models/chat_message.dart';
import 'package:nobarin/features/room/controllers/unified_player_controller.dart';
import 'package:nobarin/features/screenshare/controllers/webrtc_screenshare_controller.dart';
import 'package:nobarin/features/voice/controllers/webrtc_voice_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppFailure Architecture Tests', () {
    test('NetworkFailure stores custom message and cause', () {
      final failure = NetworkFailure('Koneksi internet bermasalah', Exception('timeout'));
      expect(failure.message, 'Koneksi internet bermasalah');
      expect(failure.cause, isNotNull);
      expect(failure.toString(), 'Koneksi internet bermasalah');
    });

    test('AuthFailure defaults and overrides message', () {
      const defaultFailure = AuthFailure();
      expect(defaultFailure.message, contains('autentikasi'));

      const customFailure = AuthFailure('Sesi autentikasi telah berakhir');
      expect(customFailure.message, 'Sesi autentikasi telah berakhir');
    });

    test('RoomNotFoundFailure formats room code in message', () {
      final failure = RoomNotFoundFailure('ABC12');
      expect(failure.code, 'ABC12');
      expect(failure.message, contains('ABC12'));
    });

    test('RoomClosedFailure stores reason', () {
      final failure = RoomClosedFailure('Host telah mengakhiri sesi.');
      expect(failure.reason, 'Host telah mengakhiri sesi.');
      expect(failure.message, 'Host telah mengakhiri sesi.');
    });

    test('MediaPlaybackFailure stores error message and cause', () {
      final cause = Exception('H.265 unsupported');
      final failure = MediaPlaybackFailure('Format video tidak didukung', cause);
      expect(failure.message, 'Format video tidak didukung');
      expect(failure.cause, cause);
    });

    test('WebRtcFailure stores message and cause', () {
      final failure = WebRtcFailure('Koneksi peer WebRTC terputus');
      expect(failure.message, 'Koneksi peer WebRTC terputus');
    });

    test('PermissionFailure stores permission name and message', () {
      const failure = PermissionFailure(
        'microphone',
        'Izin mikrofon diperlukan untuk voice chat.',
      );
      expect(failure.permissionName, 'microphone');
      expect(failure.message, 'Izin mikrofon diperlukan untuk voice chat.');
    });

    test('ServerFailure stores message and database exception cause', () {
      final cause = Exception('Database 500 error');
      final failure = ServerFailure('Database query failed', cause);
      expect(failure.message, 'Database query failed');
      expect(failure.cause, cause);
    });
  });

  group('ChatMessage & Chat Resilience Tests', () {
    test('ChatMessage defaults to MessageStatus.sent', () {
      final msg = ChatMessage(
        id: 'msg-1',
        roomId: 'room-1',
        content: 'Halo',
        createdAt: DateTime.now(),
      );
      expect(msg.status, MessageStatus.sent);
    });

    test('ChatMessage copyWith updates status correctly', () {
      final msg = ChatMessage(
        id: 'msg-1',
        roomId: 'room-1',
        content: 'Halo',
        createdAt: DateTime.now(),
        status: MessageStatus.sending,
      );

      final failedMsg = msg.copyWith(status: MessageStatus.failed);
      expect(failedMsg.status, MessageStatus.failed);
      expect(failedMsg.content, 'Halo');
      expect(failedMsg.id, 'msg-1');

      final sentMsg = failedMsg.copyWith(status: MessageStatus.sent);
      expect(sentMsg.status, MessageStatus.sent);
    });

    test('ChatController marks message as failed when offline and supports retryMessage', () async {
      const testUser = UserProfile(
        id: 'user-1',
        username: 'TestUser',
        avatarUrl: '🦊',
      );

      final controller = ChatController(
        roomId: 'room-101',
        currentUser: testUser,
        supabase: null, // Offline
      );

      await controller.sendMessage('Pesan uji coba');

      expect(controller.messages.length, 1);
      final msg = controller.messages.first;
      expect(msg.content, 'Pesan uji coba');
      // When channel is null, it should update to MessageStatus.failed
      expect(msg.status, MessageStatus.failed);

      // Attempting to retry a failed message
      await controller.retryMessage(msg.id);
      expect(controller.messages.first.status, MessageStatus.failed);

      controller.dispose();
    });
  });

  group('UnifiedPlayerController Resilience Tests', () {
    test('error state management and reloadCurrentMedia', () async {
      final player = UnifiedPlayerController();
      expect(player.errorMessage, isNull);

      player.clearError();
      expect(player.errorMessage, isNull);

      // Calling reloadCurrentMedia with empty url is a safe no-op
      await player.reloadCurrentMedia();
      expect(player.errorMessage, isNull);

      player.dispose();
    });
  });

  group('WebRtcVoiceController Error Handling Tests', () {
    test('voice controller initializes with clean error state and reconnect works', () async {
      final voice = WebRtcVoiceController(
        roomId: 'room-202',
        userId: 'user-99',
        userName: 'Tester',
        supabase: null,
      );

      expect(voice.errorMessage, isNull);
      expect(voice.status, VoiceStatus.disconnected);

      await voice.connect();
      // Without supabase, status transitions to unconfigured
      expect(voice.status, VoiceStatus.unconfigured);
      expect(voice.errorMessage, isNull);

      await voice.reconnect();
      expect(voice.status, VoiceStatus.unconfigured);

      voice.dispose();
    });
  });

  group('WebRtcScreenShareController Error Handling Tests', () {
    test('startScreenShare sets descriptive errorMessage when not allowed', () async {
      final screen = WebRtcScreenShareController(
        roomId: 'room-303',
        userId: 'user-viewer',
        userName: 'Viewer',
        isHostProvider: () => false,
        isCollaborativeProvider: () => false,
        supabase: null,
      );

      expect(screen.errorMessage, isNull);
      expect(screen.canShareScreen, isFalse);

      final result = await screen.startScreenShare();
      expect(result, isFalse);
      expect(screen.errorMessage, isNotNull);
      expect(screen.errorMessage, contains('izin'));

      screen.dispose();
    });
  });
}
