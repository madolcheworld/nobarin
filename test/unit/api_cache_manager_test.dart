import 'package:flutter_test/flutter_test.dart';
import 'package:nobarin/core/network/api_cache_manager.dart';

void main() {
  group('ApiCacheManager Tests', () {
    late ApiCacheManager cache;

    setUp(() {
      cache = ApiCacheManager(
        maxEntries: 3,
        defaultTtl: const Duration(seconds: 1),
      );
    });

    test('stores and retrieves cached items correctly', () {
      cache.set('key1', 'value1');
      expect(cache.get<String>('key1'), equals('value1'));
      expect(cache.has('key1'), isTrue);
    });

    test('returns null for nonexistent keys', () {
      expect(cache.get<String>('missing'), isNull);
      expect(cache.has('missing'), isFalse);
    });

    test('expires items after TTL', () async {
      cache.set('short_lived', 'temp', ttl: const Duration(milliseconds: 50));
      expect(cache.get<String>('short_lived'), equals('temp'));

      await Future.delayed(const Duration(milliseconds: 70));
      expect(cache.get<String>('short_lived'), isNull);
    });

    test('evicts oldest item when maxEntries is exceeded', () {
      cache.set('k1', 'v1');
      cache.set('k2', 'v2');
      cache.set('k3', 'v3');
      expect(cache.size, equals(3));

      // Adding 4th item should evict oldest (k1)
      cache.set('k4', 'v4');
      expect(cache.size, equals(3));
      expect(cache.get<String>('k1'), isNull);
      expect(cache.get<String>('k2'), equals('v2'));
      expect(cache.get<String>('k3'), equals('v3'));
      expect(cache.get<String>('k4'), equals('v4'));
    });

    test('refreshing item moves it to end of LRU', () {
      cache.set('k1', 'v1');
      cache.set('k2', 'v2');
      cache.set('k3', 'v3');

      // Access k1, making it most recently used
      expect(cache.get<String>('k1'), equals('v1'));

      // Adding k4 should now evict k2 instead of k1
      cache.set('k4', 'v4');
      expect(cache.get<String>('k1'), equals('v1'));
      expect(cache.get<String>('k2'), isNull);
      expect(cache.get<String>('k3'), equals('v3'));
      expect(cache.get<String>('k4'), equals('v4'));
    });

    test('invalidatePattern removes matching keys only', () {
      cache.set('yt_search_lofi', ['res1']);
      cache.set('yt_search_anime', ['res2']);
      cache.set('dm_detail_123', 'dailymotion');

      cache.invalidatePattern('yt_search_');
      expect(cache.get('yt_search_lofi'), isNull);
      expect(cache.get('yt_search_anime'), isNull);
      expect(cache.get<String>('dm_detail_123'), equals('dailymotion'));
    });

    test('clear removes all entries', () {
      cache.set('k1', 'v1');
      cache.set('k2', 'v2');
      expect(cache.size, equals(2));

      cache.clear();
      expect(cache.size, equals(0));
      expect(cache.get('k1'), isNull);
    });
  });
}
