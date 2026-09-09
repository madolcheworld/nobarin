class TimeFormatter {
  /// Formats seconds to mm:ss or hh:mm:ss.
  /// If seconds <= 0, isNaN, or isInfinite, returns [fallback] (defaults to '00:00').
  /// [padHours] controls whether single-digit hours are padded with leading zero ('01:00:00' vs '1:00:00').
  static String formatDuration(
    double seconds, {
    String fallback = '00:00',
    bool padHours = true,
  }) {
    if (seconds.isNaN || seconds.isInfinite || seconds <= 0) {
      return fallback;
    }

    final int totalSeconds = seconds.floor();
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int remainingSeconds = totalSeconds % 60;

    final String minutesStr = minutes.toString().padLeft(2, '0');
    final String secondsStr = remainingSeconds.toString().padLeft(2, '0');

    if (hours > 0) {
      final String hoursStr =
          padHours ? hours.toString().padLeft(2, '0') : hours.toString();
      return '$hoursStr:$minutesStr:$secondsStr';
    }

    return '$minutesStr:$secondsStr';
  }

  /// Formats a DateTime to a friendly chat timestamp (e.g. "14:32")
  static String formatChatTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
