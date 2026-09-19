import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/chat/controllers/chat_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

    test('sendSystemMessage deduplicates identical messages within short window', () async {
      await chatController.sendSystemMessage('Alex keluar');
      expect(chatController.messages.length, 1);

      // Immediate duplicate should be ignored
      await chatController.sendSystemMessage('Alex keluar');
      expect(chatController.messages.length, 1);

      // Different message should be accepted
      await chatController.sendSystemMessage('Bob keluar');
      expect(chatController.messages.length, 2);
    });

    test('handleTypingBroadcast updates typing status and usernames', () {
      expect(chatController.hasTypingUsers, isFalse);
      expect(chatController.typingStatusText, isNull);

      chatController.handleTypingBroadcast({
        'user_id': 'user-2',
        'username': 'Bob',
        'is_typing': true,
      });

      expect(chatController.hasTypingUsers, isTrue);
      expect(chatController.typingUsernames, contains('Bob'));
      expect(chatController.typingStatusText, 'Bob sedang mengetik...');

      // Remove typing
      chatController.handleTypingBroadcast({
        'user_id': 'user-2',
        'username': 'Bob',
        'is_typing': false,
      });

      expect(chatController.hasTypingUsers, isFalse);
      expect(chatController.typingStatusText, isNull);
    });

    test('typingStatusText formats correctly for 1, 2, and >2 users', () {
      // 1 user
      chatController.handleTypingBroadcast({
        'user_id': 'user-2',
        'username': 'Alice',
        'is_typing': true,
      });
      expect(chatController.typingStatusText, 'Alice sedang mengetik...');

      // 2 users
      chatController.handleTypingBroadcast({
        'user_id': 'user-3',
        'username': 'Bob',
        'is_typing': true,
      });
      expect(chatController.typingStatusText, 'Alice dan Bob sedang mengetik...');

      // 3 users
      chatController.handleTypingBroadcast({
        'user_id': 'user-4',
        'username': 'Charlie',
        'is_typing': true,
      });
      expect(chatController.typingStatusText, 'Alice dan 2 lainnya sedang mengetik...');
    });

    test('handleTypingBroadcast ignores own user events', () {
      chatController.handleTypingBroadcast({
        'user_id': testUser.id,
        'username': testUser.username,
        'is_typing': true,
      });

      expect(chatController.hasTypingUsers, isFalse);
      expect(chatController.typingStatusText, isNull);
    });

    test('sendMessage automatically resets typing state', () async {
      chatController.setTyping(true);
      await chatController.sendMessage('Halo dunia!');

      expect(chatController.messages.length, 1);
      expect(chatController.messages.first.content, 'Halo dunia!');
    });
  });
}
