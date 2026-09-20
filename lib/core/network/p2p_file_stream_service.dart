import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'local_media_server.dart';

/// In-memory LRU cache for P2P video chunks.
/// Keeps memory bounded to [maxSizeBytes] (default 32 MB) to remain mobile-friendly.
class ChunkLruCache {
  final int maxSizeBytes;
  int _currentSizeBytes = 0;
  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap<String, Uint8List>();

  ChunkLruCache({this.maxSizeBytes = 32 * 1024 * 1024});

  int get currentSizeBytes => _currentSizeBytes;
  int get count => _cache.length;

  static String _key(int start, int length) => '$start:$length';

  bool contains(int start, int length) => _cache.containsKey(_key(start, length));

  Uint8List? get(int start, int length) {
    final key = _key(start, length);
    final data = _cache.remove(key);
    if (data != null) {
      _cache[key] = data; // Move to most recently used
      return data;
    }
    return null;
  }

  void put(int start, int length, Uint8List data) {
    if (data.length > maxSizeBytes) return;

    final key = _key(start, length);
    if (_cache.containsKey(key)) {
      _currentSizeBytes -= _cache[key]!.length;
      _cache.remove(key);
    }

    while (_cache.isNotEmpty && (_currentSizeBytes + data.length > maxSizeBytes)) {
      final oldestKey = _cache.keys.first;
      final removed = _cache.remove(oldestKey);
      if (removed != null) {
        _currentSizeBytes -= removed.length;
      }
    }

    _cache[key] = data;
    _currentSizeBytes += data.length;
  }

  void clear() {
    _cache.clear();
    _currentSizeBytes = 0;
  }
}

/// Token to cancel in-flight P2P chunk requests during seek or client disconnect.
class P2PCancellationToken {
  bool _isCancelled = false;
  final Set<int> _activeRequestIds = {};
  void Function(Set<int> cancelledIds)? onCancel;

  bool get isCancelled => _isCancelled;
  Set<int> get activeRequestIds => Set.unmodifiable(_activeRequestIds);

  void register(int id) {
    if (!_isCancelled) {
      _activeRequestIds.add(id);
    }
  }

  void unregister(int id) {
    _activeRequestIds.remove(id);
  }

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    final ids = Set<int>.from(_activeRequestIds);
    _activeRequestIds.clear();
    onCancel?.call(ids);
  }
}

/// Metadata describing a P2P local file stream session in the room
class P2PFileMetadata {
  final String fileName;
  final int fileSize;
  final String mimeType;
  final String? lanUrl;
  final String hostUserId;
  final String? hostUserName;

  const P2PFileMetadata({
    required this.fileName,
    required this.fileSize,
    this.mimeType = 'video/mp4',
    this.lanUrl,
    required this.hostUserId,
    this.hostUserName,
  });

