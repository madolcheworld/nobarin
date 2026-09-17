import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/room/presentation/widgets/exit_room_dialog.dart';

void main() {
  group('ExitRoomLoadingDialog Widget Tests', () {
    testWidgets('renders message and subMessage correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExitRoomLoadingDialog(
              message: 'Mengalihkan Host & Keluar...',
              subMessage: 'Menyerahkan peran Host ke Budi',
            ),
          ),
        ),
      );

      expect(find.text('Mengalihkan Host & Keluar...'), findsOneWidget);
      expect(find.text('Menyerahkan peran Host ke Budi'), findsOneWidget);
      expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('ExitRoomLoadingDialog.show displays dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  ExitRoomLoadingDialog.show(
                    context,
                    message: 'Sedang Keluar Room...',
                    subMessage: 'Memutuskan koneksi dan kembali ke lobby',
                  );
                },
                child: const Text('Keluar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Keluar'));
      await tester.pump();

      expect(find.text('Sedang Keluar Room...'), findsOneWidget);
      expect(
        find.text('Memutuskan koneksi dan kembali ke lobby'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
