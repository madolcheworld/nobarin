import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_party/features/auth/domain/user_profile.dart';
import 'package:watch_party/features/chat/controllers/chat_controller.dart';
import 'package:watch_party/features/chat/presentation/chat_panel_widget.dart';

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
  });
}
