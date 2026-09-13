import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'p2p_loopback_proxy.dart';

P2pLoopbackProxy createLoopbackProxy() => P2pIoLoopbackProxy();

class P2pIoLoopbackProxy implements P2pLoopbackProxy {
  HttpServer? _server;
  int _port = 0;
  bool _isRunning = false;
  int _fileSize = 0;
  String _mimeType = 'video/mp4';
  String _fileName = 'p2p_stream.mp4';
  ChunkFetcher? _fetchChunk;

  @override
  int get port => _port;

  @override
  String get streamUrl => 'http://127.0.0.1:$_port/$_fileName';

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> start({
    required int fileSize,
    required String mimeType,
    required String fileName,
    required ChunkFetcher fetchChunk,
  }) async {
    await stop();

    _fileSize = fileSize;
    _mimeType = mimeType;
    _fileName = fileName.replaceAll(RegExp(r'[^\w\.-]'), '_');
    if (_fileName.isEmpty) _fileName = 'p2p_stream.mp4';
    _fetchChunk = fetchChunk;

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _isRunning = true;

    _server!.listen(_handleRequest, onError: (err) {
      debugPrint('[P2pLoopbackProxy] Server error: $err');
    });
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Range, Accept-Ranges, Content-Type');

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.ok;
      await response.close();
      return;
    }

    if (request.uri.path == '/ping') {
      response.statusCode = HttpStatus.ok;
      response.write('pong');
      await response.close();
      return;
    }

    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.contentTypeHeader, _mimeType);

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    int start = 0;
    int end = _fileSize > 0 ? _fileSize - 1 : 0;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final parts = rangeHeader.substring(6).split('-');
      if (parts.isNotEmpty && parts[0].isNotEmpty) {
        start = int.tryParse(parts[0]) ?? 0;
      }
      if (parts.length > 1 && parts[1].isNotEmpty) {
        end = int.tryParse(parts[1]) ?? end;
      }
      if (end >= _fileSize && _fileSize > 0) {
        end = _fileSize - 1;
      }

      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$_fileSize',
      );
      response.contentLength = (end - start + 1);
    } else {
      response.statusCode = HttpStatus.ok;
      response.contentLength = _fileSize;
    }

    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    int currentOffset = start;
    const int fetchChunkSize = 64 * 1024;

    try {
      while (currentOffset <= end && _isRunning) {
        final toRead = math.min(fetchChunkSize, end - currentOffset + 1);
        final chunk = await _fetchChunk!(currentOffset, toRead);
        if (chunk.isEmpty) break;

        response.add(chunk);
        await response.flush();
        currentOffset += chunk.length;
      }
    } catch (e) {
      // Seek or connection close by player
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _port = 0;
  }
}
