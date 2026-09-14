import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_cache_manager.dart';
import '../../../core/network/app_http_client.dart';
import 'models/dailymotion_video_model.dart';

class DailymotionService {
  static final RegExp _dailymotionRegex = RegExp(
    r'(?:https?:\/\/)?(?:www\.)?(?:dailymotion\.com\/(?:video\/|embed\/video\/)|dai\.ly\/)([a-zA-Z0-9]+)',
    caseSensitive: false,
  );

  /// Extract Dailymotion Video ID from URL, iframe embed, or raw alphanumeric ID
  static String? extractVideoId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // Direct alphanumeric ID check (typically starts with x or k, length 4 to 8)
    if (RegExp(r'^[xk][a-zA-Z0-9]{4,8}$', caseSensitive: false).hasMatch(trimmed)) {
      return trimmed;
    }

    final match = _dailymotionRegex.firstMatch(trimmed);
    if (match != null) {
      final id = match.group(1);
      // Remove any extra slugs like _title-slug
      return id?.split('_').first;
    }

    return null;
  }

  /// Curated presets grouped by categories
  static final Map<String, List<DailymotionVideo>> categoryPresets = {
    'Trending': [
      const DailymotionVideo(
        id: 'x7tgad0',
        title: 'Big Buck Bunny - Open Source 3D Animation',
        description: 'Classic open movie project created by the Blender Institute.',
        uploaderName: 'Blender Foundation',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x7tgad0',
        durationSeconds: 596,
        viewsTotal: 1250000,
        category: 'Trending',
      ),
      const DailymotionVideo(
        id: 'x8n6y2p',
        title: 'Tears of Steel - Sci-Fi VFX Short',
        description: 'Open-source VFX movie set in a dystopian Amsterdam.',
        uploaderName: 'Open Movie Lab',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x8n6y2p',
        durationSeconds: 734,
        viewsTotal: 890000,
        category: 'Trending',
      ),
      const DailymotionVideo(
        id: 'x51xwf',
        title: 'Elephants Dream - The First Open Movie',
        description: 'Pioneering open CGI animated short by Orange Open Movie.',
        uploaderName: 'Blender Studio',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x51xwf',
        durationSeconds: 654,
        viewsTotal: 640000,
        category: 'Trending',
      ),
      const DailymotionVideo(
        id: 'x2m8j13',
        title: 'Cosmos Laundromat - First Cycle Short Film',
        description: 'On a desolate island, a suicidal sheep named Franck meets Victor.',
        uploaderName: 'CGI Shorts HQ',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x2m8j13',
        durationSeconds: 728,
        viewsTotal: 520000,
        category: 'Trending',
      ),
    ],
    'Berita & Media': [
      const DailymotionVideo(
        id: 'x8om1t6',
        title: 'Euronews Live - Global Headlines & Top Stories',
        description: 'Latest international news and comprehensive analysis 24/7.',
        uploaderName: 'Euronews',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x8om1t6',
        durationSeconds: 1800,
        viewsTotal: 430000,
        category: 'Berita & Media',
      ),
      const DailymotionVideo(
        id: 'x8zffw8',
        title: 'France 24 English - International News Stream',
        description: 'Round-the-clock international news and perspectives.',
        uploaderName: 'France 24',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x8zffw8',
        durationSeconds: 2400,
        viewsTotal: 380000,
        category: 'Berita & Media',
      ),
      const DailymotionVideo(
        id: 'x8023p2',
        title: 'DW News - Germany & World Daily Digest',
        description: 'German international broadcaster providing insightful reports.',
        uploaderName: 'DW News Official',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x8023p2',
        durationSeconds: 900,
        viewsTotal: 290000,
        category: 'Berita & Media',
      ),
    ],
    'Musik & Klip': [
      const DailymotionVideo(
        id: 'x8j8oqw',
        title: 'Lofi Chill Hop & Ambient Beats',
        description: 'Relaxing instrumental soundscapes for studying and working.',
        uploaderName: 'Chill & Sound',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x8j8oqw',
        durationSeconds: 3600,
        viewsTotal: 780000,
        category: 'Musik & Klip',
      ),
      const DailymotionVideo(
        id: 'x81h552',
        title: 'Electronic Dance Festival Showcase Live',
        description: 'Electric atmosphere and stunning stage visual production.',
        uploaderName: 'EDM Stage',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x81h552',
        durationSeconds: 1240,
        viewsTotal: 410000,
        category: 'Musik & Klip',
      ),
      const DailymotionVideo(
        id: 'x7w8q2s',
        title: 'Acoustic Guitar Sessions & Chill Covers',
        description: 'Warm, unplugged acoustic melodic performance in studio.',
        uploaderName: 'Studio Sessions',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x7w8q2s',
        durationSeconds: 880,
        viewsTotal: 260000,
        category: 'Musik & Klip',
      ),
    ],
    'Olahraga & Aksi': [
      const DailymotionVideo(
        id: 'x891tca',
        title: 'Red Bull Extreme Downhill Mountain Biking',
        description: 'Breathtaking speed and high-stakes stunts on rough mountain trails.',
        uploaderName: 'Action Sports Network',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x891tca',
        durationSeconds: 420,
        viewsTotal: 1540000,
        category: 'Olahraga & Aksi',
      ),
      const DailymotionVideo(
        id: 'x7x9a5m',
        title: 'World Football Best Goals & Incredible Saves',
        description: 'Stunning long-range screamers and acrobatic saves compilation.',
        uploaderName: 'Football Focus',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x7x9a5m',
        durationSeconds: 610,
        viewsTotal: 980000,
        category: 'Olahraga & Aksi',
      ),
      const DailymotionVideo(
        id: 'x8g92lm',
        title: 'Motorsport Speed & Track Drift Highlights',
        description: 'High-octane racing clips and precision cornering.',
        uploaderName: 'Speed Hub',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x8g92lm',
        durationSeconds: 480,
        viewsTotal: 340000,
        category: 'Olahraga & Aksi',
      ),
    ],
    'Film & Animasi': [
      const DailymotionVideo(
        id: 'x82p90z',
        title: 'Sintel - The Durian Open Movie Project',
        description: 'Heartfelt fantasy animation of a girl searching for her pet dragon.',
        uploaderName: 'Blender Animation',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x82p90z',
        durationSeconds: 918,
        viewsTotal: 1100000,
        category: 'Film & Animasi',
      ),
      const DailymotionVideo(
        id: 'x7tgad0',
        title: 'Big Buck Bunny (Full HD 60FPS)',
        description: 'Funny forest adventure with a giant gentle bunny.',
        uploaderName: 'Blender Foundation',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x7tgad0',
        durationSeconds: 596,
        viewsTotal: 1250000,
        category: 'Film & Animasi',
      ),
      const DailymotionVideo(
        id: 'x8n6y2p',
        title: 'Tears of Steel 4K Sci-Fi Film',
        description: 'Futuristic VFX open film short.',
        uploaderName: 'Open Movie Lab',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/x8n6y2p',
        durationSeconds: 734,
        viewsTotal: 890000,
        category: 'Film & Animasi',
      ),
    ],
  };

  /// All preset videos combined
  static List<DailymotionVideo> get allPresets {
    final List<DailymotionVideo> all = [];
    final seenIds = <String>{};
    for (final list in categoryPresets.values) {
      for (final v in list) {
        if (seenIds.add(v.id)) {
          all.add(v);
        }
      }
    }
    return all;
  }

  /// Returns videos for a category
  static List<DailymotionVideo> getPresetsForCategory(String category) {
    if (category.isEmpty || category == 'Semua') {
      return allPresets;
    }
    return categoryPresets[category] ?? allPresets;
  }

  /// Search videos using official public Dailymotion API
  /// Falls back to local preset search if request fails or is offline
  static Future<List<DailymotionVideo>> searchVideos(
    String query, {
    int limit = 15,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return allPresets;
    }

    // Direct URL or Video ID resolution
    final directId = extractVideoId(trimmed);
    if (directId != null &&
        (trimmed.startsWith('http') ||
            trimmed.contains('dailymotion') ||
            trimmed.contains('dai.ly') ||
            RegExp(r'^[xk][a-zA-Z0-9]{5,7}$').hasMatch(trimmed))) {
      final detail = await fetchVideoDetails(directId);
      if (detail != null) {
        return [detail];
      }
    }

    final cacheKey = 'dm_search_${trimmed.toLowerCase()}_limit$limit';
    final cached = ApiCacheManager.instance.get<List<DailymotionVideo>>(cacheKey);
    if (cached != null) {
      return List<DailymotionVideo>.from(cached);
    }

    try {
      final uri = Uri.parse(
        'https://api.dailymotion.com/videos?fields=id,title,description,duration,thumbnail_720_url,owner.screenname,views_total&search=${Uri.encodeComponent(trimmed)}&limit=$limit',
      );

      final response = await AppHttpClient.get(uri, timeout: const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final list = decoded['list'] as List<dynamic>? ?? [];

        final results = <DailymotionVideo>[];
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            results.add(DailymotionVideo.fromJson(item));
          }
        }

        if (results.isNotEmpty) {
          ApiCacheManager.instance.set(cacheKey, results, ttl: ApiCacheManager.searchTtl);
          return results;
        }
      }
    } catch (e) {
      debugPrint('[DailymotionService] Search API error: $e. Using preset fallback.');
    }

    // Fallback: search locally within presets
    final lower = trimmed.toLowerCase();
    final fallback = allPresets.where((video) {
      return video.title.toLowerCase().contains(lower) ||
          video.description.toLowerCase().contains(lower) ||
          video.uploaderName.toLowerCase().contains(lower) ||
          video.category.toLowerCase().contains(lower);
    }).toList();

    if (fallback.isNotEmpty) {
      ApiCacheManager.instance.set(cacheKey, fallback, ttl: ApiCacheManager.searchTtl);
    }

    return fallback;
  }

  /// Search alias for consistency with other services
  static Future<List<DailymotionVideo>> search(
    String query, {
    int limit = 15,
  }) =>
      searchVideos(query, limit: limit);

  /// Fetch single video details by ID or URL
  static Future<DailymotionVideo?> fetchVideoDetails(String input) async {
    final id = extractVideoId(input) ?? input.trim();
    if (id.isEmpty) return null;

    // Check presets first
    for (final v in allPresets) {
      if (v.id.toLowerCase() == id.toLowerCase()) {
        return v;
      }
    }

    final cacheKey = 'dm_detail_$id';
    final cached = ApiCacheManager.instance.get<DailymotionVideo>(cacheKey);
    if (cached != null) {
      return cached;
    }

    try {
      final uri = Uri.parse(
        'https://api.dailymotion.com/video/$id?fields=id,title,description,duration,thumbnail_720_url,owner.screenname,views_total',
      );

      final response = await AppHttpClient.get(uri, timeout: const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final video = DailymotionVideo.fromJson(decoded);
        ApiCacheManager.instance.set(cacheKey, video, ttl: ApiCacheManager.oEmbedTtl);
        return video;
      }
    } catch (e) {
      debugPrint('[DailymotionService] Details API error: $e');
    }

    return DailymotionVideo.fromId(id);
  }
}
