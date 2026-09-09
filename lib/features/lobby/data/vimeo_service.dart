import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/utils/time_formatter.dart';
import 'models/vimeo_video_model.dart';

class VimeoService {
  static final RegExp _vimeoRegex = RegExp(
    r'(?:https?:\/\/)?(?:www\.|player\.)?vimeo\.com\/(?:channels\/(?:\w+\/)?|groups\/([^\/]*)\/videos\/|album\/(\d+)\/video\/|video\/|)(\d+)(?:$|\/|\?)',
    caseSensitive: false,
  );

  /// Ekstrak Vimeo video ID dari URL atau string angka
  static String? extractVideoId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    if (RegExp(r'^\d{5,12}$').hasMatch(trimmed)) {
      return trimmed;
    }
    final match = _vimeoRegex.firstMatch(trimmed);
    return match?.group(3);
  }

  /// Preset terkurasi berbagai video Vimeo berkualitas tinggi
  static final Map<String, List<VimeoVideo>> categoryPresets = {
    'Staff Picks': [
      const VimeoVideo(
        id: '76979871',
        title: 'The New Normal - Vimeo Staff Pick Premiere',
        channelTitle: 'Vimeo Staff Picks',
        thumbnailUrl: 'https://vumbnail.com/76979871.jpg',
        duration: '11:15',
        category: 'Staff Picks',
      ),
      const VimeoVideo(
        id: '1084537',
        title: 'Big Buck Bunny (HD 60fps Open Movie)',
        channelTitle: 'Blender Foundation',
        thumbnailUrl: 'https://vumbnail.com/1084537.jpg',
        duration: '09:56',
        category: 'Staff Picks',
      ),
      const VimeoVideo(
        id: '22439234',
        title: 'The Mountain - Milky Way & El Teide Timelapse',
        channelTitle: 'TSO Photography',
        thumbnailUrl: 'https://vumbnail.com/22439234.jpg',
        duration: '03:05',
        category: 'Staff Picks',
      ),
      const VimeoVideo(
        id: '1487517',
        title: 'Validation - Award-winning Fable Film',
        channelTitle: 'Kurt Kuenne',
        thumbnailUrl: 'https://vumbnail.com/1487517.jpg',
        duration: '16:24',
        category: 'Staff Picks',
      ),
    ],
    'Film Pendek & Sci-Fi': [
      const VimeoVideo(
        id: '76979871',
        title: 'The New Normal - Cinematic Sci-Fi Short',
        channelTitle: 'Vimeo Staff Picks',
        thumbnailUrl: 'https://vumbnail.com/76979871.jpg',
        duration: '11:15',
        category: 'Film Pendek',
      ),
      const VimeoVideo(
        id: '62232896',
        title: 'RUIN - Post-Apocalyptic Animated Action',
        channelTitle: 'OddBall Animation',
        thumbnailUrl: 'https://vumbnail.com/62232896.jpg',
        duration: '08:32',
        category: 'Sci-Fi',
      ),
      const VimeoVideo(
        id: '120583486',
        title: 'SUNDAYS - Futuristic Philosophical Sci-Fi',
        channelTitle: 'PostPanic',
        thumbnailUrl: 'https://vumbnail.com/120583486.jpg',
        duration: '14:50',
        category: 'Sci-Fi',
      ),
    ],
    'Animasi 3D': [
      const VimeoVideo(
        id: '1084537',
        title: 'Big Buck Bunny (HD 60fps)',
        channelTitle: 'Blender Foundation',
        thumbnailUrl: 'https://vumbnail.com/1084537.jpg',
        duration: '09:56',
        category: 'Animasi',
      ),
      const VimeoVideo(
        id: '58229003',
        title: 'Sintel - The Durian Open Movie Project',
        channelTitle: 'Blender Foundation',
        thumbnailUrl: 'https://vumbnail.com/58229003.jpg',
        duration: '14:48',
        category: 'Animasi',
      ),
      const VimeoVideo(
        id: '82173118',
        title: 'Tears of Steel - Sci-Fi VFX Showcase',
        channelTitle: 'Blender Foundation',
        thumbnailUrl: 'https://vumbnail.com/82173118.jpg',
        duration: '12:14',
        category: 'Animasi',
      ),
    ],
    'Dokumenter & Alam': [
      const VimeoVideo(
        id: '22439234',
        title: 'The Mountain - Milky Way Timelapse',
        channelTitle: 'TSO Photography',
        thumbnailUrl: 'https://vumbnail.com/22439234.jpg',
        duration: '03:05',
        category: 'Dokumenter',
      ),
      const VimeoVideo(
        id: '23237102',
        title: 'The Aurora - Arctic Light Phenomena',
        channelTitle: 'TSO Photography',
        thumbnailUrl: 'https://vumbnail.com/23237102.jpg',
        duration: '02:11',
        category: 'Dokumenter',
      ),
      const VimeoVideo(
        id: '38942125',
        title: 'The Arctic Light - Northern Landscape',
        channelTitle: 'TSO Photography',
        thumbnailUrl: 'https://vumbnail.com/38942125.jpg',
        duration: '04:49',
        category: 'Dokumenter',
      ),
    ],
  };

  /// Mengambil info detail video via oEmbed API Vimeo
  static Future<VimeoVideo> fetchVideoDetails(String videoId) async {
    final cleanId = extractVideoId(videoId) ?? videoId;
    try {
      final oembedUrl = Uri.parse(
        'https://vimeo.com/api/oembed.json?url=https://vimeo.com/$cleanId',
      );
      final res = await http.get(oembedUrl).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final title = data['title'] as String?;
        final author = data['author_name'] as String?;
        final thumb = data['thumbnail_url'] as String?;
        final durationSec = data['duration'] as int?;

        final String durationStr = TimeFormatter.formatDuration(
          (durationSec ?? 0).toDouble(),
          fallback: 'HD',
        );

        return VimeoVideo(
          id: cleanId,
          title: title ?? 'Vimeo Video ($cleanId)',
          channelTitle: author ?? 'Vimeo Creator',
          thumbnailUrl: thumb ?? 'https://vumbnail.com/$cleanId.jpg',
          duration: durationStr,
          category: 'Vimeo',
        );
      }
    } catch (e) {
      debugPrint('[VimeoService] oEmbed fetch error: $e');
    }

    return VimeoVideo.fromId(id: cleanId);
  }

  /// Mencari video Vimeo berdasarkan query atau URL / ID video
  static Future<List<VimeoVideo>> search(String query, {int page = 1}) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      return categoryPresets['Staff Picks'] ?? [];
    }

    final id = extractVideoId(clean);
    final results = <VimeoVideo>[];

    if (id != null) {
      final details = await fetchVideoDetails(id);
      results.add(details);
    }

    final lower = clean.toLowerCase();
    for (final list in categoryPresets.values) {
      for (final video in list) {
        if (video.id.toLowerCase().contains(lower) ||
            video.title.toLowerCase().contains(lower) ||
            video.channelTitle.toLowerCase().contains(lower) ||
            video.category.toLowerCase().contains(lower)) {
          if (!results.any((v) => v.id == video.id)) {
            results.add(video);
          }
        }
      }
    }

    return results;
  }
}
