import 'fullscreen_stub.dart'
    if (dart.library.js_interop) 'fullscreen_web.dart' as impl;

/// Cross-platform helper for managing full screen view modes.
class FullscreenHelper {
  /// Whether the browser or window is currently in full screen mode.
  static bool get isFullscreen => impl.isFullscreen();

  /// Toggles full screen mode.
  static void toggleFullscreen() => impl.toggleFullscreen();

  /// Enters full screen mode.
  static Future<void> enterFullscreen() => impl.enterFullscreen();

  /// Exits full screen mode if currently active.
  static Future<void> exitFullscreen() => impl.exitFullscreen();
}
