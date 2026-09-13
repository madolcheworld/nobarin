import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import '../../models/local_video_file.dart';
import 'p2p_file_reader.dart';

P2pFileChunkReader createFileReader(LocalVideoFile file) => P2pIoFileChunkReader(file);

class P2pIoFileChunkReader implements P2pFileChunkReader {
  final LocalVideoFile file;
  RandomAccessFile? _raf;

  P2pIoFileChunkReader(this.file);

  @override
  Future<void> open() async {
    if (file.path == null || file.path!.isEmpty) {
      if (file.bytes != null) {
        return;
      }
      throw StateError('File path is required for IO reader');
    }
    final ioFile = File(file.path!);
    _raf = await ioFile.open(mode: FileMode.read);
  }

  @override
  Future<Uint8List> readChunk(int start, int length) async {
    if (file.bytes != null) {
      if (start >= file.bytes!.length) return Uint8List(0);
      final end = math.min(start + length, file.bytes!.length);
      return file.bytes!.sublist(start, end);
    }

    if (_raf == null) {
      await open();
    }
    if (start >= file.size) {
      return Uint8List(0);
    }
    final effectiveLength = math.min(length, file.size - start);
    if (effectiveLength <= 0) {
      return Uint8List(0);
    }

    await _raf!.setPosition(start);
    final bytes = await _raf!.read(effectiveLength);
    return bytes;
  }

  @override
  Future<void> close() async {
    try {
      await _raf?.close();
    } catch (_) {}
    _raf = null;
  }
}
