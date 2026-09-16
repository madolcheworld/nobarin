import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/auth/domain/user_profile.dart';
import 'package:nobarin/features/auth/presentation/auth_controller.dart';
import 'package:nobarin/features/lobby/data/lobby_repository.dart';
import 'package:nobarin/features/lobby/presentation/lobby_controller.dart';
import 'package:nobarin/features/lobby/presentation/widgets/create_room_dialog.dart';
import 'package:nobarin/features/room/models/room_model.dart';

class _FakeAuthController extends StateNotifier<AsyncValue<UserProfile?>>
    implements AuthController {
  _FakeAuthController(UserProfile profile)
      : super(AsyncValue.data(profile));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const fakeUser = UserProfile(
    id: 'user-test-123',
    username: 'RiyanTester',
    avatarUrl: '🦊',
  );

  Widget buildTestableDialog({
    String? initialMediaType,
    String? initialMediaUrl,
    String? initialTitle,
    LobbyRepository? repository,
  }) {
    final repo = repository ?? LobbyRepository(supabase: null);

    return ProviderScope(
      overrides: [
        lobbyRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith((ref) => _FakeAuthController(fakeUser)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: CreateRoomDialog(
            initialMediaType: initialMediaType,
            initialMediaUrl: initialMediaUrl,
            initialTitle: initialTitle,
          ),
        ),
      ),
    );
  }

  group('CreateRoomDialog - 2-Step Flow Tests (Clean Video Selection)', () {
    testWidgets('Initial view shows Step 1 (Pilih Sumber Video) without skip or direct video',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestableDialog());
      await tester.pump();

      // Step 1 Header & Indicator
      expect(find.text('Pilih Sumber Video'), findsAtLeast(1));
      expect(find.text('Langkah 1 dari 2'), findsOneWidget);

      // Supported Options
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('Bstation / Bilibili'), findsOneWidget);

      // Verify Direct Video is cleanly removed
      expect(find.textContaining('Direct Video'), findsNothing);
      expect(find.textContaining('Direct Video Link'), findsNothing);

      // Verify NO skip option exists
      expect(find.textContaining('Lewati'), findsNothing);
      expect(find.textContaining('lewati'), findsNothing);
      expect(find.textContaining('pilih nanti'), findsNothing);
    });

    testWidgets('Opening with YouTube initialMediaUrl opens directly at Step 2',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestableDialog(
          initialMediaType: 'youtube',
          initialMediaUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          initialTitle: 'Nobar Rick Astley',
        ),
      );
      await tester.pump();

      // Opens straight into Step 2
      expect(find.text('Pengaturan Room'), findsAtLeast(1));
      expect(find.text('Langkah 2 dari 2'), findsOneWidget);
      expect(find.text('Nobar Rick Astley'), findsAtLeast(1));
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('Mode Kontrol Pemutaran'), findsOneWidget);
      expect(find.text('Buat Room Sekarang'), findsOneWidget);
    });

    testWidgets('Opening with Bstation initialMediaUrl opens directly at Step 2',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestableDialog(
          initialMediaType: 'bstation',
          initialMediaUrl: 'https://www.bilibili.tv/en/video/12345678',
          initialTitle: 'Anime Episode 1',
        ),
      );
      await tester.pump();

      // Opens straight into Step 2 with Bstation preview
      expect(find.text('Pengaturan Room'), findsAtLeast(1));
      expect(find.text('Langkah 2 dari 2'), findsOneWidget);
      expect(find.text('Anime Episode 1'), findsAtLeast(1));
      expect(find.text('Bstation'), findsOneWidget);
    });

    testWidgets('BackButton in Step 2 header returns to Step 1',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestableDialog(
          initialMediaType: 'youtube',
          initialMediaUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          initialTitle: 'Nobar Rick Astley',
        ),
      );
      await tester.pump();

      expect(find.text('Langkah 2 dari 2'), findsOneWidget);

      // Tap back button in header
      await tester.tap(find.byTooltip('Kembali ke pilih video'));
      await tester.pumpAndSettle();

      // Should be back to Step 1
      expect(find.text('Pilih Sumber Video'), findsAtLeast(1));
      expect(find.text('Langkah 1 dari 2'), findsOneWidget);
      expect(find.textContaining('Tetap gunakan:'), findsOneWidget);
    });

    testWidgets('Ganti Video button in Step 2 returns to Step 1 and allow returning back to Step 2',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestableDialog(
          initialMediaType: 'youtube',
          initialMediaUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          initialTitle: 'Nobar Rick Astley',
        ),
      );
      await tester.pump();

      expect(find.text('Ganti Video'), findsOneWidget);

      // Tap "Ganti Video"
      await tester.tap(find.text('Ganti Video'));
      await tester.pumpAndSettle();

      // Should return to Step 1
      expect(find.text('Pilih Sumber Video'), findsAtLeast(1));
      expect(find.text('Langkah 1 dari 2'), findsOneWidget);
      expect(find.textContaining('Tetap gunakan: Nobar Rick Astley'), findsOneWidget);

      // Tap "Tetap gunakan: ..." to go back to Step 2
      await tester.tap(find.textContaining('Tetap gunakan:'));
      await tester.pumpAndSettle();

      expect(find.text('Pengaturan Room'), findsAtLeast(1));
      expect(find.text('Langkah 2 dari 2'), findsOneWidget);
    });

    testWidgets('Submitting valid form in Step 2 successfully creates room',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = LobbyRepository(supabase: null);
      RoomModel? resultRoom;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lobbyRepositoryProvider.overrideWithValue(repo),
            authControllerProvider.overrideWith((ref) => _FakeAuthController(fakeUser)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    resultRoom = await CreateRoomDialog.show(
                      context,
                      initialMediaType: 'youtube',
                      initialMediaUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
                      initialTitle: 'Nobar Testing Seru',
                    );
                  },
                  child: const Text('Buka Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Buka Dialog'));
      await tester.pumpAndSettle();

      // Check on Step 2
      expect(find.text('Pengaturan Room'), findsAtLeast(1));
      expect(find.text('Buat Room Sekarang'), findsOneWidget);

      // Tap submit
      await tester.tap(find.text('Buat Room Sekarang'));
      await tester.pumpAndSettle();

      // Verify room was created and dialog dismissed
      expect(resultRoom, isNotNull);
      expect(resultRoom!.title, 'Nobar Testing Seru');
      expect(resultRoom!.currentMediaUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(resultRoom!.hostName, 'RiyanTester');
    });
  });
}
