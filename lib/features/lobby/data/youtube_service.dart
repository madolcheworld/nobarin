import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_cache_manager.dart';
import '../../../core/network/app_http_client.dart';
import 'models/youtube_video_model.dart';

class YouTubeService {
  static final RegExp _ytVideoIdRegex = RegExp(
    r'(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|watch\?v=|watch\?.+&v=|shorts\/))([\w-]{11})',
    caseSensitive: false,
  );

  static String? extractVideoId(String input) {
    final trimmed = input.trim();
    if (trimmed.length == 11 && RegExp(r'^[\w-]{11}$').hasMatch(trimmed)) {
      return trimmed;
    }
    final match = _ytVideoIdRegex.firstMatch(trimmed);
    return match?.group(1);
  }

  /// Preset terkurasi berbagai kategori agar tampilan awal selalu penuh konten menarik
  static final Map<String, List<YouTubeVideo>> categoryPresets = {
    'Trending': [
      const YouTubeVideo(
        id: 'dQw4w9WgXcQ',
        title: 'Rick Astley - Never Gonna Give You Up (Official Music Video)',
        channelTitle: 'Rick Astley',
        thumbnailUrl: 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        duration: '03:33',
      ),
      const YouTubeVideo(
        id: 'jfKfPfyJRdk',
        title: 'lofi hip hop radio 📚 - beats to relax/study to',
        channelTitle: 'Lofi Girl',
        thumbnailUrl: 'https://img.youtube.com/vi/jfKfPfyJRdk/hqdefault.jpg',
        duration: 'LIVE',
      ),
      const YouTubeVideo(
        id: 'QdBZY2fkU-0',
        title: 'Marvel Studios Deadpool & Wolverine | Official Trailer',
        channelTitle: 'Marvel Entertainment',
        thumbnailUrl: 'https://img.youtube.com/vi/QdBZY2fkU-0/hqdefault.jpg',
        duration: '02:38',
      ),
      const YouTubeVideo(
        id: 'QdX1wU9-4jE',
        title: 'Grand Theft Auto VI Trailer 1',
        channelTitle: 'Rockstar Games',
        thumbnailUrl: 'https://img.youtube.com/vi/QdX1wU9-4jE/hqdefault.jpg',
        duration: '01:31',
      ),
    ],
    'Musik & Lo-Fi': [
      const YouTubeVideo(
        id: 'jfKfPfyJRdk',
        title: 'lofi hip hop radio 📚 - beats to relax/study to',
        channelTitle: 'Lofi Girl',
        thumbnailUrl: 'https://img.youtube.com/vi/jfKfPfyJRdk/hqdefault.jpg',
        duration: 'LIVE',
      ),
      const YouTubeVideo(
        id: '4xDzrJKXOOY',
        title: 'synthwave radio 🌌 - beats to chill/game to',
        channelTitle: 'Lofi Girl',
        thumbnailUrl: 'https://img.youtube.com/vi/4xDzrJKXOOY/hqdefault.jpg',
        duration: 'LIVE',
      ),
      const YouTubeVideo(
        id: 'kXYiU_JCYtU',
        title: 'Numb [Official Music Video] - Linkin Park',
        channelTitle: 'Linkin Park',
        thumbnailUrl: 'https://img.youtube.com/vi/kXYiU_JCYtU/hqdefault.jpg',
        duration: '03:07',
      ),
      const YouTubeVideo(
        id: 'JGwWNGJdvx8',
        title: 'Ed Sheeran - Shape of You (Official Music Video)',
        channelTitle: 'Ed Sheeran',
        thumbnailUrl: 'https://img.youtube.com/vi/JGwWNGJdvx8/hqdefault.jpg',
        duration: '04:23',
      ),
    ],
    'Trailer Film': [
      const YouTubeVideo(
        id: 'QdBZY2fkU-0',
        title: 'Marvel Studios Deadpool & Wolverine | Official Trailer',
        channelTitle: 'Marvel Entertainment',
        thumbnailUrl: 'https://img.youtube.com/vi/QdBZY2fkU-0/hqdefault.jpg',
        duration: '02:38',
      ),
      const YouTubeVideo(
        id: 'd9MyW72ELq0',
        title: 'Avatar: The Way of Water | Official Trailer',
        channelTitle: '20th Century Studios',
        thumbnailUrl: 'https://img.youtube.com/vi/d9MyW72ELq0/hqdefault.jpg',
        duration: '02:29',
      ),
      const YouTubeVideo(
        id: 'TcMBFSGVi1c',
        title: 'Avengers: Endgame - Official Trailer',
        channelTitle: 'Marvel Entertainment',
        thumbnailUrl: 'https://img.youtube.com/vi/TcMBFSGVi1c/hqdefault.jpg',
        duration: '02:26',
      ),
      const YouTubeVideo(
        id: 'Way9Dexny3w',
        title: 'Dune: Part Two | Official Trailer',
        channelTitle: 'Warner Bros. Pictures',
        thumbnailUrl: 'https://img.youtube.com/vi/Way9Dexny3w/hqdefault.jpg',
        duration: '03:02',
      ),
    ],
    'Anime': [
      const YouTubeVideo(
        id: 'bQtb0sU_FvE',
        title: 'Attack on Titan Final Season THE FINAL CHAPTERS Official Trailer',
        channelTitle: 'Crunchyroll',
        thumbnailUrl: 'https://img.youtube.com/vi/bQtb0sU_FvE/hqdefault.jpg',
        duration: '01:30',
      ),
      const YouTubeVideo(
        id: 'pkZXUF_Uu10',
        title: 'JUJUTSU KAISEN Season 2 Shibuya Incident Official Trailer',
        channelTitle: 'TOHO animation',
        thumbnailUrl: 'https://img.youtube.com/vi/pkZXUF_Uu10/hqdefault.jpg',
        duration: '01:45',
      ),
      const YouTubeVideo(
        id: 't6MXHsebwUY',
        title: 'Demon Slayer: Kimetsu no Yaiba Hashira Training Arc Trailer',
        channelTitle: 'Aniplex USA',
        thumbnailUrl: 'https://img.youtube.com/vi/t6MXHsebwUY/hqdefault.jpg',
        duration: '02:00',
      ),
      const YouTubeVideo(
        id: 'V1PL8CzNzCw',
        title: 'Chainsaw Man – Main Trailer / Chainsaw Man Official',
        channelTitle: 'MAPPA CHANNEL',
        thumbnailUrl: 'https://img.youtube.com/vi/V1PL8CzNzCw/hqdefault.jpg',
        duration: '01:34',
      ),
    ],
    'Gaming': [
      const YouTubeVideo(
        id: 'QdX1wU9-4jE',
        title: 'Grand Theft Auto VI Trailer 1',
        channelTitle: 'Rockstar Games',
        thumbnailUrl: 'https://img.youtube.com/vi/QdX1wU9-4jE/hqdefault.jpg',
        duration: '01:31',
      ),
      const YouTubeVideo(
        id: 'MmB9b5njVbA',
        title: 'Minecraft Official Trailer',
        channelTitle: 'Minecraft',
        thumbnailUrl: 'https://img.youtube.com/vi/MmB9b5njVbA/hqdefault.jpg',
        duration: '01:21',
      ),
      const YouTubeVideo(
        id: 'e_E9W2vsRbA',
        title: 'ELDEN RING Shadow of the Erdtree – Official Gameplay Reveal',
        channelTitle: 'BANDAI NAMCO Europe',
        thumbnailUrl: 'https://img.youtube.com/vi/e_E9W2vsRbA/hqdefault.jpg',
        duration: '03:06',
      ),
    ],
    'Animasi / Kartun': [
      const YouTubeVideo(
        id: 'aqz-KE-bpKQ',
        title: 'Big Buck Bunny 4K 60fps (Open Source Blender Animation)',
        channelTitle: 'Blender Foundation',
        thumbnailUrl: 'https://img.youtube.com/vi/aqz-KE-bpKQ/hqdefault.jpg',
        duration: '10:34',
      ),
      const YouTubeVideo(
        id: 'e-ORhEE9VVg',
        title: 'Sintel - Third Open Movie by Blender Foundation',
        channelTitle: 'Blender Foundation',
        thumbnailUrl: 'https://img.youtube.com/vi/e-ORhEE9VVg/hqdefault.jpg',
        duration: '14:48',
      ),
    ],
  };

