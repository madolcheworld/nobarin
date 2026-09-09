import '../../../../core/utils/time_formatter.dart';
import 'playable_media_item.dart';

class DailymotionVideo implements PlayableMediaItem {
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
  @override
  String get mediaType => 'dailymotion';

  const DailymotionVideo({
    required this.id,
    required this.title,
    this.description = '',
    this.uploaderName = 'Dailymotion Creator',
    this.thumbnailUrl = '',
    this.durationSeconds = 0,
    this.viewsTotal = 0,
    this.category = 'Trending',
  });

  /// Canonical watch URL
  @override
  String get url => 'https://www.dailymotion.com/video/$id';

  /// Embed iframe URL used by embedded player
  String get embedUrl =>
      'https://www.dailymotion.com/embed/video/$id?autoplay=1&ui-logo=0&sharing-enable=0';

  /// Standard thumbnail URL fallback
  String get effectiveThumbnailUrl {
    if (thumbnailUrl.isNotEmpty) return thumbnailUrl;
    return 'https://www.dailymotion.com/thumbnail/video/$id';
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

  factory DailymotionVideo.fromId(
    String id, {
    String? title,
    String? uploaderName,
    String? category,
  }) {
    return DailymotionVideo(
      id: id,
      title: title ?? 'Dailymotion Video ($id)',
      uploaderName: uploaderName ?? 'Dailymotion',
      category: category ?? 'Trending',
    );
  }

  factory DailymotionVideo.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final ownerName = (json['owner.screenname'] ??
            (json['owner'] is Map ? json['owner']['screenname'] : null) ??
            json['uploader_name']) as String? ??
        'Dailymotion';

    final thumb = (json['thumbnail_720_url'] ??
            json['thumbnail_480_url'] ??
            json['thumbnail_url']) as String? ??
        '';

    final duration = (json['duration'] as num?)?.toInt() ?? 0;
    final views = (json['views_total'] as num?)?.toInt() ?? 0;

    return DailymotionVideo(
      id: id,
      title: json['title'] as String? ?? 'Dailymotion Video',
      description: json['description'] as String? ?? '',
      uploaderName: ownerName,
      thumbnailUrl: thumb,
      durationSeconds: duration,
      viewsTotal: views,
      category: json['category'] as String? ?? 'Trending',
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
      };
}
