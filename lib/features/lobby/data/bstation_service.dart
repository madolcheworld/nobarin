import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_cache_manager.dart';
import '../../../core/network/app_http_client.dart';
import 'models/bstation_video_model.dart';

class BstationService {
  static final RegExp _tvVideoRegex = RegExp(
    r'(?:https?:\/\/)?(?:www\.)?bilibili\.tv\/(?:id|en)\/video\/([0-9]+)',
    caseSensitive: false,
  );

  static final RegExp _tvPlayRegex = RegExp(
    r'(?:https?:\/\/)?(?:www\.)?bilibili\.tv\/(?:id|en)\/play\/([0-9]+(?:\/[0-9]+)?)',
    caseSensitive: false,
  );

  static final RegExp _comVideoRegex = RegExp(
    r'(?:https?:\/\/)?(?:www\.)?bilibili\.com\/video\/(BV[a-zA-Z0-9]+|av[0-9]+)',
    caseSensitive: false,
  );

  static final RegExp _shortRegex = RegExp(
    r'(?:https?:\/\/)?b23\.tv\/([a-zA-Z0-9]+)',
    caseSensitive: false,
  );

  /// Extract Bstation/Bilibili Video ID or Play ID from URL or raw ID
  static String? extractVideoId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // 1. Direct BV ID (e.g. BV1xx411c7mD)
    if (RegExp(r'^BV[a-zA-Z0-9]{10}$', caseSensitive: false).hasMatch(trimmed)) {
      return trimmed;
    }

    // 2. Direct Anime Play Path or numeric ID (e.g. 2117053 or 36571/30624556)
    if (RegExp(r'^\d+(?:\/\d+)?$').hasMatch(trimmed)) {
      return trimmed;
    }

    // 3. bilibili.tv /id/play/ or /en/play/ (with optional query params)
    final playMatch = _tvPlayRegex.firstMatch(trimmed);
    if (playMatch != null) {
      return playMatch.group(1);
    }

    // 4. bilibili.tv /id/video/ or /en/video/
    final tvMatch = _tvVideoRegex.firstMatch(trimmed);
    if (tvMatch != null) {
      return tvMatch.group(1);
    }

    // 5. bilibili.com /video/
    final comMatch = _comVideoRegex.firstMatch(trimmed);
    if (comMatch != null) {
      return comMatch.group(1);
    }

    // 6. b23.tv short link
    final shortMatch = _shortRegex.firstMatch(trimmed);
    if (shortMatch != null) {
      return shortMatch.group(1);
    }

