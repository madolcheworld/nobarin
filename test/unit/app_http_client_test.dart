import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nobarin/core/network/app_http_client.dart';

void main() {
  group('AppHttpClient Tests', () {
    tearDown(() {
      AppHttpClient.setMockClient(null);
    });

    test('injects default User-Agent header and executes GET successfully', () async {
      final mock = MockClient((request) async {
        expect(request.headers['User-Agent'], contains('NobarinApp'));
        return http.Response(jsonEncode({'success': true}), 200);
      });

      AppHttpClient.setMockClient(mock);

      final res = await AppHttpClient.get(Uri.parse('https://api.example.com/data'));
      expect(res.statusCode, equals(200));
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      expect(decoded['success'], isTrue);
    });

    test('retries on 502/503 transient error and succeeds', () async {
      int calls = 0;
      final mock = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response('Bad Gateway', 502);
        }
        return http.Response('OK', 200);
      });

      AppHttpClient.setMockClient(mock);

      final res = await AppHttpClient.get(
        Uri.parse('https://api.example.com/transient'),
        maxRetries: 1,
      );

      expect(calls, equals(2));
      expect(res.statusCode, equals(200));
    });

    test('does not retry on 404 client error', () async {
      int calls = 0;
      final mock = MockClient((request) async {
        calls++;
        return http.Response('Not Found', 404);
      });

      AppHttpClient.setMockClient(mock);

      final res = await AppHttpClient.get(
        Uri.parse('https://api.example.com/notfound'),
        maxRetries: 2,
      );

      expect(calls, equals(1));
      expect(res.statusCode, equals(404));
    });

    test('POST request correctly forwards body and headers', () async {
      final mock = MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(request.body, equals('{"hello":"world"}'));
        return http.Response('{"created":true}', 201);
      });

      AppHttpClient.setMockClient(mock);

      final res = await AppHttpClient.post(
        Uri.parse('https://api.example.com/create'),
        body: '{"hello":"world"}',
      );

      expect(res.statusCode, equals(201));
    });
  });
}
