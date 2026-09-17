import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nobarin/core/network/local_media_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File sampleVideoFile;
  late LocalMediaServer server;

  setUp(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('nobarin_test_media_');
    sampleVideoFile = File('${tempDir.path}/test_sample.mp4');

    // Create 1000 bytes of dummy video data
    final dummyData = List<int>.generate(1000, (i) => i % 256);
    await sampleVideoFile.writeAsBytes(dummyData);

    server = LocalMediaServer();
  });

  tearDown(() async {
    await server.stop();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LocalMediaServer Tests', () {
    test('starts server and reports streamUrl and loopbackUrl', () async {
      final url = await server.start(
        filePath: sampleVideoFile.path,
        bindToLan: false, // loopback for unit test
        mimeType: 'video/mp4',
      );

      expect(server.isRunning, isTrue);
      expect(server.port, greaterThan(0));
      expect(url, contains('http://127.0.0.1:${server.port}/video'));
      expect(server.loopbackUrl, equals(url));
    });

    test('serves full video file when no Range header is present', () async {
      final url = await server.start(
        filePath: sampleVideoFile.path,
        bindToLan: false,
        mimeType: 'video/mp4',
      );

      final response = await http.get(Uri.parse(url));

      expect(response.statusCode, equals(200));
      expect(response.headers['content-type'], equals('video/mp4'));
      expect(response.headers['accept-ranges'], equals('bytes'));
      expect(response.headers['content-length'], equals('1000'));
      expect(response.bodyBytes.length, equals(1000));
      expect(response.bodyBytes[0], equals(0));
      expect(response.bodyBytes[1], equals(1));
    });

    test('serves 206 Partial Content for Range: bytes=0-99', () async {
      final url = await server.start(
        filePath: sampleVideoFile.path,
        bindToLan: false,
        mimeType: 'video/mp4',
      );

      final response = await http.get(
        Uri.parse(url),
        headers: {'Range': 'bytes=0-99'},
      );

      expect(response.statusCode, equals(206));
      expect(response.headers['content-range'], equals('bytes 0-99/1000'));
      expect(response.headers['content-length'], equals('100'));
      expect(response.headers['accept-ranges'], equals('bytes'));
      expect(response.bodyBytes.length, equals(100));
      expect(response.bodyBytes.first, equals(0));
      expect(response.bodyBytes.last, equals(99));
    });

    test('serves 206 Partial Content for open-ended Range: bytes=500-', () async {
      final url = await server.start(
        filePath: sampleVideoFile.path,
        bindToLan: false,
        mimeType: 'video/mp4',
      );

      final response = await http.get(
        Uri.parse(url),
        headers: {'Range': 'bytes=500-'},
      );

      expect(response.statusCode, equals(206));
      expect(response.headers['content-range'], equals('bytes 500-999/1000'));
      expect(response.headers['content-length'], equals('500'));
      expect(response.bodyBytes.length, equals(500));
      expect(response.bodyBytes.first, equals(500 % 256));
    });

    test('serves HEAD requests with headers but empty body', () async {
      final url = await server.start(
        filePath: sampleVideoFile.path,
        bindToLan: false,
        mimeType: 'video/mp4',
      );

      final response = await http.head(Uri.parse(url));

      expect(response.statusCode, equals(200));
      expect(response.headers['content-length'], equals('1000'));
      expect(response.headers['accept-ranges'], equals('bytes'));
      expect(response.bodyBytes.isEmpty, isTrue);
    });

    test('serves OPTIONS request with CORS headers', () async {
      final url = await server.start(
        filePath: sampleVideoFile.path,
        bindToLan: false,
      );

      final request = http.Request('OPTIONS', Uri.parse(url));
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      expect(response.statusCode, equals(200));
      expect(response.headers['access-control-allow-origin'], equals('*'));
    });

    test('stopping server closes connection and clears state', () async {
      await server.start(filePath: sampleVideoFile.path, bindToLan: false);
      expect(server.isRunning, isTrue);

      await server.stop();
      expect(server.isRunning, isFalse);
      expect(server.port, equals(0));
      expect(server.streamUrl, isNull);
    });
  });
}
