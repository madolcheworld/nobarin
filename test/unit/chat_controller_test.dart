import 'package:flutter_test/flutter_test.dart';
import 'package:watch_party/features/auth/domain/user_profile.dart';
import 'package:watch_party/features/chat/controllers/chat_controller.dart';

void main() {
  group('ChatController Unit Tests', () {
    late ChatController chatController;
    const testUser = UserProfile(
      id: 'test-user-1',
      username: 'Tester',
      avatarUrl: '🐼',
      isGuest: true,
    );

    setUp(() {
      chatController = ChatController(
        roomId: 'room-123',
        currentUser: testUser,
        supabase: null, // Offline / mock mode
      );
    });

    tearDown(() {
      chatController.dispose();
    });

    test('initializes with an empty message list for clean UI', () {
      expect(chatController.messages.isEmpty, isTrue);
    });

    test('sendMessage adds text message correctly', () async {
      await chatController.sendMessage('Halo semua!');

      expect(chatController.messages.length, 1);
      final lastMsg = chatController.messages.last;
      expect(lastMsg.content, 'Halo semua!');
      expect(lastMsg.username, testUser.username);
      expect(lastMsg.avatarUrl, testUser.avatarUrl);
      expect(lastMsg.isText, isTrue);
    });

    test('sendMessage ignores whitespace only messages', () async {
      final initialCount = chatController.messages.length;
      await chatController.sendMessage('   ');
      expect(chatController.messages.length, initialCount);
    });

    test('sendReaction adds emoji message and emits on reaction stream',
        () async {
      FloatingReaction? emittedReaction;
      final sub = chatController.reactionsStream.listen((reaction) {
        emittedReaction = reaction;
      });

      await chatController.sendReaction('🔥');

      expect(chatController.messages.last.content, '🔥');
      expect(chatController.messages.last.isReaction, isTrue);
      expect(emittedReaction, isNotNull);
      expect(emittedReaction!.emoji, '🔥');

      await sub.cancel();
    });

    test('sendSystemMessage adds system notification properly', () async {
      await chatController.sendSystemMessage('User Alex bergabung.');
      final lastMsg = chatController.messages.last;
      expect(lastMsg.content, 'User Alex bergabung.');
      expect(lastMsg.isSystem, isTrue);
      expect(lastMsg.userId, isNull);
    });

    test('sendSystemMessage ignores empty content', () async {
      final initialCount = chatController.messages.length;
      await chatController.sendSystemMessage('   ');
      expect(chatController.messages.length, initialCount);
    });
  });
}
