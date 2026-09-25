import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../network/app_http_client.dart';
import '../../features/room/controllers/dailymotion_player_controller.dart';
import '../../features/room/controllers/unified_player_controller.dart';

/// Centralized utility for extracting, cleaning, and resolving human-readable video titles
/// from various video platforms (Bstation, YouTube, Dailymotion, Direct URLs)
/// preventing raw IDs or numeric segments from being displayed to the user.
class VideoTitleResolver {
  static final Map<String, String> _titleCache = {};

  /// Normalizes and cleans raw titles by stripping platform suffixes, HTML entities,
  /// and rejecting purely numeric or ID-based strings.
  static String cleanTitle(String? rawTitle) {
    if (rawTitle == null) return '';
    var title = rawTitle.trim();
    if (title.isEmpty) return '';

    // If title consists exclusively of digits, it's an ID or index, not a human title.
    if (RegExp(r'^\d+$').hasMatch(title)) {
      return '';
    }

    // If title is of the form "Video Platform (123456)" or "(12345)", reject it.
    if (RegExp(
      r'^(Video\s+)?(Bstation|Bilibili|YouTube|Dailymotion)\s*\([^\)]+\)$',
      caseSensitive: false,
    ).hasMatch(title)) {
      return '';
    }

    // Unescape common HTML entities
    title = title
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');

    // Strip common platform suffixes (e.g. " - Bstation", " | YouTube", " HD | bilibili", " - Dailymotion")
    title = title.replaceAll(
      RegExp(r'\s*(HD\s*)?[-|/–—_]\s*(Bstation|Bilibili|YouTube|Dailymotion).*$', caseSensitive: false),
      '',
    );
    title = title.replaceAll(
      RegExp(r'\s*HD\s*\|\s*bilibili.*$', caseSensitive: false),
      '',
    );

    title = title.trim();

    // Verify after stripping suffixes that it isn't empty, just digits, or generic platform name
    if (title.isEmpty || RegExp(r'^\d+$').hasMatch(title)) {
      return '';
    }

    final lower = title.toLowerCase();
    if (lower == 'bstation' ||
        lower == 'bilibili' ||
        lower == 'youtube' ||
        lower == 'dailymotion' ||
        lower == 'video') {
      return '';
    }

    return title;
  }

  /// Resolves the actual human-readable video title asynchronously for a given URL.
  /// Returns null if unable to resolve or network fails.
  static Future<String?> resolveTitle(
    String url, {
    String? mediaType,
    http.Client? client,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    if (_titleCache.containsKey(trimmed)) {
      final cached = _titleCache[trimmed];
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
    }

    final effectiveClient = client ?? AppHttpClient.client;

    try {
      // 1. YouTube Detection
      if (mediaType == 'youtube' ||
          trimmed.contains('youtube.com') ||
          trimmed.contains('youtu.be')) {
        final videoId = UnifiedPlayerController.extractYoutubeId(trimmed);
        if (videoId != null && videoId.isNotEmpty) {
          final resolved = await _resolveYouTubeTitle(videoId, effectiveClient);
          if (resolved != null && resolved.isNotEmpty) {
            _titleCache[trimmed] = resolved;
            return resolved;
          }
        }
        return null;
      }

      // 2. Dailymotion Detection
      if (mediaType == 'dailymotion' ||
          trimmed.contains('dailymotion.com') ||
          trimmed.contains('dai.ly')) {
        final videoId = DailymotionPlayerController.extractVideoId(trimmed);
        if (videoId != null && videoId.isNotEmpty) {
          final resolved = await _resolveDailymotionTitle(videoId, effectiveClient);
          if (resolved != null && resolved.isNotEmpty) {
            _titleCache[trimmed] = resolved;
            return resolved;
          }
        }
        return null;
      }

      // 3. Bstation / Bilibili Detection
      if (mediaType == 'bstation' ||
          trimmed.contains('bilibili.tv') ||
          trimmed.contains('bilibili.com') ||
          trimmed.contains('b23.tv')) {
        final resolved = await _resolveBstationTitle(trimmed, effectiveClient);
        if (resolved != null && resolved.isNotEmpty) {
          _titleCache[trimmed] = resolved;
          return resolved;
        }
        return null;
      }

      // 4. Direct URL / Media File Detection
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        final uri = Uri.tryParse(trimmed);
        if (uri != null && uri.pathSegments.isNotEmpty) {
          var seg = uri.pathSegments.last;
          // Strip query params if in segment
          if (seg.contains('?')) {
            seg = seg.split('?').first;
          }
          // Remove extension
          final dotIdx = seg.lastIndexOf('.');
          if (dotIdx != -1 && dotIdx > 0) {
            seg = seg.substring(0, dotIdx);
          }
          // Replace underscores and dashes
          seg = seg.replaceAll(RegExp(r'[-_]+'), ' ').trim();
          final clean = cleanTitle(seg);
          if (clean.isNotEmpty) {
            _titleCache[trimmed] = clean;
            return clean;
          }
        }
      }
    } catch (e) {
      debugPrint('[VideoTitleResolver] Error resolving title for $trimmed: $e');
    }

    return null;
  }

