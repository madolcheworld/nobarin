class TimeFormatter {
  /// Formats seconds to mm:ss or hh:mm:ss
  static String formatDuration(double seconds) {
    if (seconds.isNaN || seconds.isInfinite || seconds <= 0) {
      return '00:00';
    }

    final int totalSeconds = seconds.floor();
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int remainingSeconds = totalSeconds % 60;

    final String minutesStr = minutes.toString().padLeft(2, '0');
    final String secondsStr = remainingSeconds.toString().padLeft(2, '0');

    if (hours > 0) {
      final String hoursStr = hours.toString().padLeft(2, '0');
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