  static String _getQueryForPage(String query, int page) {
    if (page <= 1) return query;
    final lower = query.toLowerCase();
    if (lower.contains('trending')) {
      if (page == 2) return 'trending musik dan hiburan viral';
      if (page == 3) return 'trending live stream gaming musik';
      return 'trending video indonesia populer';
    }
    if (lower.contains('trailer') || lower.contains('film')) {
      if (page == 2) return 'official movie trailers 2024 2025';
      if (page == 3) return 'film bioskop trailer terbaru indonesia';
      return 'hollywood teaser trailer 4k';
    }
    if (lower.contains('lo-fi') || lower.contains('lofi') || lower.contains('musik')) {
      if (page == 2) return 'lofi hip hop beats study relax live';
      if (page == 3) return 'music playlist chill acoustic pop';
      return 'synthwave chill gaming radio';
    }
    if (lower.contains('anime')) {
      if (page == 2) return 'anime official teaser trailer clip';
      if (page == 3) return 'anime opening animation 4k';
      return 'top anime fights scenes';
    }
    if (lower.contains('gaming')) {
      if (page == 2) return 'gameplay trailer official reveal 4k';
      if (page == 3) return 'esports tournament highlights';
      return 'best gaming moments clip';
    }
    if (lower.contains('animasi') || lower.contains('kartun')) {
      if (page == 2) return 'blender open movie short film animation';
      if (page == 3) return 'animated cartoon award winning short';
      return '3d cgi animated short';
    }
    if (page == 2) return '$query full';
    if (page == 3) return '$query official';
    return '$query clip';
  }