  /// Resolves YouTube video title via YouTube official public oEmbed API.
  static Future<String?> _resolveYouTubeTitle(String videoId, http.Client client) async {
    try {
      final oEmbedUri = Uri.parse(
        'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json',
      );
      final res = await client.get(oEmbedUri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic> && decoded['title'] != null) {
          final clean = cleanTitle(decoded['title'] as String);
          if (clean.isNotEmpty) {
            return clean;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Resolves Dailymotion video title via Dailymotion official public oEmbed API.
  static Future<String?> _resolveDailymotionTitle(String videoId, http.Client client) async {
    try {
      final oEmbedUri = Uri.parse(
        'https://www.dailymotion.com/services/oembed?url=https://www.dailymotion.com/video/$videoId',
      );
      final res = await client.get(oEmbedUri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic> && decoded['title'] != null) {
          final clean = cleanTitle(decoded['title'] as String);
          if (clean.isNotEmpty) {
            return clean;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Resolves Bstation anime/video title from page HTML metadata tags.
  static Future<String?> _resolveBstationTitle(String url, http.Client client) async {
    try {
      final canonicalUrl = url.startsWith('http') ? url : 'https://$url';
      final uri = Uri.parse(canonicalUrl);
      final res = await client.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36',
          'Accept-Language': 'id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7',
        },
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final body = res.body;

        // 1. Try <title> tag
        final titleMatch = RegExp(r'<title>(.*?)</title>', caseSensitive: false).firstMatch(body);
        if (titleMatch != null) {
          final raw = titleMatch.group(1);
          final clean = cleanTitle(raw);
          if (clean.isNotEmpty) {
            return clean;
          }
        }

        // 2. Try <meta property="og:title" content="...">
        final ogMatch = RegExp(
          r'<meta\s+[^>]*?property=["\x27]og:title["\x27][^>]*?content=(?:"([^"]*)"|\x27([^\x27]*)\x27)',
          caseSensitive: false,
        ).firstMatch(body) ??
        RegExp(
          r'<meta\s+[^>]*?content=(?:"([^"]*)"|\x27([^\x27]*)\x27)[^>]*?property=["\x27]og:title["\x27]',
          caseSensitive: false,
        ).firstMatch(body);
        if (ogMatch != null) {
          final raw = ogMatch.group(1) ?? ogMatch.group(2);
          final clean = cleanTitle(raw);
          if (clean.isNotEmpty) {
            return clean;
          }
        }

        // 3. Try <meta name="twitter:title" content="...">
        final twMatch = RegExp(
          r'<meta\s+[^>]*?name=["\x27]twitter:title["\x27][^>]*?content=(?:"([^"]*)"|\x27([^\x27]*)\x27)',
          caseSensitive: false,
        ).firstMatch(body) ??
        RegExp(
          r'<meta\s+[^>]*?content=(?:"([^"]*)"|\x27([^\x27]*)\x27)[^>]*?name=["\x27]twitter:title["\x27]',
          caseSensitive: false,
        ).firstMatch(body);
        if (twMatch != null) {
          final raw = twMatch.group(1) ?? twMatch.group(2);
          final clean = cleanTitle(raw);
          if (clean.isNotEmpty) {
            return clean;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Clears in-memory title cache (useful for testing or cache refresh).
  static void clearCache() {
    _titleCache.clear();
  }
}
