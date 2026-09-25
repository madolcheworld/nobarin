import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/features/pip/services/pip_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'watch_party/pip_test_channel';
  late MethodChannel mockChannel;
  late PipService pipService;
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
        case 'setAutoEnterPip':
          return true;
        default:
          return null;
      }
    });

    pipService = PipService.withChannel(mockChannel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mockChannel, null);
    pipService.dispose();
  });

  group('PipService Unit Tests', () {
    test('initial state isInPipMode is false', () {
      expect(pipService.isInPipMode, isFalse);
      expect(pipService.isInPipModeNotifier.value, isFalse);
    });

    test('isPipSupported invokes channel and returns true', () async {
      final supported = await pipService.isPipSupported();
      expect(supported, isTrue);
      expect(log, hasLength(1));
      expect(log.first.method, 'isPipSupported');
    });

    test('isPipSupported handles channel error gracefully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mockChannel, (MethodCall methodCall) async {
        throw PlatformException(code: 'ERROR', message: 'Not supported');
      });

      final supported = await pipService.isPipSupported();
      expect(supported, isFalse);
    });

    test('enterPip invokes channel with default 16:9 aspect ratio', () async {
      final success = await pipService.enterPip();
      expect(success, isTrue);
      expect(log, hasLength(1));
      expect(log.first.method, 'enterPip');
      expect(log.first.arguments, {'numerator': 16, 'denominator': 9});
    });

    test('enterPip invokes channel with custom aspect ratio', () async {
      final success = await pipService.enterPip(numerator: 4, denominator: 3);
      expect(success, isTrue);
      expect(log, hasLength(1));
      expect(log.first.method, 'enterPip');
      expect(log.first.arguments, {'numerator': 4, 'denominator': 3});
    });

    test('enterPip handles platform exceptions safely', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mockChannel, (MethodCall methodCall) async {
        throw PlatformException(code: 'FAILED', message: 'Cannot enter pip');
      });

      final success = await pipService.enterPip();
      expect(success, isFalse);
    });

    test('setAutoEnterPip invokes channel with boolean flag', () async {
      await pipService.setAutoEnterPip(true);
      expect(log, hasLength(1));
      expect(log.first.method, 'setAutoEnterPip');
      expect(log.first.arguments, {'enabled': true});

      await pipService.setAutoEnterPip(false);
      expect(log, hasLength(2));
      expect(log.last.method, 'setAutoEnterPip');
      expect(log.last.arguments, {'enabled': false});
    });

    test('non-Android platform returns false and does not invoke channel', () async {
      final nonAndroidService = PipService.withChannel(mockChannel, isAndroid: false);
      expect(await nonAndroidService.isPipSupported(), isFalse);
      expect(await nonAndroidService.enterPip(), isFalse);
      await nonAndroidService.setAutoEnterPip(true);
      expect(log, isEmpty);
      nonAndroidService.dispose();
    });

    test('native callback onPipModeChanged updates state and notifies listeners', () async {
      bool listenerNotified = false;
      pipService.isInPipModeNotifier.addListener(() {
        listenerNotified = true;
      });

      // Simulate native callback sending true
      final messageByteData = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onPipModeChanged', true),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channelName,
        messageByteData,
        (ByteData? data) {},
      );

      expect(pipService.isInPipMode, isTrue);
      expect(pipService.isInPipModeNotifier.value, isTrue);
      expect(listenerNotified, isTrue);

      // Simulate native callback sending false
      listenerNotified = false;
      final exitByteData = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onPipModeChanged', false),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channelName,
        exitByteData,
        (ByteData? data) {},
      );

      expect(pipService.isInPipMode, isFalse);
      expect(pipService.isInPipModeNotifier.value, isFalse);
      expect(listenerNotified, isTrue);
    });

    test('updatePlaybackState invokes channel with isPlaying boolean', () async {
      await pipService.updatePlaybackState(true);
      expect(log, hasLength(1));
      expect(log.first.method, 'updatePlaybackState');
      expect(log.first.arguments, {'isPlaying': true});

      await pipService.updatePlaybackState(false);
      expect(log, hasLength(2));
      expect(log.last.method, 'updatePlaybackState');
      expect(log.last.arguments, {'isPlaying': false});
    });

    test('updateScreenShareState invokes channel with isSharing boolean', () async {
      await pipService.updateScreenShareState(true);
      expect(log, hasLength(1));
      expect(log.first.method, 'updateScreenShareState');
      expect(log.first.arguments, {'isSharingLocally': true});

      await pipService.updateScreenShareState(false);
      expect(log, hasLength(2));
      expect(log.last.method, 'updateScreenShareState');
      expect(log.last.arguments, {'isSharingLocally': false});
    });

    test('setPipAspectRatio invokes channel with numerator and denominator', () async {
      await pipService.setPipAspectRatio(9, 16);
      expect(log, hasLength(1));
      expect(log.first.method, 'setPipAspectRatio');
      expect(log.first.arguments, {'numerator': 9, 'denominator': 16});
    });

    test('native callback onPipAction notifies listeners and supports consecutive identical actions', () async {
      final List<String> receivedActions = [];
      pipService.pipActionNotifier.addListener(() {
        final action = pipService.pipActionNotifier.value;
        if (action != null) {
          receivedActions.add(action);
        }
      });

      // Simulate native callback sending 'play'
      final playByteData = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onPipAction', 'play'),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channelName,
        playByteData,
        (ByteData? data) {},
      );

      expect(receivedActions, ['play']);

      // Simulate native callback sending 'play' again (consecutive identical action)
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channelName,
        playByteData,
        (ByteData? data) {},
      );

      expect(receivedActions, ['play', 'play']);

      // Simulate native callback sending 'stop_screenshare'
      final stopByteData = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onPipAction', 'stop_screenshare'),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channelName,
        stopByteData,
        (ByteData? data) {},
      );

      expect(receivedActions, ['play', 'play', 'stop_screenshare']);
    });
  });
}
