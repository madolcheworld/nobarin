import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/core/network/p2p_file_stream_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChunkLruCache Tests', () {
    test('put and get returns cached chunk', () {
      final cache = ChunkLruCache(maxSizeBytes: 1024);
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);

      expect(cache.contains(0, 5), isFalse);
      cache.put(0, 5, data);
      expect(cache.contains(0, 5), isTrue);
      expect(cache.count, equals(1));
      expect(cache.currentSizeBytes, equals(5));

      final retrieved = cache.get(0, 5);
      expect(retrieved, equals(data));
    });

    test('get of non-existent key returns null', () {
      final cache = ChunkLruCache(maxSizeBytes: 1024);
      expect(cache.get(100, 50), isNull);
    });

    test('evicts oldest entries when maxSizeBytes is exceeded', () {
      // 100 bytes capacity
      final cache = ChunkLruCache(maxSizeBytes: 100);

      final chunk1 = Uint8List(40); // 0-40
      final chunk2 = Uint8List(40); // 40-40
      final chunk3 = Uint8List(40); // 80-40

      cache.put(0, 40, chunk1);
      cache.put(40, 40, chunk2);
      expect(cache.count, equals(2));
      expect(cache.currentSizeBytes, equals(80));

      // Adding chunk3 (40 bytes) makes 120 > 100, so chunk1 (oldest) must be evicted
      cache.put(80, 40, chunk3);
      expect(cache.count, equals(2));
      expect(cache.currentSizeBytes, equals(80));
      expect(cache.contains(0, 40), isFalse);
      expect(cache.contains(40, 40), isTrue);
      expect(cache.contains(80, 40), isTrue);
    });

    test('get updates LRU access order to prevent eviction of recently accessed items', () {
      final cache = ChunkLruCache(maxSizeBytes: 100);

      final chunk1 = Uint8List(40);
      final chunk2 = Uint8List(40);
      final chunk3 = Uint8List(40);

      cache.put(0, 40, chunk1);
      cache.put(40, 40, chunk2);

      // Access chunk1, making chunk2 the least recently used
      final got = cache.get(0, 40);
      expect(got, isNotNull);

      // Add chunk3 -> chunk2 should be evicted, chunk1 preserved
      cache.put(80, 40, chunk3);
      expect(cache.contains(40, 40), isFalse);
      expect(cache.contains(0, 40), isTrue);
      expect(cache.contains(80, 40), isTrue);
    });

    test('re-inserting same key updates value and size without duplicating', () {
      final cache = ChunkLruCache(maxSizeBytes: 100);

      cache.put(0, 20, Uint8List(20));
      expect(cache.count, equals(1));
      expect(cache.currentSizeBytes, equals(20));

      cache.put(0, 20, Uint8List(35));
      expect(cache.count, equals(1));
      expect(cache.currentSizeBytes, equals(35));
    });

    test('items larger than maxSizeBytes are rejected', () {
      final cache = ChunkLruCache(maxSizeBytes: 50);
      cache.put(0, 100, Uint8List(100));
      expect(cache.count, equals(0));
      expect(cache.currentSizeBytes, equals(0));
    });

    test('clear resets count and currentSizeBytes', () {
      final cache = ChunkLruCache(maxSizeBytes: 1024);
      cache.put(0, 10, Uint8List(10));
      cache.put(10, 20, Uint8List(20));
      expect(cache.count, equals(2));

      cache.clear();
      expect(cache.count, equals(0));
      expect(cache.currentSizeBytes, equals(0));
      expect(cache.get(0, 10), isNull);
    });
  });

  group('P2PCancellationToken Tests', () {
    test('tracks active request IDs and cancels them on cancel()', () {
      final token = P2PCancellationToken();
      expect(token.isCancelled, isFalse);

      token.register(1);
      token.register(2);
      token.register(3);
      token.unregister(2);

      expect(token.activeRequestIds, equals({1, 3}));

      Set<int>? notifiedIds;
      token.onCancel = (ids) {
        notifiedIds = ids;
      };

      token.cancel();
      expect(token.isCancelled, isTrue);
      expect(notifiedIds, equals({1, 3}));
      expect(token.activeRequestIds, isEmpty);

      // Second cancel() is no-op
      notifiedIds = null;
      token.cancel();
      expect(notifiedIds, isNull);
    });

    test('registering after cancel() does not add IDs', () {
      final token = P2PCancellationToken();
      token.cancel();
      token.register(99);
      expect(token.activeRequestIds, isEmpty);
    });
  });

  group('P2PFileStreamService Sliding Window & Cache Integration Tests', () {
    late Directory tempDir;
    late File sampleFile;
    late P2PFileStreamService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('p2p_pipeline_test_');
      sampleFile = File('${tempDir.path}/test_stream.bin');
      // Create a 256 KB file with known byte patterns
      final bytes = Uint8List(256 * 1024);
      for (int i = 0; i < bytes.length; i++) {
        bytes[i] = i % 256;
      }
      await sampleFile.writeAsBytes(bytes);

      service = P2PFileStreamService.withDependencies();
    });

    tearDown(() async {
      await service.reset();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('streamRangePipelined serves cached chunks instantly in order', () async {
      // Pre-seed cache with 2 chunks (each 64 KB)
      final chunk0 = Uint8List.fromList(List.generate(64 * 1024, (i) => 1));
      final chunk1 = Uint8List.fromList(List.generate(64 * 1024, (i) => 2));

      service.chunkCache.put(0, 64 * 1024, chunk0);
      service.chunkCache.put(64 * 1024, 64 * 1024, chunk1);

      final token = P2PCancellationToken();
      final chunks = <Uint8List>[];

      // Stream range covering both chunks: 0 to 128 KB - 1
      await for (final chunk in service.streamRangePipelined(
        start: 0,
        end: (128 * 1024) - 1,
        token: token,
        chunkSize: 64 * 1024,
        windowSize: 4,
      )) {
        chunks.add(chunk);
      }

      expect(chunks.length, equals(2));
      expect(chunks[0], equals(chunk0));
      expect(chunks[1], equals(chunk1));
    });

    test('streamRangePipelined aborts when token is cancelled', () async {
      // Pre-seed 5 chunks
      for (int i = 0; i < 5; i++) {
        service.chunkCache.put(
          i * 64 * 1024,
          64 * 1024,
          Uint8List(64 * 1024),
        );
      }

      final token = P2PCancellationToken();
      final chunks = <Uint8List>[];

      final stream = service.streamRangePipelined(
        start: 0,
        end: (5 * 64 * 1024) - 1,
        token: token,
        chunkSize: 64 * 1024,
        windowSize: 2,
      );

      await for (final chunk in stream) {
        chunks.add(chunk);
        if (chunks.length == 2) {
          token.cancel(); // Abort after 2 chunks
        }
      }

      // Stream stopped early due to cancellation
      expect(chunks.length, equals(2));
      expect(token.isCancelled, isTrue);
    });

    test('hostFile enables reading chunks safely and sequentially', () async {
      await service.hostFile(
        filePath: sampleFile.path,
        hostUserId: 'host-user-1',
      );

      expect(service.isHosting, isTrue);

      // Verify reset properly clears cache and hosting state
      service.chunkCache.put(0, 100, Uint8List(100));
      expect(service.chunkCache.count, equals(1));

      await service.reset();
      expect(service.isHosting, isFalse);
      expect(service.chunkCache.count, equals(0));
    });
  });
}
