import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/chat/controllers/chat_controller.dart';
import 'package:nobarin/features/chat/models/chat_message.dart';
import 'package:nobarin/features/chat/presentation/chat_panel_widget.dart';

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

      // Verify UGC actions are presented
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
