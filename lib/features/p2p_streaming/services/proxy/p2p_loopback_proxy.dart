import 'dart:typed_data';
import 'p2p_loopback_proxy_stub.dart'
    if (dart.library.io) 'p2p_loopback_proxy_io.dart' as impl;

typedef ChunkFetcher = Future<Uint8List> Function(int start, int length);

abstract class P2pLoopbackProxy {
  int get port;
  String get streamUrl;
  bool get isRunning;

  Future<void> start({
    required int fileSize,
    required String mimeType,
    required String fileName,
    required ChunkFetcher fetchChunk,
  });

  Future<void> stop();

  static P2pLoopbackProxy create() => impl.createLoopbackProxy();
}
