/// Centralized input validation and sanitization utility for Nobarin.
/// Provides defense-in-depth sanitization against XSS, injection attacks,
/// malformed remote websocket payloads, and unbounded text inputs.
class InputValidators {
  InputValidators._();

  /// Regex matching zero-width spaces, directional marks, and control characters:
  /// \u200B-\u200D (zero-width space, ZWNJ, ZWJ)
  /// \uFEFF (zero-width no-break space / BOM)
  /// \u00A0 (non-breaking space)
  /// \u202A-\u202E (directional embedding / override)
  static final RegExp zeroWidthRegExp =
      RegExp(r'[\u200B-\u200D\uFEFF\u00A0\u202A-\u202E]');

  /// Cleans hidden zero-width characters and collapses repeated whitespace
  static String sanitizeText(String input) {
    return input
        .replaceAll(zeroWidthRegExp, '')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }

  /// Validates a username / display nickname (2 - 24 characters)
  static String? validateUsername(String? value) {
    if (value == null) {
      return 'Silakan masukkan nama atau nickname kamu';
    }
    final clean = sanitizeText(value);
    if (clean.isEmpty) {
      return 'Silakan masukkan nama atau nickname kamu';
    }
    if (clean.length < 2) {
      return 'Nama pengguna minimal 2 karakter';
    }
    if (clean.length > 24) {
      return 'Nama pengguna maksimal 24 karakter';
    }
    return null;
  }

  /// Validates a room title / room name (2 - 60 characters)
  static String? validateRoomTitle(String? value) {
    if (value == null) {
      return 'Nama room tidak boleh kosong';
    }
    final clean = sanitizeText(value);
    if (clean.isEmpty) {
      return 'Nama room tidak boleh kosong';
    }
    if (clean.length < 2) {
      return 'Nama room minimal 2 karakter';
    }
    if (clean.length > 60) {
      return 'Nama room maksimal 60 karakter';
    }
    return null;
  }

  /// Sanitizes room description to neutralize system metadata injection
  /// (e.g. stripping `[HOST:...]` and `[THUMB:...]`) and bounds length to 300 chars.
  static String sanitizeRoomDescription(String? input) {
    if (input == null || input.isEmpty) return '';
    var clean = input.replaceAll(zeroWidthRegExp, '');
    // Neutralize forged host or thumbnail metadata tags
    clean = clean.replaceAll(
      RegExp(r'\[(HOST|THUMB):[^\]]*\]', caseSensitive: false),
      '',
    );
    clean = clean.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    if (clean.length > 300) {
      clean = clean.substring(0, 300).trim();
    }
    return clean;
  }

  /// Validates room code candidate
  static bool isValidRoomCode(String? value) {
    if (value == null) return false;
    final clean = value.replaceAll('-', '').trim();
    if (clean.length < 3 || clean.length > 12) return false;
    return RegExp(r'^[a-zA-Z0-9]+$').hasMatch(clean);
  }

  /// Sanitizes text chat message:
  /// - Strips invisible zero-width chars
  /// - Enforces 500 characters max limit
  /// - Collapses excessive newlines (max 2 consecutive newlines)
  static String sanitizeChatMessage(String text) {
    var clean = text.replaceAll(zeroWidthRegExp, '').trim();
    if (clean.length > 500) {
      clean = clean.substring(0, 500).trim();
    }
    return clean.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  /// Validates media / video URL syntax and allowed protocols
  static bool isValidMediaUrl(String? url) {
    if (url == null) return false;
    final trimmed = url.trim();
    if (trimmed.isEmpty || trimmed.length > 2048) return false;

    // Local file path patterns
    if (trimmed.startsWith('/') ||
        trimmed.startsWith('file://') ||
        trimmed.startsWith('content://') ||
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed)) {
      return true;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      return false;
    }

    const allowedSchemes = {'http', 'https', 'p2p', 'webbrowser'};
    return allowedSchemes.contains(uri.scheme.toLowerCase());
  }

  /// Sanitizes playback position (seconds) from remote sync packets.
  /// Replaces NaN, Infinity, negative values with safe 0.0, and bounds by max duration.
  static double sanitizePlaybackPosition(double? position, {double? maxDuration}) {
    if (position == null || position.isNaN || position.isInfinite || position < 0.0) {
      return 0.0;
    }
    if (maxDuration != null && maxDuration > 0.0 && position > maxDuration) {
      return maxDuration;
    }
    return position;
  }

  /// Sanitizes playback speed to safe range [0.25, 4.0].
  /// Replaces NaN or Infinity with default 1.0.
  static double sanitizePlaybackSpeed(double? speed) {
    if (speed == null || speed.isNaN || speed.isInfinite) {
      return 1.0;
    }
    return speed.clamp(0.25, 4.0);
  }
}
