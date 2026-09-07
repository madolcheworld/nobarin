import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_party/features/pip/presentation/pip_button.dart';
import 'package:watch_party/features/pip/services/pip_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'watch_party/pip_button_test';
  late MethodChannel mockChannel;
  final List<MethodCall> log = [];

  setUp(() {
    log.clear();
    mockChannel = const MethodChannel(channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mockChannel, (MethodCall methodCall) async {
      log.add(methodCall);
      switch (methodCall.method) {
        case 'isPipSupported':
          return true;
        case 'enterPip':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mockChannel, null);
  });

  group('PipButton Widget Tests', () {
    testWidgets('renders icon button when supported', (tester) async {
      final pipService = PipService.withChannel(mockChannel, isAndroid: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                PipButton(pipService: pipService),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.picture_in_picture_alt_rounded), findsOneWidget);
      expect(log.any((m) => m.method == 'isPipSupported'), isTrue);

      pipService.dispose();
    });

    testWidgets('hides button when PiP is not supported', (tester) async {
      final pipService = PipService.withChannel(mockChannel, isAndroid: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                PipButton(pipService: pipService),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.picture_in_picture_alt_rounded), findsNothing);

      pipService.dispose();
    });

    testWidgets('triggers onBeforeEnter and enterPip on press', (tester) async {
      final pipService = PipService.withChannel(mockChannel, isAndroid: true);
      bool beforeEnterCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                PipButton(
                  pipService: pipService,
                  onBeforeEnter: () {
                    beforeEnterCalled = true;
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.picture_in_picture_alt_rounded));
      await tester.pumpAndSettle();

      expect(beforeEnterCalled, isTrue);
      expect(log.any((m) => m.method == 'enterPip'), isTrue);

      pipService.dispose();
    });
  });
}
