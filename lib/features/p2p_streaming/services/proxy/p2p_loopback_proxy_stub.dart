import 'dart:typed_data';
import 'p2p_loopback_proxy.dart';

P2pLoopbackProxy createLoopbackProxy() => P2pStubLoopbackProxy();

class P2pStubLoopbackProxy implements P2pLoopbackProxy {
  @override
  int get port => 0;

  @override
  String get streamUrl => '';

  @override
  bool get isRunning => false;

  @override
  Future<void> start({
    required int fileSize,
    required String mimeType,
    required String fileName,
    required ChunkFetcher fetchChunk,
  }) async {}

  @override
  Future<void> stop() async {}
}
