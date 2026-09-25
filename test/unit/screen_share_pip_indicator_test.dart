import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/screenshare/presentation/widgets/screen_share_pip_indicator.dart';

void main() {
  group('ScreenSharePipIndicator Widget Tests', () {
    testWidgets('renders live text, room title, and subtitle correctly',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 180,
              child: ScreenSharePipIndicator(
                roomTitle: 'Anime Night Room',
              ),
            ),
          ),
        ),
      );

      // Verify text elements
      expect(find.text('LIVE BERBAGI LAYAR'), findsOneWidget);
      expect(find.text('Anime Night Room'), findsOneWidget);
      expect(find.text('Layar HP Anda sedang disiarkan'), findsOneWidget);
      expect(find.byIcon(Icons.mobile_screen_share_rounded), findsOneWidget);

      // onStop is null so no button rendered
      expect(find.text('Hentikan Layar'), findsNothing);
    });

    testWidgets('triggers onStop callback when button is tapped',
        (tester) async {
      bool stopped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 200,
              child: ScreenSharePipIndicator(
                roomTitle: 'Movie Room',
                onStop: () {
                  stopped = true;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('Hentikan Layar'), findsOneWidget);
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

      await tester.tap(find.text('Hentikan Layar'));
      await tester.pump();

      expect(stopped, isTrue);
    });
  });
}
