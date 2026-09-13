import 'dart:collection';

class _CacheEntry<T> {
  final T value;
  final DateTime expiresAt;

  _CacheEntry({
    required this.value,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// In-memory LRU and TTL Cache Manager for REST API and network responses.
class ApiCacheManager {
  static ApiCacheManager? _instance;
  static ApiCacheManager get instance => _instance ??= ApiCacheManager();

  /// Maximum number of items in cache before oldest entry is evicted.
  final int maxEntries;

  /// Default TTL if not specified.
  final Duration defaultTtl;

  final LinkedHashMap<String, _CacheEntry<dynamic>> _cache =
      LinkedHashMap<String, _CacheEntry<dynamic>>();

  // Pre-configured standard TTL durations
  static const Duration oEmbedTtl = Duration(minutes: 60);
  static const Duration searchTtl = Duration(minutes: 3);
  static const Duration driveListTtl = Duration(minutes: 2);

  ApiCacheManager({
    this.maxEntries = 250,
    this.defaultTtl = const Duration(minutes: 10),
  });

  /// Allows replacing the singleton instance for unit testing.
  static void setMockInstance(ApiCacheManager? mockInstance) {
    _instance = mockInstance;
  }

  /// Retrieves cached item if present and not expired.
  T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;

    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }

    // Refresh LRU order by moving to end
    _cache.remove(key);
    _cache[key] = entry;

    return entry.value as T?;
  }

  /// Sets item into cache with specified or default TTL.
  void set<T>(String key, T value, {Duration? ttl}) {
    if (value == null) return;

    final duration = ttl ?? defaultTtl;
    final expiresAt = DateTime.now().add(duration);

    // Evict expired entries or oldest entry if limit reached
    if (_cache.length >= maxEntries && !_cache.containsKey(key)) {
      _evictExpiredOrOldest();
    }

    // Remove first to ensure LRU ordering
    _cache.remove(key);
    _cache[key] = _CacheEntry<T>(
      value: value,
      expiresAt: expiresAt,
    );
  }

  /// Checks if key exists and is still valid.
  bool has(String key) {
    return get(key) != null;
  }

  /// Removes a single key.
  void remove(String key) {
    _cache.remove(key);
  }

  /// Removes all keys containing the given pattern or prefix.
  void invalidatePattern(String pattern) {
    final keysToRemove = _cache.keys
        .where((k) => k.contains(pattern))
        .toList();
    for (final k in keysToRemove) {
      _cache.remove(k);
    }
  }

  /// Clears all cached items.
  void clear() {
    _cache.clear();
  }

  int get size => _cache.length;

  void _evictExpiredOrOldest() {
    // 1. First remove any expired entries
    final expiredKeys = _cache.entries
        .where((e) => e.value.isExpired)
        .map((e) => e.key)
        .toList();

    for (final k in expiredKeys) {
      _cache.remove(k);
    }

    // 2. If still at limit, evict the oldest entry (first in LinkedHashMap)
    if (_cache.length >= maxEntries && _cache.isNotEmpty) {
      _cache.remove(_cache.keys.first);
    }
  }
}
