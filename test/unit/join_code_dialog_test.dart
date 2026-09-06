import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_party/features/lobby/data/lobby_repository.dart';
import 'package:watch_party/features/lobby/presentation/lobby_controller.dart';
import 'package:watch_party/features/lobby/presentation/widgets/join_code_dialog.dart';
import 'package:watch_party/features/room/models/room_model.dart';

void main() {
  Widget buildTestableDialog({
    required LobbyRepository repository,
    ValueChanged<RoomModel>? onJoined,
  }) {
    return ProviderScope(
      overrides: [
        lobbyRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: JoinCodeDialog(onJoined: onJoined),
        ),
      ),
    );
  }

  testWidgets('JoinCodeDialog shows error when submitted with empty code',
      (WidgetTester tester) async {
    final repo = LobbyRepository(supabase: null);

    await tester.pumpWidget(buildTestableDialog(repository: repo));
    await tester.pump();

    // Tap Gabung with empty field
    await tester.tap(find.text('Gabung'));
    await tester.pump();

    expect(find.text('Masukkan kode room'), findsOneWidget);
  });

  testWidgets('JoinCodeDialog shows error when room is not found',
      (WidgetTester tester) async {
    final repo = LobbyRepository(supabase: null);

    await tester.pumpWidget(buildTestableDialog(repository: repo));
    await tester.pump();

    // Enter non-existent code
    await tester.enterText(find.byType(TextField), 'INVALID99');
    await tester.tap(find.text('Gabung'));
    await tester.pump();

    expect(
      find.text('Room dengan kode "INVALID99" tidak ditemukan'),
      findsOneWidget,
    );
  });

  testWidgets('JoinCodeDialog succeeds with valid code and calls onJoined',
      (WidgetTester tester) async {
    final repo = LobbyRepository(supabase: null);
    RoomModel? joinedRoom;

    await tester.pumpWidget(
      buildTestableDialog(
        repository: repo,
        onJoined: (room) => joinedRoom = room,
      ),
    );
    await tester.pump();

    // Enter lowercase code 'wp1001' which matches demo room WP1001
    await tester.enterText(find.byType(TextField), 'wp1001');
    await tester.tap(find.text('Gabung'));
    await tester.pumpAndSettle();

    expect(joinedRoom, isNotNull);
    expect(joinedRoom!.code, 'WP1001');
  });

  testWidgets('JoinCodeDialog succeeds with hyphenated code wp-1001',
      (WidgetTester tester) async {
    final repo = LobbyRepository(supabase: null);
    RoomModel? joinedRoom;

    await tester.pumpWidget(
      buildTestableDialog(
        repository: repo,
        onJoined: (room) => joinedRoom = room,
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'wp-1001');
    await tester.tap(find.text('Gabung'));
    await tester.pumpAndSettle();

    expect(joinedRoom, isNotNull);
    expect(joinedRoom!.code, 'WP1001');
  });

  testWidgets('JoinCodeDialog succeeds with pasted room URL',
      (WidgetTester tester) async {
    final repo = LobbyRepository(supabase: null);
    RoomModel? joinedRoom;

    await tester.pumpWidget(
      buildTestableDialog(
        repository: repo,
        onJoined: (room) => joinedRoom = room,
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byType(TextField),
      'http://localhost:8080/#/room/WP1001',
    );
    await tester.tap(find.text('Gabung'));
    await tester.pumpAndSettle();

    expect(joinedRoom, isNotNull);
    expect(joinedRoom!.code, 'WP1001');
  });

  testWidgets('JoinCodeDialog succeeds with suffix 1001',
      (WidgetTester tester) async {
    final repo = LobbyRepository(supabase: null);
    RoomModel? joinedRoom;

    await tester.pumpWidget(
      buildTestableDialog(
        repository: repo,
        onJoined: (room) => joinedRoom = room,
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '1001');
    await tester.tap(find.text('Gabung'));
    await tester.pumpAndSettle();

    expect(joinedRoom, isNotNull);
    expect(joinedRoom!.code, 'WP1001');
  });

  testWidgets('JoinCodeDialog succeeds with en-dash WP–1001',
      (WidgetTester tester) async {
    final repo = LobbyRepository(supabase: null);
    RoomModel? joinedRoom;

    await tester.pumpWidget(
      buildTestableDialog(
        repository: repo,
        onJoined: (room) => joinedRoom = room,
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'WP–1001');
    await tester.tap(find.text('Gabung'));
    await tester.pumpAndSettle();

    expect(joinedRoom, isNotNull);
    expect(joinedRoom!.code, 'WP1001');
  });

  testWidgets('JoinCodeDialog succeeds with quoted code "WP1001"',
      (WidgetTester tester) async {
    final repo = LobbyRepository(supabase: null);
    RoomModel? joinedRoom;

    await tester.pumpWidget(
      buildTestableDialog(
        repository: repo,
        onJoined: (room) => joinedRoom = room,
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '"WP1001"');
    await tester.tap(find.text('Gabung'));
    await tester.pumpAndSettle();

    expect(joinedRoom, isNotNull);
    expect(joinedRoom!.code, 'WP1001');
  });

  testWidgets('JoinCodeDialog succeeds with prefix Kode room: WP1001',
      (WidgetTester tester) async {
    final repo = LobbyRepository(supabase: null);
    RoomModel? joinedRoom;

    await tester.pumpWidget(
      buildTestableDialog(
        repository: repo,
        onJoined: (room) => joinedRoom = room,
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Kode room: WP1001');
    await tester.tap(find.text('Gabung'));
    await tester.pumpAndSettle();

    expect(joinedRoom, isNotNull);
    expect(joinedRoom!.code, 'WP1001');
  });

  testWidgets('JoinCodeDialog clears error when user types new character',
      (WidgetTester tester) async {
    final repo = LobbyRepository(supabase: null);

    await tester.pumpWidget(buildTestableDialog(repository: repo));
    await tester.pump();

    // Trigger error
    await tester.tap(find.text('Gabung'));
    await tester.pump();
    expect(find.text('Masukkan kode room'), findsOneWidget);

    // Typing clears error
    await tester.enterText(find.byType(TextField), 'W');
    await tester.pump();
    expect(find.text('Masukkan kode room'), findsNothing);
  });
}