  /// Mencari video YouTube secara live (pada native/mobile via scraping ytInitialData,
  /// dengan pagination lazy-loading dan fallback ke preset).
  static Future<List<YouTubeVideo>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      if (page == 1) {
        return categoryPresets['Trending'] ?? [];
      } else {
        return search('Trending', page: page);
      }
    }

    // Jika user menginputkan link YouTube langsung
    final directId = extractVideoId(cleanQuery);
    if (directId != null) {
      final info = await fetchVideoDetails(directId);
      return [info];
    }

    final cacheKey = 'yt_search_${cleanQuery.toLowerCase()}_p$page';
    final cached = ApiCacheManager.instance.get<List<YouTubeVideo>>(cacheKey);
    if (cached != null) {
      return List<YouTubeVideo>.from(cached);
    }

    final effectiveQuery = _getQueryForPage(cleanQuery, page);

    // Lakukan pencarian live
    try {
      if (!kIsWeb) {
        final url = Uri.parse(
          'https://www.youtube.com/results?search_query=${Uri.encodeComponent(effectiveQuery)}',
        );
        final response = await AppHttpClient.get(
          url,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Accept-Language': 'id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7',
          },
          timeout: const Duration(seconds: 6),
        );

        if (response.statusCode == 200) {
          final results = _parseYouTubeSearchHtml(response.body);
          if (results.isNotEmpty) {
            ApiCacheManager.instance.set(cacheKey, results, ttl: ApiCacheManager.searchTtl);
            return results;
          }
        }
      }
    } catch (e) {
      debugPrint('[YouTubeService] Live search error: $e');
    }

    // Fallback: cari di koleksi preset yang relevan
    final lowerQuery = cleanQuery.toLowerCase();
    final allPresets = categoryPresets.values.expand((list) => list).toSet().toList();
    final matched = allPresets.where((v) {
      return v.title.toLowerCase().contains(lowerQuery) ||
          v.channelTitle.toLowerCase().contains(lowerQuery);
    }).toList();

    if (matched.isNotEmpty) {
      ApiCacheManager.instance.set(cacheKey, matched, ttl: ApiCacheManager.searchTtl);
      return matched;
    }

    final fallback = page == 1 ? (categoryPresets['Trending'] ?? []) : <YouTubeVideo>[];
    if (fallback.isNotEmpty) {
      ApiCacheManager.instance.set(cacheKey, fallback, ttl: ApiCacheManager.searchTtl);
    }
    return fallback;
  }

  /// Mem-parsing konten HTML YouTube Search untuk mengekstrak videoRenderer
  static List<YouTubeVideo> _parseYouTubeSearchHtml(String html) {
    final List<YouTubeVideo> videos = [];
    try {
      final match = RegExp(r'var ytInitialData = ({.*?});</script>').firstMatch(html);
      if (match == null) return videos;

      final jsonString = match.group(1);
      if (jsonString == null) return videos;

      final data = json.decode(jsonString) as Map<String, dynamic>;
      final contents = data['contents']?['twoColumnSearchResultsRenderer']
          ?['primaryContents']?['sectionListRenderer']?['contents'] as List?;

      if (contents == null) return videos;

      for (final section in contents) {
        final itemSection = section['itemSectionRenderer'];
        if (itemSection == null) continue;
        final items = itemSection['contents'] as List?;
        if (items == null) continue;

        for (final item in items) {
          final v = item['videoRenderer'];
          if (v != null) {
            final videoId = v['videoId'] as String?;
            if (videoId == null || videoId.isEmpty) continue;

            final titleRuns = v['title']?['runs'] as List?;
            final title = titleRuns != null && titleRuns.isNotEmpty
                ? (titleRuns[0]['text'] as String? ?? 'Video YouTube')
                : (v['title']?['simpleText'] as String? ?? 'Video YouTube');

            final ownerRuns = v['ownerText']?['runs'] as List?;
            final channel = ownerRuns != null && ownerRuns.isNotEmpty
                ? (ownerRuns[0]['text'] as String? ?? 'YouTube')
                : 'YouTube';

            final duration = v['lengthText']?['simpleText'] as String? ??
                (v['badges'] != null ? 'LIVE' : '');

            videos.add(
              YouTubeVideo(
                id: videoId,
                title: title,
                channelTitle: channel,
                thumbnailUrl: 'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
                duration: duration,
              ),
            );

            if (videos.length >= 25) break;
          }
        }
      }
    } catch (e) {
      debugPrint('[YouTubeService] Parse HTML error: $e');
    }
    return videos;
  }

  /// Mengambil informasi video detail (termasuk judul asli via oEmbed bila tersedia)
  static Future<YouTubeVideo> fetchVideoDetails(String videoId) async {
    final cleanId = extractVideoId(videoId) ?? videoId;
    final cacheKey = 'yt_detail_$cleanId';
    final cached = ApiCacheManager.instance.get<YouTubeVideo>(cacheKey);
    if (cached != null) {
      return cached;
    }

    try {
      final oembedUrl = Uri.parse(
        'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$cleanId&format=json',
      );
      final res = await AppHttpClient.get(oembedUrl, timeout: const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final title = data['title'] as String?;
        final author = data['author_name'] as String?;
        final thumb = data['thumbnail_url'] as String?;
        final video = YouTubeVideo(
          id: cleanId,
          title: title ?? 'Video YouTube ($cleanId)',
          channelTitle: author ?? 'YouTube',
          thumbnailUrl: thumb ?? 'https://img.youtube.com/vi/$cleanId/hqdefault.jpg',
          duration: '',
        );
        ApiCacheManager.instance.set(cacheKey, video, ttl: ApiCacheManager.oEmbedTtl);
        return video;
      }
    } catch (_) {}

    return YouTubeVideo.fromId(id: cleanId);
  }
}
