import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/core/utils/input_validators.dart';

void main() {
  group('InputValidators Tests', () {
    test('sanitizeText strips zero-width chars and extra whitespace', () {
      final input = '  Alex\u200B \u200C \uFEFF  Popcorn  ';
      final cleaned = InputValidators.sanitizeText(input);
      expect(cleaned, 'Alex Popcorn');
    });

    test('validateUsername enforces constraints', () {
      expect(InputValidators.validateUsername(null), isNotNull);
      expect(InputValidators.validateUsername(''), isNotNull);
      expect(InputValidators.validateUsername('   '), isNotNull);
      expect(InputValidators.validateUsername('\u200B\u200C'), isNotNull);
      expect(InputValidators.validateUsername('a'), isNotNull); // < 2 chars
      expect(InputValidators.validateUsername('Jo'), isNull); // 2 chars valid
      expect(InputValidators.validateUsername('Alex_99'), isNull);
      expect(InputValidators.validateUsername('a' * 24), isNull);
      expect(InputValidators.validateUsername('a' * 25), isNotNull); // > 24 chars
    });

    test('validateRoomTitle enforces constraints', () {
      expect(InputValidators.validateRoomTitle(null), isNotNull);
      expect(InputValidators.validateRoomTitle(''), isNotNull);
      expect(InputValidators.validateRoomTitle('a'), isNotNull);
      expect(InputValidators.validateRoomTitle('Nobar Film'), isNull);
      expect(InputValidators.validateRoomTitle('A' * 60), isNull);
      expect(InputValidators.validateRoomTitle('A' * 61), isNotNull);
    });

    test('sanitizeRoomDescription strips forged metadata tags', () {
      final input = 'Seru banget! [HOST:name=Hacker;id=fake-id-123] [THUMB:http://fake.jpg] nonton bareng';
      final sanitized = InputValidators.sanitizeRoomDescription(input);
      expect(sanitized, 'Seru banget! nonton bareng');
      expect(sanitized.contains('[HOST:'), isFalse);
      expect(sanitized.contains('[THUMB:'), isFalse);

      final longDesc = 'B' * 400;
      final limited = InputValidators.sanitizeRoomDescription(longDesc);
      expect(limited.length, 300);
    });

    test('isValidRoomCode validates code format', () {
      expect(InputValidators.isValidRoomCode('WP1001'), isTrue);
      expect(InputValidators.isValidRoomCode('WP-93X2'), isTrue);
      expect(InputValidators.isValidRoomCode('W'), isFalse); // too short
      expect(InputValidators.isValidRoomCode('WP1001!'), isFalse); // invalid char
      expect(InputValidators.isValidRoomCode('A' * 15), isFalse); // too long
    });

    test('isValidMediaUrl checks protocols and lengths', () {
      expect(InputValidators.isValidMediaUrl('https://youtube.com/watch?v=123'), isTrue);
      expect(InputValidators.isValidMediaUrl('http://example.com/video.mp4'), isTrue);
      expect(InputValidators.isValidMediaUrl('p2p://user1/file.mp4'), isTrue);
      expect(InputValidators.isValidMediaUrl('webbrowser://example.com'), isTrue);
      expect(InputValidators.isValidMediaUrl('/sdcard/video.mp4'), isTrue);
      expect(InputValidators.isValidMediaUrl('file:///video.mp4'), isTrue);

      // Malicious or unsupported protocols
      expect(InputValidators.isValidMediaUrl('javascript:alert(1)'), isFalse);
      expect(InputValidators.isValidMediaUrl('data:text/html;base64,foo'), isFalse);
      expect(InputValidators.isValidMediaUrl('intent://some-intent'), isFalse);
      expect(InputValidators.isValidMediaUrl(''), isFalse);
      expect(InputValidators.isValidMediaUrl('https://example.com/${"a" * 2050}'), isFalse);
    });

    test('sanitizePlaybackPosition protects against NaN, Infinity, negative', () {
      expect(InputValidators.sanitizePlaybackPosition(null), 0.0);
      expect(InputValidators.sanitizePlaybackPosition(double.nan), 0.0);
      expect(InputValidators.sanitizePlaybackPosition(double.infinity), 0.0);
      expect(InputValidators.sanitizePlaybackPosition(double.negativeInfinity), 0.0);
      expect(InputValidators.sanitizePlaybackPosition(-10.5), 0.0);
      expect(InputValidators.sanitizePlaybackPosition(45.2), 45.2);
      expect(InputValidators.sanitizePlaybackPosition(120.0, maxDuration: 100.0), 100.0);
    });

    test('sanitizePlaybackSpeed clamps to safe range and handles NaN', () {
      expect(InputValidators.sanitizePlaybackSpeed(null), 1.0);
      expect(InputValidators.sanitizePlaybackSpeed(double.nan), 1.0);
      expect(InputValidators.sanitizePlaybackSpeed(double.infinity), 1.0);
      expect(InputValidators.sanitizePlaybackSpeed(-2.0), 0.25);
      expect(InputValidators.sanitizePlaybackSpeed(0.1), 0.25);
      expect(InputValidators.sanitizePlaybackSpeed(1.5), 1.5);
      expect(InputValidators.sanitizePlaybackSpeed(10.0), 4.0);
    });

    test('sanitizeChatMessage strips zero-width chars and bounds length', () {
      final msg = 'Halo kawan!\u200B\u200C \n\n\n\n\nApa kabar?';
      final cleaned = InputValidators.sanitizeChatMessage(msg);
      expect(cleaned, 'Halo kawan! \n\nApa kabar?');
      expect(cleaned.contains('\u200B'), isFalse);

      final longMsg = 'X' * 600;
      final bounded = InputValidators.sanitizeChatMessage(longMsg);
      expect(bounded.length, 500);
    });
  });
}
