import 'dart:math' as math;
import 'dart:typed_data';
import '../../models/local_video_file.dart';
import 'p2p_file_reader.dart';

P2pFileChunkReader createFileReader(LocalVideoFile file) => P2pWebFileChunkReader(file);

class P2pWebFileChunkReader implements P2pFileChunkReader {
  final LocalVideoFile file;

  P2pWebFileChunkReader(this.file);

  @override
  Future<void> open() async {}

  @override
  Future<Uint8List> readChunk(int start, int length) async {
    final bytes = file.bytes;
    if (bytes == null || start >= bytes.length) {
      return Uint8List(0);
    }
    final end = math.min(start + length, bytes.length);
    return bytes.sublist(start, end);
  }

  @override
  Future<void> close() async {}
}