  factory P2PFileMetadata.fromJson(Map<String, dynamic> json) {
    return P2PFileMetadata(
      fileName: json['file_name'] as String? ?? 'Video',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      mimeType: json['mime_type'] as String? ?? 'video/mp4',
      lanUrl: json['lan_url'] as String?,
      hostUserId: json['host_user_id'] as String? ?? '',
      hostUserName: json['host_user_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'file_name': fileName,
      'file_size': fileSize,
      'mime_type': mimeType,
      if (lanUrl != null) 'lan_url': lanUrl,
      'host_user_id': hostUserId,
      if (hostUserName != null) 'host_user_name': hostUserName,
    };
  }

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Service managing P2P direct video streaming from local files across internet or LAN.
class P2PFileStreamService extends ChangeNotifier {
  static final P2PFileStreamService instance = P2PFileStreamService._();

  final LocalMediaServer _localMediaServer;
  final ChunkLruCache chunkCache;

  // Host state
  String? _hostedFilePath;
  P2PFileMetadata? _activeMetadata;
  final Map<String, RTCDataChannel> _hostDataChannels = {};
  RandomAccessFile? _hostRaf;
  Future<void> _hostReadChain = Future.value();
  final Set<int> _hostCancelledRequestIds = {};

  // Viewer state
  HttpServer? _viewerLoopbackServer;
  int _viewerLoopbackPort = 0;
  RTCDataChannel? _viewerDataChannel;
  String? _localOverrideFilePath;
  final Map<int, Completer<Uint8List?>> _pendingChunkRequests = {};
  int _requestIdCounter = 0;

  P2PFileStreamService._({ChunkLruCache? cache})
      : _localMediaServer = LocalMediaServer(),
        chunkCache = cache ?? ChunkLruCache();

  @visibleForTesting
  P2PFileStreamService.withDependencies({
    LocalMediaServer? localMediaServer,
    ChunkLruCache? cache,
  })  : _localMediaServer = localMediaServer ?? LocalMediaServer(),
        chunkCache = cache ?? ChunkLruCache();

  bool get isHosting => _hostedFilePath != null;
  String? get hostedFilePath => _hostedFilePath;
  P2PFileMetadata? get activeMetadata => _activeMetadata;
  String? get localOverrideFilePath => _localOverrideFilePath;
  bool get hasLocalOverride => _localOverrideFilePath != null;
  LocalMediaServer get localMediaServer => _localMediaServer;

  /// Starts hosting a local file on the Host device.
  /// Sets up the LAN HTTP server and prepares for P2P DataChannel chunk requests.
  Future<P2PFileMetadata> hostFile({
    required String filePath,
    required String hostUserId,
    String? hostUserName,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('P2P file streaming from internal storage is not supported on web.');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }

    final totalBytes = await file.length();
    final fileName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'video.mp4';
    final mime = _detectMimeType(fileName);

    // 1. Start LAN server for zero-data local Wi-Fi playback
    String? lanUrl;
    try {
      lanUrl = await _localMediaServer.start(
        filePath: filePath,
        bindToLan: true,
        mimeType: mime,
      );
    } catch (e) {
      debugPrint('[P2PFileStreamService] LAN server start note: $e');
    }

    await _hostRaf?.close();
    _hostRaf = null;
    _hostCancelledRequestIds.clear();

    _hostedFilePath = filePath;
    _activeMetadata = P2PFileMetadata(
      fileName: fileName,
      fileSize: totalBytes,
      mimeType: mime,
      lanUrl: lanUrl,
      hostUserId: hostUserId,
      hostUserName: hostUserName,
    );

    notifyListeners();
    return _activeMetadata!;
  }

  /// Registers a WebRTC DataChannel established between Host and a Viewer.
  void registerHostDataChannel(String peerId, RTCDataChannel channel) {
    _hostDataChannels[peerId] = channel;

    channel.onMessage = (RTCDataChannelMessage message) {
      _handleHostDataChannelMessage(channel, message);
    };

    channel.onDataChannelState = (RTCDataChannelState state) {
      if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _hostDataChannels.remove(peerId);
      }
    };
  }

  /// Handles incoming chunk read and cancel requests from a Viewer over DataChannel.
  Future<void> _handleHostDataChannelMessage(
    RTCDataChannel channel,
    RTCDataChannelMessage message,
  ) async {
    if (!message.isBinary && _hostedFilePath != null) {
      try {
        final data = jsonDecode(message.text) as Map<String, dynamic>;
        final cmd = data['cmd'] as String?;

        if (cmd == 'cancel') {
          final ids = (data['ids'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt());
          if (ids != null) {
            _hostCancelledRequestIds.addAll(ids);
          }
          return;
        }

        if (cmd == 'read') {
          final reqId = (data['id'] as num).toInt();
          final start = (data['start'] as num).toInt();
          final length = (data['length'] as num).toInt();

          if (_hostCancelledRequestIds.remove(reqId)) {
            return; // Cancelled by viewer
          }

          final file = File(_hostedFilePath!);
          if (!await file.exists()) {
            channel.send(RTCDataChannelMessage(jsonEncode({
              'cmd': 'err',
              'id': reqId,
              'msg': 'File not found',
            })));
            return;
          }

          // Backpressure throttling
          if ((channel.bufferedAmount ?? 0) > 256 * 1024) {
            await _throttleHostBackpressure(channel);
          }

          if (_hostCancelledRequestIds.remove(reqId)) {
            return; // Cancelled during backpressure pause
          }

          final chunk = await _readHostChunkSafely(start, length);

          if (_hostCancelledRequestIds.remove(reqId)) {
            return; // Cancelled while reading
          }

          if (chunk.isEmpty) {
            channel.send(RTCDataChannelMessage(jsonEncode({
              'cmd': 'eof',
              'id': reqId,
            })));
          } else {
            // Binary format: 4-byte reqId (big endian) + raw chunk bytes
            final packet = Uint8List(4 + chunk.length);
            final bdata = ByteData.sublistView(packet);
            bdata.setUint32(0, reqId, Endian.big);
            packet.setRange(4, 4 + chunk.length, chunk);

            await channel.send(RTCDataChannelMessage.fromBinary(packet));
          }
        }
      } catch (e) {
        debugPrint('[P2PFileStreamService] Error serving chunk on host: $e');
      }
    }
  }

  /// Safely reads [length] bytes at [start] offset from the hosted file using a serialized queue.
  Future<Uint8List> _readHostChunkSafely(int start, int length) {
    final completer = Completer<Uint8List>();
    _hostReadChain = _hostReadChain.then((_) async {
      try {
        if (_hostedFilePath == null) {
          completer.complete(Uint8List(0));
          return;
        }
        if (_hostRaf == null) {
          final file = File(_hostedFilePath!);
          if (!await file.exists()) {
            completer.complete(Uint8List(0));
            return;
          }
          _hostRaf = await file.open(mode: FileMode.read);
        }
        await _hostRaf!.setPosition(start);
        final data = await _hostRaf!.read(length);
        completer.complete(data);
      } catch (e) {
        debugPrint('[P2PFileStreamService] Host read error: $e');
        completer.complete(Uint8List(0));
      }
    });
    return completer.future;
  }

  /// Pauses host chunk transmission if WebRTC DataChannel send buffer is congested (backpressure).
  Future<void> _throttleHostBackpressure(RTCDataChannel channel) async {
    if ((channel.bufferedAmount ?? 0) <= 128 * 1024) return;

    final completer = Completer<void>();
    channel.bufferedAmountLowThreshold = 64 * 1024;
    final oldCallback = channel.onBufferedAmountLow;

    channel.onBufferedAmountLow = (int currentBuffer) {
      oldCallback?.call(currentBuffer);
      if (!completer.isCompleted) {
        completer.complete();
      }
    };

    await completer.future.timeout(
      const Duration(milliseconds: 200),
      onTimeout: () {},
    );

    channel.onBufferedAmountLow = oldCallback;
  }

  /// Prepares the Viewer to stream from the Host.
  /// Returns the stream URL that should be loaded into [UnifiedPlayerController].
  Future<String> prepareViewerStream({
    required P2PFileMetadata metadata,
    RTCDataChannel? dataChannel,
  }) async {
    // Check if user set local override (Syncplay mode)
    if (_localOverrideFilePath != null) {
      final localFile = File(_localOverrideFilePath!);
      if (await localFile.exists()) {
        debugPrint('[P2PFileStreamService] Using local override file: $_localOverrideFilePath');
        return _localOverrideFilePath!;
      }
    }

    _activeMetadata = metadata;

    // 1. Check if Host LAN URL is reachable (same Wi-Fi)
    if (metadata.lanUrl != null && metadata.lanUrl!.isNotEmpty) {
      final isLanReachable = await _pingUrl(metadata.lanUrl!);
      if (isLanReachable) {
        debugPrint('[P2PFileStreamService] Direct LAN streaming active at: ${metadata.lanUrl}');
        return metadata.lanUrl!;
      }
    }

    // 2. Otherwise, start local loopback server backed by WebRTC DataChannel
    if (dataChannel != null) {
      _viewerDataChannel = dataChannel;
      _setupViewerDataChannel(dataChannel);
    }

    final loopbackUrl = await _startViewerLoopbackServer(metadata);
    return loopbackUrl;
  }

  /// Sets up DataChannel listeners on the Viewer side
  void _setupViewerDataChannel(RTCDataChannel channel) {
    _viewerDataChannel = channel;

    channel.onMessage = (RTCDataChannelMessage message) {
      if (message.isBinary) {
        final bytes = message.binary;
        if (bytes.length >= 4) {
          final bdata = ByteData.sublistView(bytes);
          final reqId = bdata.getUint32(0, Endian.big);
          final chunk = bytes.sublist(4);

          final completer = _pendingChunkRequests.remove(reqId);
          completer?.complete(chunk);
        }
      } else {
        try {
          final data = jsonDecode(message.text) as Map<String, dynamic>;
          final cmd = data['cmd'] as String?;
          final reqId = (data['id'] as num?)?.toInt();

          if (reqId != null && _pendingChunkRequests.containsKey(reqId)) {
            final completer = _pendingChunkRequests.remove(reqId);
            if (cmd == 'eof') {
              completer?.complete(Uint8List(0));
            } else {
              completer?.complete(null);
            }
          }
        } catch (_) {}
      }
    };
  }

  /// Starts the local HTTP loopback server (127.0.0.1) on the Viewer
  Future<String> _startViewerLoopbackServer(P2PFileMetadata metadata) async {
    await stopViewerLoopback();

    if (kIsWeb) {
      throw UnsupportedError('Local loopback is not supported on web.');
    }

    _viewerLoopbackServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _viewerLoopbackPort = _viewerLoopbackServer!.port;

    _viewerLoopbackServer!.listen((request) => _handleViewerLoopbackRequest(request, metadata),
        onError: (e) {
      debugPrint('[P2PFileStreamService] Viewer loopback error: $e');
    });

    final url = 'http://127.0.0.1:$_viewerLoopbackPort/stream.mp4';
    debugPrint('[P2PFileStreamService] Viewer loopback listening at $url');
    return url;
  }

  /// Handles HTTP requests from the local media player to the loopback server
  Future<void> _handleViewerLoopbackRequest(
    HttpRequest request,
    P2PFileMetadata metadata,
  ) async {
    final response = request.response;
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Range, Accept-Ranges, Content-Type');
    response.headers.set('Access-Control-Expose-Headers', 'Content-Range, Content-Length, Accept-Ranges');
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.contentTypeHeader, metadata.mimeType);

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.ok;
      await response.close();
      return;
    }

    final totalBytes = metadata.fileSize;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    int start = 0;
    int end = totalBytes - 1;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final rangeSpec = rangeHeader.substring(6).trim();
      final parts = rangeSpec.split('-');
      if (parts.length == 2) {
        if (parts[0].isNotEmpty) start = int.tryParse(parts[0]) ?? 0;
        if (parts[1].isNotEmpty) end = int.tryParse(parts[1]) ?? (totalBytes - 1);
      }
      start = start.clamp(0, totalBytes - 1);
      end = end.clamp(start, totalBytes - 1);

      response.statusCode = HttpStatus.partialContent; // 206
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$totalBytes',
      );
      response.headers.set(HttpHeaders.contentLengthHeader, '${end - start + 1}');
    } else {
      response.statusCode = HttpStatus.ok;
      response.headers.set(HttpHeaders.contentLengthHeader, '$totalBytes');
    }

    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    final token = P2PCancellationToken();
    token.onCancel = (ids) {
      for (final id in ids) {
        final completer = _pendingChunkRequests.remove(id);
        completer?.complete(null);
      }
      if (ids.isNotEmpty &&
          _viewerDataChannel != null &&
          _viewerDataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
        try {
          _viewerDataChannel!.send(RTCDataChannelMessage(jsonEncode({
            'cmd': 'cancel',
            'ids': ids.toList(),
          })));
        } catch (_) {}
      }
    };

    const chunkSize = 32 * 1024;
    final chunkStream = streamRangePipelined(
      start: start,
      end: end,
      token: token,
      chunkSize: chunkSize,
      windowSize: 6,
    );

    try {
      await for (final chunk in chunkStream) {
        if (token.isCancelled) break;
        response.add(chunk);
        await response.flush();
      }
    } catch (e) {
      debugPrint('[P2PFileStreamService] Error piping chunk to player: $e');
    } finally {
      token.cancel();
      try {
        await response.close();
      } catch (_) {}
    }
  }

  /// Streams byte range [start]..[end] using a Credit-Based Sliding Window
  /// pipelining up to [windowSize] chunks in parallel over WebRTC DataChannel.
  Stream<Uint8List> streamRangePipelined({
    required int start,
    required int end,
    required P2PCancellationToken token,
    int chunkSize = 32 * 1024,
    int windowSize = 6,
  }) async* {
    final totalBytes = end - start + 1;
    if (totalBytes <= 0) return;
    final numChunks = (totalBytes / chunkSize).ceil();

    final Map<int, Future<Uint8List?>> inFlight = {};
    int nextDispatchIndex = 0;

    void dispatch(int index) {
      final cStart = start + index * chunkSize;
      final cEnd = (cStart + chunkSize - 1).clamp(cStart, end);
      final cLen = cEnd - cStart + 1;

      // 1. Check LRU Cache (0 ms instant return)
      final cached = chunkCache.get(cStart, cLen);
      if (cached != null) {
        inFlight[index] = Future.value(cached);
        return;
      }

      // 2. Request over DataChannel with cancellation token
      inFlight[index] = _requestChunkFromHostWithToken(
        start: cStart,
        length: cLen,
        token: token,
      ).then((data) {
        if (data != null && data.isNotEmpty) {
          chunkCache.put(cStart, cLen, data);
        }
        return data;
      });
    }

    // Pre-fill sliding window
    while (nextDispatchIndex < numChunks && nextDispatchIndex < windowSize) {
      if (token.isCancelled) break;
      dispatch(nextDispatchIndex);
      nextDispatchIndex++;
    }

    // Sequentially assemble and yield chunks in exact order
    for (int i = 0; i < numChunks; i++) {
      if (token.isCancelled) break;

      // Keep pipeline saturated: dispatch next chunk in window
      while (nextDispatchIndex < numChunks && (nextDispatchIndex - i) < windowSize) {
        dispatch(nextDispatchIndex);
        nextDispatchIndex++;
      }

      final future = inFlight.remove(i);
      if (future == null) break;

      final chunk = await future;
      if (token.isCancelled) break;
      if (chunk == null || chunk.isEmpty) {
        break;
      }

      yield chunk;
    }
  }

  /// Sends a chunk request over WebRTC DataChannel to the Host with a cancellation token
  Future<Uint8List?> _requestChunkFromHostWithToken({
    required int start,
    required int length,
    required P2PCancellationToken token,
  }) async {
    if (token.isCancelled) return null;
    if (_viewerDataChannel == null ||
        _viewerDataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      return null;
    }

    final reqId = ++_requestIdCounter;
    final completer = Completer<Uint8List?>();
    _pendingChunkRequests[reqId] = completer;
    token.register(reqId);

    try {
      await _viewerDataChannel!.send(RTCDataChannelMessage(jsonEncode({
        'cmd': 'read',
        'id': reqId,
        'start': start,
        'length': length,
      })));

      final result = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _pendingChunkRequests.remove(reqId);
          token.unregister(reqId);
          return null;
        },
      );
      token.unregister(reqId);
      return result;
    } catch (e) {
      _pendingChunkRequests.remove(reqId);
      token.unregister(reqId);
      return null;
    }
  }

  /// Sends a chunk request over WebRTC DataChannel to the Host and awaits the response
  @visibleForTesting
  Future<Uint8List?> requestChunkFromHost(int start, int length) {
    return _requestChunkFromHostWithToken(
      start: start,
      length: length,
      token: P2PCancellationToken(),
    );
  }

  /// Sets local file override (Syncplay mode) for this viewer
  void setLocalOverride(String? path) {
    _localOverrideFilePath = path;
    notifyListeners();
  }

  /// Clears local override
  void clearLocalOverride() {
    _localOverrideFilePath = null;
    notifyListeners();
  }

  /// Stops viewer loopback server
  Future<void> stopViewerLoopback() async {
    if (_viewerLoopbackServer != null) {
      try {
        await _viewerLoopbackServer!.close(force: true);
      } catch (_) {}
      _viewerLoopbackServer = null;
      _viewerLoopbackPort = 0;
    }
    _pendingChunkRequests.clear();
  }

  /// Stops all hosting and streaming activities
  Future<void> reset() async {
    await _localMediaServer.stop();
    await stopViewerLoopback();
    await _hostRaf?.close();
    _hostRaf = null;
    _hostCancelledRequestIds.clear();
    chunkCache.clear();
    _hostedFilePath = null;
    _activeMetadata = null;
    _localOverrideFilePath = null;
    _hostDataChannels.clear();
    _viewerDataChannel = null;
    notifyListeners();
  }

  /// Quick ping to check if a URL is reachable
  static Future<bool> _pingUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final client = http.Client();
      try {
        final response = await client.head(uri).timeout(
              const Duration(milliseconds: 1500),
            );
        return response.statusCode == 200 || response.statusCode == 206;
      } finally {
        client.close();
      }
    } catch (_) {
      return false;
    }
  }

  static String _detectMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp4') || lower.endsWith('.m4v')) return 'video/mp4';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.avi')) return 'video/x-msvideo';
    return 'video/mp4';
  }
}
