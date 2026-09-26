import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/chat/controllers/chat_controller.dart';
import 'package:nobarin/features/chat/models/chat_message.dart';

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

    test('sendMessage enforces 500-char limit and collapses excessive newlines', () async {
      final longText = 'A' * 600;
      await chatController.sendMessage(longText);

      expect(chatController.messages.length, 1);
      expect(chatController.messages.first.content.length, 500);

      final multilineText = 'Line 1\n\n\n\n\nLine 2';
      await chatController.sendMessage(multilineText);
      expect(chatController.messages.last.content, 'Line 1\n\nLine 2');
    });

    test('ChatMessage JSON serialization preserves guest sender_name and sender_avatar', () {
      final guestMsg = ChatMessage(
        id: 'msg-guest-1',
        roomId: 'room-123',
        userId: null,
        username: 'GuestUser',
        avatarUrl: '🦊',
        content: 'Halo dari tamu!',
        createdAt: DateTime.now(),
      );

      final json = guestMsg.toJson();
      expect(json['sender_name'], 'GuestUser');
      expect(json['sender_avatar'], '🦊');

      final reconstructed = ChatMessage.fromJson(json);
      expect(reconstructed.username, 'GuestUser');
      expect(reconstructed.avatarUrl, '🦊');
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

    test('toggleMessageReaction adds and removes reaction for current user atomically', () async {
      await chatController.sendMessage('Tes reaksi');
      final msgId = chatController.messages.first.id;

      // Add reaction
      await chatController.toggleMessageReaction(msgId, '❤️');
      expect(chatController.messages.first.reactions['❤️'], contains(testUser.id));

      // Remove reaction (toggle off)
      await chatController.toggleMessageReaction(msgId, '❤️');
      expect(chatController.messages.first.reactions['❤️']?.contains(testUser.id) ?? false, isFalse);
    });

    test('handleReactionToggledBroadcast merges reactions without overriding other emojis', () async {
      await chatController.sendMessage('Tes reaksi broadcast');
      final msgId = chatController.messages.first.id;

      // Bob adds 👍
      chatController.handleReactionToggledBroadcast({
        'message_id': msgId,
        'user_id': 'user-bob',
        'emoji': '👍',
        'action': 'add',
      });
      expect(chatController.messages.first.reactions['👍'], contains('user-bob'));

      // Alice adds ❤️
      chatController.handleReactionToggledBroadcast({
        'message_id': msgId,
        'user_id': 'user-alice',
        'emoji': '❤️',
        'action': 'add',
      });
      // Both 👍 from Bob and ❤️ from Alice exist
      expect(chatController.messages.first.reactions['👍'], contains('user-bob'));
      expect(chatController.messages.first.reactions['❤️'], contains('user-alice'));

      // Bob removes 👍
      chatController.handleReactionToggledBroadcast({
        'message_id': msgId,
        'user_id': 'user-bob',
        'emoji': '👍',
        'action': 'remove',
      });
      expect(chatController.messages.first.reactions['👍']?.contains('user-bob') ?? false, isFalse);
      expect(chatController.messages.first.reactions['❤️'], contains('user-alice'));
    });

    test('blockUser hides messages from blocked user and unblock restores visibility', () {
      final msg1 = ChatMessage.text(
        id: 'msg-1',
        roomId: 'room-123',
        userId: 'spammer-id',
        username: 'Spammer',
        avatarUrl: '💀',
        content: 'Spam message',
      );
      final msg2 = ChatMessage.text(
        id: 'msg-2',
        roomId: 'room-123',
        userId: 'friend-id',
        username: 'Friend',
        avatarUrl: '😊',
        content: 'Friendly message',
      );

      chatController.addMessage(msg1);
      chatController.addMessage(msg2);

      expect(chatController.messages.length, 2);

      // Block spammer
      chatController.blockUser('spammer-id');
      expect(chatController.isUserBlocked('spammer-id'), isTrue);
      expect(chatController.messages.length, 1);
      expect(chatController.messages.first.userId, 'friend-id');

      // Unblock spammer
      chatController.unblockUser('spammer-id');
      expect(chatController.isUserBlocked('spammer-id'), isFalse);
      expect(chatController.messages.length, 2);
    });

    test('deleteMessage removes message locally and via broadcast', () async {
      await chatController.sendMessage('Pesan akan dihapus');
      final msgId = chatController.messages.first.id;
      expect(chatController.messages.length, 1);

      // Local delete
      await chatController.deleteMessage(msgId);
      expect(chatController.messages.isEmpty, isTrue);

      // Add another message and delete via broadcast
      await chatController.sendMessage('Pesan kedua');
      final msgId2 = chatController.messages.first.id;
      expect(chatController.messages.length, 1);

      chatController.handleMessageDeletedBroadcast({
        'message_id': msgId2,
      });
      expect(chatController.messages.isEmpty, isTrue);
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

    test('handleTypingBroadcast handles nested Supabase payload envelope', () {
      chatController.handleTypingBroadcast({
        'event': 'TYPING_STATUS',
        'type': 'broadcast',
        'payload': {
          'user_id': 'user-99',
          'username': 'EnvelopeUser',
          'is_typing': true,
        },
      });

      expect(chatController.hasTypingUsers, isTrue);
      expect(chatController.typingStatusText, 'EnvelopeUser sedang mengetik...');
    });

    test('sendMessage automatically resets typing state', () async {
      chatController.setTyping(true);
      await chatController.sendMessage('Halo dunia!');

      expect(chatController.messages.length, 1);
      expect(chatController.messages.first.content, 'Halo dunia!');
    });
  });
}
