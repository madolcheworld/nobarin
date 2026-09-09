import 'package:flutter_test/flutter_test.dart';
import 'package:watch_party/core/utils/time_formatter.dart';

void main() {
  group('TimeFormatter Tests', () {
    test('formats duration below 1 minute correctly', () {
      expect(TimeFormatter.formatDuration(0), '00:00');
      expect(TimeFormatter.formatDuration(5), '00:05');
      expect(TimeFormatter.formatDuration(59), '00:59');
    });

    test('formats duration with minutes correctly', () {
      expect(TimeFormatter.formatDuration(60), '01:00');
      expect(TimeFormatter.formatDuration(75), '01:15');
      expect(TimeFormatter.formatDuration(599), '09:59');
      expect(TimeFormatter.formatDuration(600), '10:00');
    });

    test('formats duration with hours correctly', () {
      expect(TimeFormatter.formatDuration(3600), '01:00:00');
      expect(TimeFormatter.formatDuration(3665), '01:01:05');
      expect(TimeFormatter.formatDuration(7322), '02:02:02');
    });

    test('handles edge cases: negative, NaN, infinity with custom fallback', () {
      expect(TimeFormatter.formatDuration(-10), '00:00');
      expect(TimeFormatter.formatDuration(0, fallback: 'HD'), 'HD');
      expect(TimeFormatter.formatDuration(double.nan, fallback: 'LIVE'), 'LIVE');
      expect(TimeFormatter.formatDuration(double.infinity), '00:00');
    });

    test('supports unpadded hours with padHours: false', () {
      expect(TimeFormatter.formatDuration(3600, padHours: false), '1:00:00');
      expect(TimeFormatter.formatDuration(3665, padHours: false), '1:01:05');
      expect(TimeFormatter.formatDuration(7322, padHours: false), '2:02:02');
      expect(TimeFormatter.formatDuration(36000, padHours: false), '10:00:00');
    });

    test('formats chat timestamp', () {
      final dt = DateTime(2026, 9, 5, 14, 5);
      expect(TimeFormatter.formatChatTime(dt), '14:05');
    });
  });
}
