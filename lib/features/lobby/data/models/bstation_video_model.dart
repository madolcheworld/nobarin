import '../../../../core/utils/time_formatter.dart';
import 'playable_media_item.dart';

class BstationVideo implements PlayableMediaItem {
  @override
  final String id;
  @override
  final String title;
  final String description;
  final String uploaderName;
  @override
  String get author => uploaderName;
  @override
  final String thumbnailUrl;
  final int durationSeconds;
  @override
  String get duration => durationFormatted;
  final int viewsTotal;
  final String category;
  final String? episodeNumber;
  @override
  String get mediaType => 'bstation';

  const BstationVideo({
    required this.id,
    required this.title,
    this.description = '',
    this.uploaderName = 'Bstation Creator',
    this.thumbnailUrl = '',
    this.durationSeconds = 0,
    this.viewsTotal = 0,
    this.category = 'Anime Populer',
    this.episodeNumber,
  });

  /// Canonical watch URL
  @override
  String get url {
    if (id.startsWith('BV') || id.startsWith('bv')) {
      return 'https://www.bilibili.com/video/$id';
    }
    return 'https://www.bilibili.tv/id/play/$id';
  }

  /// Embed iframe URL used by embedded player (for Bilibili BV IDs) or canonical web URL
  String get embedUrl {
    if (id.startsWith('BV') || id.startsWith('bv')) {
      return 'https://player.bilibili.com/player.html?bvid=$id&page=1&as_wide=1&high_quality=1&danmaku=0&autoplay=1';
    }
    return 'https://www.bilibili.tv/id/play/$id';
  }

  /// Standard thumbnail URL fallback
  String get effectiveThumbnailUrl {
    if (thumbnailUrl.isNotEmpty) return thumbnailUrl;
    return 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=800&auto=format&fit=crop&q=80';
  }

  /// Alias for effectiveThumbnailUrl
  String get canonicalThumbnailUrl => effectiveThumbnailUrl;

  /// Format duration to mm:ss or hh:mm:ss
  String get durationFormatted => TimeFormatter.formatDuration(
        durationSeconds.toDouble(),
        fallback: 'HD',
        padHours: false,
      );

  /// Alias for durationFormatted
  String get formattedDuration => durationFormatted;

  /// Human-readable views count
  String get viewsFormatted {
    if (viewsTotal <= 0) return '';
    if (viewsTotal >= 1000000) {
      return '${(viewsTotal / 1000000).toStringAsFixed(1)}M views';
    } else if (viewsTotal >= 1000) {
      return '${(viewsTotal / 1000).toStringAsFixed(1)}K views';
    }
    return '$viewsTotal views';
  }

  /// Alias for viewsFormatted
  String get formattedViews => viewsFormatted;

  factory BstationVideo.fromId(
    String id, {
    String? title,
    String? uploaderName,
    String? category,
    String? thumbnailUrl,
    String? episodeNumber,
  }) {
    return BstationVideo(
      id: id,
      title: title ?? 'Bstation Video ($id)',
      uploaderName: uploaderName ?? 'Bstation / Bilibili',
      category: category ?? 'Anime Populer',
      thumbnailUrl: thumbnailUrl ?? '',
      episodeNumber: episodeNumber,
    );
  }

  factory BstationVideo.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? json['bvid'] as String? ?? '';
    final uploader = json['uploader_name'] as String? ??
        json['author'] as String? ??
        json['owner'] as String? ??
        'Bstation Creator';
    final thumb = json['thumbnail_url'] as String? ??
        json['pic'] as String? ??
        json['cover'] as String? ??
        '';
    final duration = (json['duration'] as num?)?.toInt() ?? 0;
    final views = (json['views_total'] as num?)?.toInt() ??
        (json['play'] as num?)?.toInt() ??
        0;

    return BstationVideo(
      id: id,
      title: json['title'] as String? ?? 'Bstation Video',
      description: json['description'] as String? ?? json['desc'] as String? ?? '',
      uploaderName: uploader,
      thumbnailUrl: thumb,
      durationSeconds: duration,
      viewsTotal: views,
      category: json['category'] as String? ?? 'Anime Populer',
      episodeNumber: json['episode_number'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'uploader_name': uploaderName,
        'thumbnail_url': effectiveThumbnailUrl,
        'duration': durationSeconds,
        'views_total': viewsTotal,
        'category': category,
        if (episodeNumber != null) 'episode_number': episodeNumber,
      };
}