    return null;
  }

  /// Curated presets grouped by anime and creative categories
  static final Map<String, List<BstationVideo>> categoryPresets = {
    'Anime Populer': [
      const BstationVideo(
        id: '2117053',
        title: 'Kisah Penggembala Dewa (Tales of Herding Gods)',
        description: 'Di Desa Can Lao yang terpencil, Qin Mu dibesarkan oleh sembilan tetua misterius. Petualangan magis di tanah para dewa yang penuh aksi spektakuler.',
        uploaderName: 'Bstation Anime Hub',
        thumbnailUrl: 'https://pic.bstarstatic.com/ogv/bac6048b713c32beea4a489e6be4a38c.png@720w_405h_1e_1c_90q.webp',
        durationSeconds: 1200,
        viewsTotal: 40100000,
        category: 'Anime Populer',
        episodeNumber: 'EP 01',
      ),
      const BstationVideo(
        id: '36571/30624556',
        title: "A Mortal's Journey to Immortality (Fanren Xiu Xian Chuan)",
        description: 'Perjalanan pemuda desa biasa Han Li melangkah di jalan kultivasi abadi yang penuh bahaya dan intrik.',
        uploaderName: 'Bstation Official',
        thumbnailUrl: 'https://pic.bstarstatic.com/ogv/84b5173bdb997d1d3bf1828fa2a440d4.png',
        durationSeconds: 1320,
        viewsTotal: 56900000,
        category: 'Anime Populer',
        episodeNumber: 'EP 190',
      ),
      const BstationVideo(
        id: '2410921/30654199',
        title: 'Penguasa Tertinggi Sepanjang Masa: Li Yunxiao',
        description: 'Kaisar Bela Diri legendaris bereinkarnasi 15 tahun kemudian dalam tubuh pemuda berbakat yang harus bangkit kembali ke puncak kejayaan.',
        uploaderName: 'Ani-One Asia',
        thumbnailUrl: 'https://pic.bstarstatic.com/ogv/fae86f3b72da36feed0e31d764c2c897.png',
        durationSeconds: 1260,
        viewsTotal: 327000,
        category: 'Anime Populer',
        episodeNumber: 'EP 16',
      ),
      const BstationVideo(
        id: '2315270/26461480',
        title: 'Aliens Among Immortals',
        description: 'Petualangan aksi fiksi ilmiah kultivasi menakjubkan dengan animasi CGI mutakhir.',
        uploaderName: 'Muse Asia',
        thumbnailUrl: 'https://pic.bstarstatic.com/ogv/6e3ac0aee83e74acce24378d8c6b3f3f62240f74.png',
        durationSeconds: 1140,
        viewsTotal: 371000,
        category: 'Anime Populer',
        episodeNumber: 'EP 59',
      ),
      const BstationVideo(
        id: '2411218/30661758',
        title: 'Fabulous Beasts: Season 6 (Wan Sheng Jie)',
        description: 'Kisah komedi kehidupan sehari-hari monster dan iblis lucu yang tinggal bersama di apartemen modern.',
        uploaderName: 'Bstation Premiere',
        thumbnailUrl: 'https://pic.bstarstatic.com/ogv/88c478a9abac1208e9ad20893e14a083.png',
        durationSeconds: 600,
        viewsTotal: 36300,
        category: 'Anime Populer',
        episodeNumber: 'EP 07',
      ),
    ],
    'Trending & Kreator': [
      const BstationVideo(
        id: 'BV1xx411c7mD',
        title: 'Rick Astley - Never Gonna Give You Up (Official Music Video)',
        description: 'Video musik ikonik legendaris di platform Bilibili dengan jutaan pemutaran dan komentar danmaku.',
        uploaderName: 'Rick Astley Official',
        thumbnailUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=800&auto=format&fit=crop&q=80',
        durationSeconds: 213,
        viewsTotal: 89000000,
        category: 'Trending & Kreator',
        episodeNumber: 'MV',
      ),
      const BstationVideo(
        id: 'BV14x411c7A2',
        title: 'Genshin Impact Concert - Melodies of an Endless Journey',
        description: 'Konser simfoni orkestra spektakuler membawakan soundtrack orisinal Teyvat dengan animasi visual memukau.',
        uploaderName: 'Genshin Impact Official',
        thumbnailUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=800&auto=format&fit=crop&q=80',
        durationSeconds: 4200,
        viewsTotal: 1750000,
        category: 'Trending & Kreator',
        episodeNumber: 'LIVE',
      ),
      const BstationVideo(
        id: 'BV1Pt411z7bW',
        title: 'Bilibili ACG World Creator Expo & Cosplay Highlights',
        description: 'Kompilasi keseruan pameran anime, cosplayer profesional, dan pertunjukan panggung terbesar Bilibili.',
        uploaderName: 'Bilibili ACG Channel',
        thumbnailUrl: 'https://images.unsplash.com/photo-1566737236500-c8ac43014a67?w=800&auto=format&fit=crop&q=80',
        durationSeconds: 1120,
        viewsTotal: 960000,
        category: 'Trending & Kreator',
      ),
    ],
    'AMV & Musik': [
      const BstationVideo(
        id: 'BV1b5411b7m7',
        title: 'YOASOBI - Idol (Oshi no Ko OP) Official Animated MV',
        description: 'Video musik animasi lengkap lagu hit sensasional Idol karya YOASOBI untuk serial Oshi no Ko.',
        uploaderName: 'YOASOBI Official Music',
        thumbnailUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=800&auto=format&fit=crop&q=80',
        durationSeconds: 228,
        viewsTotal: 8400000,
        category: 'AMV & Musik',
        episodeNumber: 'MV',
      ),
      const BstationVideo(
        id: 'BV1GJ411x7h7',
        title: 'RADWIMPS feat. Toaka - Suzume Anime Theme Song',
        description: 'Lagu tema emosional film animasi mahakarya Makoto Shinkai "Suzume no Tojimari".',
        uploaderName: 'CoMix Wave Films',
        thumbnailUrl: 'https://images.unsplash.com/photo-1511735111819-9a3f7709049c?w=800&auto=format&fit=crop&q=80',
        durationSeconds: 245,
        viewsTotal: 3650000,
        category: 'AMV & Musik',
        episodeNumber: 'MV',
      ),
      const BstationVideo(
        id: 'BV14b411P7kZ',
        title: 'Aimer - Zankyou Sanka (Demon Slayer Entertainment District OP)',
        description: 'Penampilan memukau video musik Zankyou Sanka dengan nuansa visual gemerlap.',
        uploaderName: 'SACRA MUSIC',
        thumbnailUrl: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=800&auto=format&fit=crop&q=80',
        durationSeconds: 215,
        viewsTotal: 2980000,
        category: 'AMV & Musik',
        episodeNumber: 'MV',
      ),
    ],
    'Komedi & Parodi': [
      const BstationVideo(
        id: 'BV1xx411c7mD',
        title: 'Never Gonna Give You Up - ACG Community Meme Edition',
        description: 'Kompilasi meme legendaris dan parodi animasi terpopuler di komunitas Bilibili.',
        uploaderName: 'Meme ACG Lab',
        thumbnailUrl: 'https://images.unsplash.com/photo-1579783902614-a3fb3927b675?w=800&auto=format&fit=crop&q=80',
        durationSeconds: 430,
        viewsTotal: 2430000,
        category: 'Komedi & Parodi',
      ),
      const BstationVideo(
        id: '2411218/30661758',
        title: 'Fabulous Beasts (Wan Sheng Jie) - Momen Paling Lucu',
        description: 'Kumpulan kelucuan para monster dan iblis di kota metropolitan.',
        uploaderName: 'Anime Fun Corner',
        thumbnailUrl: 'https://images.unsplash.com/photo-1531306728370-e2ebd9d7bb99?w=800&auto=format&fit=crop&q=80',
        durationSeconds: 520,
        viewsTotal: 1870000,
        category: 'Komedi & Parodi',
      ),
    ],
  };

  /// All preset videos combined
  static List<BstationVideo> get allPresets {
    final List<BstationVideo> all = [];
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
  static List<BstationVideo> getPresetsForCategory(String category) {
    if (category.isEmpty || category == 'Semua') {
      return allPresets;
    }
    return categoryPresets[category] ?? allPresets;
  }

  /// Cleans HTML tags, entities, and excessive whitespaces from API strings
  static String _cleanText(String? raw) {
    if (raw == null) return '';
    return raw
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Parses duration string like "0:56" or "10:10" or "01:23:45" into total seconds
  static int _parseDuration(String? str) {
    if (str == null || str.isEmpty) return 0;
    final parts = str.trim().split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return m * 60 + s;
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return h * 3600 + m * 60 + s;
    }
    return 0;
  }

  /// Parses view count string like "446.5M Putar", "6.7K Ditonton", "850 Ditonton" into integer
  static int _parseViewCount(String? str) {
    if (str == null || str.isEmpty) return 0;
    final cleaned = str.replaceAll(',', '.').toUpperCase();
    final match = RegExp(r'([\d\.]+)\s*([KMB])?').firstMatch(cleaned);
    if (match != null) {
      final numVal = double.tryParse(match.group(1) ?? '0') ?? 0.0;
      final unit = match.group(2);
      if (unit == 'B') return (numVal * 1000000000).toInt();
      if (unit == 'M') return (numVal * 1000000).toInt();
      if (unit == 'K') return (numVal * 1000).toInt();
      return numVal.toInt();
    }
    return 0;
  }

  /// Fallback search locally within presets
  static List<BstationVideo> _searchPresets(String query, {int limit = 20}) {
    final lower = query.toLowerCase();
    return allPresets.where((video) {
      return video.title.toLowerCase().contains(lower) ||
          video.description.toLowerCase().contains(lower) ||
          video.uploaderName.toLowerCase().contains(lower) ||
          video.category.toLowerCase().contains(lower) ||
          video.id.toLowerCase().contains(lower);
    }).take(limit).toList();
  }

  /// Search videos using official public Bstation / Bilibili API.
  /// Returns both official anime series/seasons and UGC creator videos.
  /// Falls back to local preset search on failure or when offline.
  static Future<List<BstationVideo>> search(
    String query, {
    int page = 1,
    int pageSize = 20,
    int? limit,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return allPresets;
    }

    // Handle direct URL or direct BV/play ID
    if (cleanQuery.startsWith('http://') ||
        cleanQuery.startsWith('https://') ||
        RegExp(r'^BV[a-zA-Z0-9]{10}$', caseSensitive: false).hasMatch(cleanQuery)) {
      final detail = await fetchVideoDetails(cleanQuery);
      if (detail != null) {
        return [detail];
      }
    }

    final cacheKey = 'bstation_search_${cleanQuery.toLowerCase()}_p${page}_ps$pageSize';
    final cached = ApiCacheManager.instance.get<List<BstationVideo>>(cacheKey);
    if (cached != null) {
      return List<BstationVideo>.from(cached);
    }

    try {
      final uri = Uri.parse(
        'https://api.bilibili.tv/intl/gateway/web/v2/search_v2'
        '?keyword=${Uri.encodeComponent(cleanQuery)}'
        '&pn=$page'
        '&ps=$pageSize'
        '&s_locale=id_ID'
        '&platform=web',
      );

      final response = await AppHttpClient.get(
        uri,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Referer': 'https://www.bilibili.tv/',
          'Accept': 'application/json, text/plain, */*',
        },
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final code = decoded['code'];
        final data = decoded['data'] as Map<String, dynamic>?;

        if (code == 0 && data != null) {
          final modules = data['modules'] as List<dynamic>? ?? [];
          final results = <BstationVideo>[];
          final seenIds = <String>{};

          for (final mod in modules) {
            if (mod is! Map<String, dynamic>) continue;
            final type = mod['type']?.toString();
            final items = mod['items'] as List<dynamic>? ?? [];

            if (type == 'ogv_subject') {
              for (final it in items) {
                if (it is! Map<String, dynamic>) continue;
                final seasons = it['seasons'] as List<dynamic>?;
                if (seasons != null && seasons.isNotEmpty) {
                  for (final s in seasons) {
                    if (s is! Map<String, dynamic>) continue;
                    final seasonId = s['season_id']?.toString() ?? '';
                    if (seasonId.isEmpty || !seenIds.add(seasonId)) continue;

                    final title = _cleanText(s['title']?.toString() ?? '');
                    final cover = s['cover']?.toString() ?? '';
                    final viewStr = s['view']?.toString() ?? '';
                    final desc = _cleanText(s['description']?.toString() ?? '');
                    final indexShow = s['index_show']?.toString();
                    final stylesList = s['styles'] as List<dynamic>?;
                    final styleStr = stylesList
                        ?.map((st) => st['title']?.toString().trim())
                        .where((st) => st != null && st.isNotEmpty)
                        .join(', ');

                    results.add(
                      BstationVideo(
                        id: seasonId,
                        title: title.isNotEmpty ? title : 'Bstation Anime',
                        description: desc,
                        uploaderName: 'Bstation Anime',
                        thumbnailUrl: cover,
                        viewsTotal: _parseViewCount(viewStr),
                        category: (styleStr != null && styleStr.isNotEmpty)
                            ? styleStr
                            : 'Anime Populer',
                        episodeNumber: indexShow,
                      ),
                    );
                  }
                }
              }
            } else if (type == 'ugc') {
              for (final it in items) {
                if (it is! Map<String, dynamic>) continue;
                final aid = it['aid']?.toString() ?? '';
                if (aid.isEmpty || !seenIds.add(aid)) continue;

                final title = _cleanText(it['title']?.toString() ?? '');
                final cover = it['cover']?.toString() ?? '';
                final durationStr = it['duration']?.toString() ?? '';
                final viewStr = it['view']?.toString() ?? '';
                final author = it['author'] as Map<String, dynamic>?;
                final authorName =
                    author?['nickname']?.toString().trim() ?? 'Bstation Creator';

                results.add(
                  BstationVideo(
                    id: aid,
                    title: title.isNotEmpty ? title : 'Bstation Video',
                    uploaderName: authorName.isNotEmpty
                        ? authorName
                        : 'Bstation Creator',
                    thumbnailUrl: cover,
                    durationSeconds: _parseDuration(durationStr),
                    viewsTotal: _parseViewCount(viewStr),
                    category: 'Trending & Kreator',
                  ),
                );
              }
            }
          }

          if (results.isNotEmpty) {
            // Prioritize results whose title contains the search query
            final queryLower = cleanQuery.toLowerCase();
            results.sort((a, b) {
              final aContains = a.title.toLowerCase().contains(queryLower);
              final bContains = b.title.toLowerCase().contains(queryLower);
              if (aContains && !bContains) return -1;
              if (!aContains && bContains) return 1;
              return 0;
            });

            final effectiveResults =
                limit != null ? results.take(limit).toList() : results;
            ApiCacheManager.instance.set(
              cacheKey,
              effectiveResults,
              ttl: ApiCacheManager.searchTtl,
            );
            return effectiveResults;
          }
        }
      }
    } catch (e) {
      debugPrint('[BstationService] Live search error: $e. Falling back to presets.');
    }

    // Fallback: search locally within presets on page 1
    if (page == 1) {
      final fallback = _searchPresets(cleanQuery, limit: limit ?? pageSize);
      if (fallback.isNotEmpty) {
        ApiCacheManager.instance.set(
          cacheKey,
          fallback,
          ttl: ApiCacheManager.searchTtl,
        );
      }
      return fallback;
    }

    return [];
  }

  /// Search videos alias for backward compatibility
  static Future<List<BstationVideo>> searchVideos(
    String query, {
    int page = 1,
    int pageSize = 20,
    int? limit,
  }) =>
      search(query, page: page, pageSize: pageSize, limit: limit);

  /// Fetch single video details by ID or URL
  static Future<BstationVideo?> fetchVideoDetails(String input) async {
    final id = extractVideoId(input) ?? input.trim();
    if (id.isEmpty) return null;

    // Check presets first
    for (final v in allPresets) {
      if (v.id.toLowerCase() == id.toLowerCase()) {
        return v;
      }
    }

    final cacheKey = 'bstation_detail_$id';
    final cached = ApiCacheManager.instance.get<BstationVideo>(cacheKey);
    if (cached != null) {
      return cached;
    }

    final video = BstationVideo.fromId(id);
    ApiCacheManager.instance.set(cacheKey, video, ttl: ApiCacheManager.oEmbedTtl);
    return video;
  }
}
