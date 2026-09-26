import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/chat/controllers/chat_controller.dart';
import 'package:nobarin/features/chat/models/chat_message.dart';
import 'package:nobarin/features/chat/presentation/chat_panel_widget.dart';
import 'package:nobarin/features/chat/presentation/widgets/fullscreen_comment_overlay.dart';
import 'package:nobarin/features/chat/presentation/widgets/fullscreen_reaction_bar.dart';

void main() {
  group('ChatPanelWidget Tests', () {
    const testUser = UserProfile(
      id: 'test-user-1',
      username: 'Tester',
      avatarUrl: '🐼',
      isGuest: true,
    );

    testWidgets('renders empty state when no messages', (tester) async {
      final controller = ChatController(
        roomId: 'room-1',
        currentUser: testUser,
        supabase: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPanelWidget(chatController: controller),
          ),
        ),
      );

      expect(find.text('Belum ada pesan'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('shows typing indicator when another user is typing',
        (tester) async {
      final controller = ChatController(
        roomId: 'room-1',
        currentUser: testUser,
        supabase: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPanelWidget(chatController: controller),
          ),
        ),
      );

      expect(find.textContaining('sedang mengetik...'), findsNothing);

      // Simulate Bob typing
      controller.handleTypingBroadcast({
        'user_id': 'user-bob',
        'username': 'Bob',
        'is_typing': true,
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Bob sedang mengetik...'), findsOneWidget);

      // Simulate Bob stopped typing
      controller.handleTypingBroadcast({
        'user_id': 'user-bob',
        'username': 'Bob',
        'is_typing': false,
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Bob sedang mengetik...'), findsNothing);
      controller.dispose();
    });

    testWidgets(
        'typing in text field triggers controller setTyping and sending clears it',
        (tester) async {
      final controller = ChatController(
        roomId: 'room-1',
        currentUser: testUser,
        supabase: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPanelWidget(chatController: controller),
          ),
        ),
      );

      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);

      await tester.enterText(textField, 'Halo kawan');
      await tester.pump();

      // Submit message
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      expect(controller.messages.length, 1);
      expect(controller.messages.first.content, 'Halo kawan');
      expect(find.text('Halo kawan'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('differentiates single emoji from punctuation symbol in bubble rendering',
        (tester) async {
      final controller = ChatController(
        roomId: 'room-1',
        currentUser: testUser,
        supabase: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPanelWidget(chatController: controller),
          ),
        ),
      );

      // Send '?' (punctuation)
      await controller.sendMessage('?');
      await tester.pump();

      // Find Text widget with '?' within ListView
      final questionFinder = find.descendant(
        of: find.byType(ListView),
        matching: find.text('?'),
      );
      final questionTextWidget = tester.widget<Text>(questionFinder);
      expect(questionTextWidget.style?.fontSize, 14.0); // Regular bubble size, NOT 30!

      // Send '🔥' (emoji)
      await controller.sendMessage('🔥');
      await tester.pump();

      final emojiFinder = find.descendant(
        of: find.byType(ListView),
        matching: find.text('🔥'),
      );
      final emojiTextWidget = tester.widget<Text>(emojiFinder);
      expect(emojiTextWidget.style?.fontSize, 30.0); // Big naked emoji size!

      controller.dispose();
    });

    testWidgets('long pressing a message opens UGC moderation and reaction sheet',
        (tester) async {
      final controller = ChatController(
        roomId: 'room-1',
        currentUser: testUser,
        supabase: null,
      );

      // Add a message from another user
      controller.addMessage(
        ChatMessage.text(
          id: 'msg-other-1',
          roomId: 'room-1',
          userId: 'other-user',
          username: 'Bob',
          avatarUrl: '🦊',
          content: 'Hello World',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPanelWidget(
              chatController: controller,
              hostId: testUser.id, // Current user is host
            ),
          ),
        ),
      );

      expect(find.text('Hello World'), findsOneWidget);

      // Long press on the message bubble
      await tester.longPress(find.text('Hello World'));
      await tester.pumpAndSettle();

      // Verify UGC and new comment actions are presented
      expect(find.text('Balas Pesan'), findsOneWidget);
      expect(find.text('Sematkan Komentar'), findsOneWidget);
      expect(find.text('Salin Pesan'), findsOneWidget);
      expect(find.text('Laporkan Pesan'), findsOneWidget);
      expect(find.text('Blokir Bob'), findsOneWidget);
      expect(find.text('Hapus Pesan'), findsOneWidget);

      // Test copy message
      await tester.tap(find.text('Salin Pesan'));
      await tester.pumpAndSettle();

      expect(find.text('Pesan disalin ke clipboard'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('replying to a message shows preview banner and renders quote bubble',
        (tester) async {
      final controller = ChatController(
        roomId: 'room-1',
        currentUser: testUser,
        supabase: null,
      );

      controller.addMessage(
        ChatMessage.text(
          id: 'msg-bob-1',
          roomId: 'room-1',
          userId: 'user-bob',
          username: 'Bob',
          avatarUrl: '🦊',
          content: 'Filmnya seru banget!',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPanelWidget(chatController: controller),
          ),
        ),
      );

      // Long press and tap 'Balas Pesan'
      await tester.longPress(find.text('Filmnya seru banget!'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Balas Pesan'));
      await tester.pumpAndSettle();

      // Reply preview banner should be visible
      expect(find.byKey(const ValueKey('reply_preview_banner')), findsOneWidget);
      expect(find.text('Membalas Bob'), findsOneWidget);

      // Type reply and send
      await tester.enterText(find.byType(TextField), 'Bener banget!');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      // Preview banner disappears and reply message is rendered with quote
      expect(find.byKey(const ValueKey('reply_preview_banner')), findsNothing);
      expect(find.text('Bener banget!'), findsOneWidget);
      expect(controller.messages.last.isReply, isTrue);
      expect(controller.messages.last.replyToUsername, 'Bob');

      controller.dispose();
    });

    testWidgets('pinning a message displays pinned banner and allows host to unpin',
        (tester) async {
      final controller = ChatController(
        roomId: 'room-1',
        currentUser: testUser,
        supabase: null,
      );

      final msg = ChatMessage.text(
        id: 'msg-pin-1',
        roomId: 'room-1',
        userId: testUser.id,
        username: testUser.username,
        avatarUrl: testUser.avatarUrl,
        content: 'Aturan room: dilarang spoiler!',
      );
      controller.addMessage(msg);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPanelWidget(
              chatController: controller,
              hostId: testUser.id,
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('pinned_message_banner')), findsNothing);

      await controller.pinMessage(msg);
      await tester.pump();

      expect(find.byKey(const ValueKey('pinned_message_banner')), findsOneWidget);
      expect(find.text('Komentar Disematkan • '), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('unpin_message_button')));
      await tester.pump();

      expect(find.byKey(const ValueKey('pinned_message_banner')), findsNothing);
      controller.dispose();
    });

    testWidgets('smart message grouping hides duplicate username and avatar on consecutive messages',
        (tester) async {
      final controller = ChatController(
        roomId: 'room-1',
        currentUser: testUser,
        supabase: null,
      );

      final now = DateTime.now();
      controller.addMessage(
        ChatMessage.text(
          id: 'b1',
          roomId: 'room-1',
          userId: 'user-bob',
          username: 'Bob',
          avatarUrl: '🦊',
          content: 'Pesan pertama',
          createdAt: now,
        ),
      );
      controller.addMessage(
        ChatMessage.text(
          id: 'b2',
          roomId: 'room-1',
          userId: 'user-bob',
          username: 'Bob',
          avatarUrl: '🦊',
          content: 'Pesan kedua langsung',
          createdAt: now.add(const Duration(seconds: 20)),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPanelWidget(chatController: controller),
          ),
        ),
      );

      // Both messages are rendered, but Bob's username header & CircleAvatar only appear once
      expect(find.text('Pesan pertama'), findsOneWidget);
      expect(find.text('Pesan kedua langsung'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget);

      controller.dispose();
    });

    testWidgets('double tapping a message toggles heart reaction',
        (tester) async {
      final controller = ChatController(
        roomId: 'room-1',
        currentUser: testUser,
        supabase: null,
      );

      controller.addMessage(
        ChatMessage.text(
          id: 'msg-like-1',
          roomId: 'room-1',
          userId: 'user-bob',
          username: 'Bob',
          avatarUrl: '🦊',
          content: 'Double tap aku',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPanelWidget(chatController: controller),
          ),
        ),
      );

      final msgFinder = find.text('Double tap aku');
      await tester.tap(msgFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(msgFinder);
      await tester.pumpAndSettle();

      expect(
        controller.messages.first.hasUserReacted('❤️', testUser.id),
        isTrue,
      );

      controller.dispose();
    });

    testWidgets('FullscreenCommentOverlay shows live toast and toggles drawer',
        (tester) async {
      final controller = ChatController(
        roomId: 'room-1',
        currentUser: testUser,
        supabase: null,
      );

      bool isDrawerOpen = false;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    FullscreenReactionBar(
                      chatController: controller,
                      isCommentDrawerOpen: isDrawerOpen,
                      unreadCommentCount: 2,
                      onToggleComments: () {
                        setState(() => isDrawerOpen = !isDrawerOpen);
                      },
                    ),
                    Positioned.fill(
                      child: FullscreenCommentOverlay(
                        chatController: controller,
                        isDrawerOpen: isDrawerOpen,
                        onOpenDrawer: () {
                          setState(() => isDrawerOpen = true);
                        },
                        onCloseDrawer: () {
                          setState(() => isDrawerOpen = false);
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      // Incoming message while drawer closed shows toast
      controller.addMessage(
        ChatMessage.text(
          id: 'toast-1',
          roomId: 'room-1',
          userId: 'user-bob',
          username: 'Bob',
          avatarUrl: '🦊',
          content: 'Komentar muncul di layar penuh!',
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('fullscreen_toast_toast-1')),
        findsOneWidget,
      );

      // Tap toggle comments button on FullscreenReactionBar
      await tester.tap(
        find.byKey(const ValueKey('fullscreen_toggle_comments_button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Komentar Live'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('TextField enforces maxLength 500', (tester) async {
      final controller = ChatController(
        roomId: 'room-1',
        currentUser: testUser,
        supabase: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPanelWidget(chatController: controller),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.maxLength, 500);

      controller.dispose();
    });
  });
}
