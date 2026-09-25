import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service managing Picture-in-Picture (PiP) mode interactions
/// with the native platform (Android/iOS/Desktop).
class PipService {
  static final PipService instance = PipService._();

  final MethodChannel _channel;
  final ValueNotifier<bool> isInPipModeNotifier;
  final ValueNotifier<String?> pipActionNotifier;
  final bool _isAndroid;

  bool get isInPipMode => isInPipModeNotifier.value;

  PipService._()
      : _channel = const MethodChannel('watch_party/pip'),
        _isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
        isInPipModeNotifier = ValueNotifier<bool>(false),
        pipActionNotifier = ValueNotifier<String?>(null) {
    _initMethodCallHandler();
  }

  /// Visible for testing to inject mock channel and test environment
  @visibleForTesting
  PipService.withChannel(MethodChannel channel, {this._isAndroid = true})
      : _channel = channel,
        isInPipModeNotifier = ValueNotifier<bool>(false),
        pipActionNotifier = ValueNotifier<String?>(null) {
    _initMethodCallHandler();
  }

  void _initMethodCallHandler() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPipModeChanged':
        final inPip = call.arguments as bool? ?? false;
        if (isInPipModeNotifier.value != inPip) {
          isInPipModeNotifier.value = inPip;
          debugPrint('[PipService] onPipModeChanged: $inPip');
        }
        return null;
      case 'onPipAction':
        final action = call.arguments as String?;
        if (action != null) {
          pipActionNotifier.value = action;
          debugPrint('[PipService] onPipAction: $action');
          // Reset to null immediately so subsequent identical actions (e.g. play -> play) trigger listeners
          pipActionNotifier.value = null;
        }
        return null;
      default:
        return null;
    }
  }

  /// Checks if Picture-in-Picture is supported on the current platform/device.
  Future<bool> isPipSupported() async {
    if (!_isAndroid) return false;

    try {
      final res = await _channel.invokeMethod<bool>('isPipSupported');
      return res ?? false;
    } catch (e) {
      debugPrint('[PipService] isPipSupported error: $e');
      return false;
    }
  }

  /// Enters Picture-in-Picture mode with the specified aspect ratio.
  /// Defaults to standard video 16:9 ratio.
  Future<bool> enterPip({int numerator = 16, int denominator = 9}) async {
    if (!_isAndroid) return false;

    try {
      final res = await _channel.invokeMethod<bool>('enterPip', {
        'numerator': numerator,
        'denominator': denominator,
      });
      final success = res ?? false;
      if (success) {
        // Optimistically set until onPipModeChanged callback confirms
        isInPipModeNotifier.value = true;
      }
      return success;
    } catch (e) {
      debugPrint('[PipService] enterPip error: $e');
      return false;
    }
  }

  /// Configures whether the activity should automatically transition into
  /// Picture-in-Picture mode when the user leaves (e.g. presses Home button).
  Future<void> setAutoEnterPip(bool enabled) async {
    if (!_isAndroid) return;

    try {
      await _channel.invokeMethod('setAutoEnterPip', {'enabled': enabled});
    } catch (e) {
      debugPrint('[PipService] setAutoEnterPip error: $e');
    }
  }

  /// Synchronizes the current media playback state (playing vs paused)
  /// with the native Android Picture-in-Picture action controls.
  Future<void> updatePlaybackState(bool isPlaying) async {
    if (!_isAndroid) return;

    try {
      await _channel.invokeMethod('updatePlaybackState', {'isPlaying': isPlaying});
    } catch (e) {
      debugPrint('[PipService] updatePlaybackState error: $e');
    }
  }

  /// Synchronizes whether the user is actively sharing their screen
  /// so that native PiP controls adapt (e.g. showing "Hentikan Layar" instead of Play/Pause).
  Future<void> updateScreenShareState(bool isSharingLocally) async {
    if (!_isAndroid) return;

    try {
      await _channel.invokeMethod('updateScreenShareState', {
        'isSharingLocally': isSharingLocally,
      });
    } catch (e) {
      debugPrint('[PipService] updateScreenShareState error: $e');
    }
  }

  /// Sets the preferred aspect ratio for Picture-in-Picture mode on native Android.
  Future<void> setPipAspectRatio(int numerator, int denominator) async {
    if (!_isAndroid) return;

    try {
      await _channel.invokeMethod('setPipAspectRatio', {
        'numerator': numerator,
        'denominator': denominator,
      });
    } catch (e) {
      debugPrint('[PipService] setPipAspectRatio error: $e');
    }
  }

  void dispose() {
    isInPipModeNotifier.dispose();
    pipActionNotifier.dispose();
  }
}
