import 'dart:typed_data';
import '../../models/local_video_file.dart';
import 'p2p_file_reader_web.dart'
    if (dart.library.io) 'p2p_file_reader_io.dart' as impl;

abstract class P2pFileChunkReader {
  Future<void> open();
  Future<Uint8List> readChunk(int start, int length);
  Future<void> close();

  static P2pFileChunkReader create(LocalVideoFile file) {
    return impl.createFileReader(file);
  }
}
