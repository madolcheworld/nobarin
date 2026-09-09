/// Common polymorphic interface for all playable video and stream media items
/// in the Watch Party application.
abstract interface class PlayableMediaItem {
  String get id;
  String get title;
  String get url;
  String? get thumbnailUrl;
  String get duration;
  String get author;
  String get mediaType;
}

/// Generic media item implementation for direct URLs or ad-hoc media items.
class GenericPlayableMediaItem implements PlayableMediaItem {
  @override
  final String id;
  @override
  final String title;
  @override
  final String url;
  @override
  final String? thumbnailUrl;
  @override
  final String duration;
  @override
  final String author;
  @override
  final String mediaType;

  const GenericPlayableMediaItem({
    required this.id,
    required this.title,
    required this.url,
    this.thumbnailUrl,
    this.duration = '',
    this.author = 'Direct Stream',
    required this.mediaType,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenericPlayableMediaItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          url == other.url;

  @override
  int get hashCode => id.hashCode ^ url.hashCode;
}
