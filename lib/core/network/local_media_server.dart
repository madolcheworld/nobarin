import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Lightweight embedded HTTP server that serves a local video file
/// with full HTTP Range request (206 Partial Content) support.
///
/// This enables:
/// 1. Instant local LAN streaming to other devices on the same Wi-Fi.
/// 2. Local loopback streaming for media players requiring an HTTP endpoint.
class LocalMediaServer {
  HttpServer? _server;
  String? _filePath;
  String? _mimeType;
  int _port = 0;
  String _localIp = '127.0.0.1';

  bool get isRunning => _server != null;
  int get port => _port;
  String get localIp => _localIp;
  String? get filePath => _filePath;

  /// Returns the streaming URL for LAN or local playback
  String? get streamUrl {
    if (!isRunning) return null;
    return 'http://$_localIp:$_port/video';
  }

  /// Returns the loopback URL (127.0.0.1) for local player consumption
  String? get loopbackUrl {
    if (!isRunning) return null;
    return 'http://127.0.0.1:$_port/video';
  }

  /// Starts the HTTP server serving [filePath].
  /// If [bindToLan] is true, binds to `0.0.0.0` so other devices on the network can connect.
  /// Otherwise binds to loopback (`127.0.0.1`).
  Future<String> start({
    required String filePath,
    int port = 0,
    bool bindToLan = true,
    String? mimeType,
  }) async {
    await stop();

    _filePath = filePath;
    _mimeType = mimeType ?? _detectMimeType(filePath);

    if (kIsWeb) {
      throw UnsupportedError('LocalMediaServer is not supported on web.');
    }

    final bindAddress = bindToLan ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4;
    _server = await HttpServer.bind(bindAddress, port);
    _port = _server!.port;

    if (bindToLan) {
      _localIp = await _findLocalIpAddress();
    } else {
      _localIp = '127.0.0.1';
    }

    _server!.listen(_handleRequest, onError: (e) {
      debugPrint('[LocalMediaServer] Server error: $e');
    });

    final url = streamUrl!;
    debugPrint('[LocalMediaServer] Serving $filePath at $url');
    return url;
  }

  /// Stops the server and releases the port.
  Future<void> stop() async {
    if (_server != null) {
      try {
        await _server!.close(force: true);
      } catch (e) {
        debugPrint('[LocalMediaServer] Error stopping server: $e');
      }
      _server = null;
      _port = 0;
      _filePath = null;
    }
  }

  /// Handles incoming HTTP GET, HEAD, and OPTIONS requests
  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;

    // Set CORS headers for multi-device/browser compatibility
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Range, Accept-Ranges, Content-Type');
    response.headers.set('Access-Control-Expose-Headers', 'Content-Range, Content-Length, Accept-Ranges');

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.ok;
      await response.close();
      return;
    }

    if (_filePath == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    final file = File(_filePath!);
    if (!await file.exists()) {
      response.statusCode = HttpStatus.notFound;
      response.write('File not found');
      await response.close();
      return;
    }

    final totalBytes = await file.length();
    final contentType = _mimeType ?? 'video/mp4';

    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.contentTypeHeader, contentType);

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      // Parse Range: bytes=start-end
      final rangeSpec = rangeHeader.substring(6).trim();
      final parts = rangeSpec.split('-');

      int start = 0;
      int end = totalBytes - 1;

      if (parts.length == 2) {
        if (parts[0].isEmpty && parts[1].isNotEmpty) {
          // bytes=-suffix: last N bytes (RFC 7233)
          final suffix = int.tryParse(parts[1]) ?? 0;
          start = (totalBytes - suffix).clamp(0, totalBytes - 1);
          end = totalBytes - 1;
        } else {
          if (parts[0].isNotEmpty) {
            start = int.tryParse(parts[0]) ?? 0;
          }
          if (parts[1].isNotEmpty) {
            end = int.tryParse(parts[1]) ?? (totalBytes - 1);
          }
        }
      }

      // Clamp bounds
      start = start.clamp(0, totalBytes - 1);
      end = end.clamp(start, totalBytes - 1);
      final contentLength = end - start + 1;

      response.statusCode = HttpStatus.partialContent; // 206
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$totalBytes',
      );
      response.headers.set(HttpHeaders.contentLengthHeader, '$contentLength');

      if (request.method == 'HEAD') {
        await response.close();
        return;
      }

      try {
        await response.addStream(file.openRead(start, end + 1));
      } catch (e) {
        // Client might have disconnected/canceled seek
        debugPrint('[LocalMediaServer] Stream error (client cancel/seek): $e');
      } finally {
        try {
          await response.close();
        } catch (_) {}
      }
    } else {
      // Full file response (200 OK)
      response.statusCode = HttpStatus.ok;
      response.headers.set(HttpHeaders.contentLengthHeader, '$totalBytes');

      if (request.method == 'HEAD') {
        await response.close();
        return;
      }

      try {
        await response.addStream(file.openRead());
      } catch (e) {
        debugPrint('[LocalMediaServer] Full stream error: $e');
      } finally {
        try {
          await response.close();
        } catch (_) {}
      }
    }
  }

  /// Discovers the first valid non-loopback IPv4 network interface
  static Future<String> _findLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            // Prefer common private network prefixes: 192.168.x.x, 10.x.x.x, 172.16-31.x.x
            final ip = addr.address;
            if (ip.startsWith('192.168.') ||
                ip.startsWith('10.') ||
                ip.startsWith('172.')) {
              return ip;
            }
          }
        }
      }

      // Fallback: first available non-loopback address
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (e) {
      debugPrint('[LocalMediaServer] Note finding local IP: $e');
    }
    return '127.0.0.1';
  }

  /// Determines MIME type from file extension
  static String _detectMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp4') || lower.endsWith('.m4v')) return 'video/mp4';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.avi')) return 'video/x-msvideo';
    if (lower.endsWith('.ts')) return 'video/mp2t';
    return 'video/mp4';
  }
}
