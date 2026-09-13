import 'dart:async';
import 'package:http/http.dart' as http;

/// Centralized HTTP client providing connection pooling (Keep-Alive),
/// default timeouts, retry mechanism with exponential backoff, and testing injection.
class AppHttpClient {
  static http.Client? _client;

  /// Default timeout for HTTP requests.
  static const Duration defaultTimeout = Duration(seconds: 8);

  /// Standard User-Agent for requests.
  static const String defaultUserAgent =
      'NobarinApp/1.0 (WatchParty Flutter Multiplatform; Linux; Android; iOS)';

  /// Returns active shared [http.Client] with persistent connection pooling.
  static http.Client get client {
    return _client ??= http.Client();
  }

  /// Sets or resets the mock client (useful for unit testing).
  static void setMockClient(http.Client? mockClient) {
    _client = mockClient;
  }

  /// Closes the shared HTTP client and resets it.
  static void close() {
    _client?.close();
    _client = null;
  }

  /// Executes GET request with timeout and automatic retry on transient failure.
  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
    int maxRetries = 1,
  }) async {
    final mergedHeaders = <String, String>{
      'User-Agent': defaultUserAgent,
      ...?headers,
    };

    final effectiveTimeout = timeout ?? defaultTimeout;
    int attempt = 0;

    while (true) {
      attempt++;
      try {
        final response = await client
            .get(url, headers: mergedHeaders)
            .timeout(effectiveTimeout);

        // If server returns transient 5xx error and retries are left, back off and retry
        if (_isTransientStatusCode(response.statusCode) && attempt <= maxRetries) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }

        return response;
      } on TimeoutException {
        if (attempt <= maxRetries) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }
        rethrow;
      } on http.ClientException {
        if (attempt <= maxRetries) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }
        rethrow;
      } catch (e) {
        // Any other non-transient error: rethrow immediately
        rethrow;
      }
    }
  }

  /// Executes POST request with timeout and automatic retry on transient failure.
  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    int maxRetries = 1,
  }) async {
    final mergedHeaders = <String, String>{
      'User-Agent': defaultUserAgent,
      ...?headers,
    };

    final effectiveTimeout = timeout ?? defaultTimeout;
    int attempt = 0;

    while (true) {
      attempt++;
      try {
        final response = await client
            .post(url, headers: mergedHeaders, body: body)
            .timeout(effectiveTimeout);

        if (_isTransientStatusCode(response.statusCode) && attempt <= maxRetries) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }

        return response;
      } on TimeoutException {
        if (attempt <= maxRetries) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }
        rethrow;
      } on http.ClientException {
        if (attempt <= maxRetries) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }
        rethrow;
      } catch (e) {
        rethrow;
      }
    }
  }

  static bool _isTransientStatusCode(int code) {
    return code == 502 || code == 503 || code == 504 || code == 408;
  }
}
