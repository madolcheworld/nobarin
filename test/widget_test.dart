import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nobarin/app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('NobarinApp initial launch renders WelcomeScreen',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const ProviderScope(
        child: NobarinApp(),
      ),
    );

    // Pump to process animations
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));

    // Verify WelcomeScreen elements
    expect(find.text('Nobarin'), findsOneWidget);
    expect(find.text('Pilih Avatar'), findsOneWidget);
    expect(find.text('Nama / Nickname Kamu'), findsOneWidget);
    expect(find.text('Mulai Nonton'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('WelcomeScreen allows avatar selection and nickname entry',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const ProviderScope(
        child: NobarinApp(),
      ),
    );

    await tester.pump(const Duration(milliseconds: 600));

    // Enter nickname
    await tester.enterText(find.byType(TextField), 'TestUser');
    expect(find.text('TestUser'), findsOneWidget);

    // Tap start button
    await tester.tap(find.text('Mulai Nonton'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 600));
  });
}
