import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/room/presentation/widgets/room_loading_view.dart';

void main() {
  group('RoomLoadingView Widget Tests', () {
    testWidgets('renders room code and title correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RoomLoadingView(
            roomCode: 'WP1234',
            roomTitle: 'Nonton Bareng Anime',
          ),
        ),
      );

      expect(find.text('Nonton Bareng Anime'), findsOneWidget);
      expect(find.text('Kode: WP1234'), findsOneWidget);
      expect(find.text('Menghubungkan ke server room...'), findsOneWidget);

      // Clean up animation controller before ending test
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('rotates status messages periodically', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RoomLoadingView(
            roomCode: 'WP9999',
          ),
        ),
      );

      expect(find.text('Menyiapkan Room'), findsOneWidget);
      expect(find.text('Menghubungkan ke server room...'), findsOneWidget);

      // Advance timer for next status
      await tester.pump(const Duration(milliseconds: 2300));
      expect(find.text('Menyiapkan pemutar video...'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('shows cancel button after timeout and triggers onCancel',
        (tester) async {
      bool cancelClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: RoomLoadingView(
            roomCode: 'WP7777',
            onCancel: () {
              cancelClicked = true;
            },
          ),
        ),
      );

      // Initially cancel button is not visible
      expect(find.text('Koneksi lambat? Kembali ke Lobby'), findsNothing);

      // Advance past 7 seconds timeout
      await tester.pump(const Duration(seconds: 8));
      expect(find.text('Koneksi lambat? Kembali ke Lobby'), findsOneWidget);

      // Tap cancel button
      await tester.tap(find.text('Koneksi lambat? Kembali ke Lobby'));
      expect(cancelClicked, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
