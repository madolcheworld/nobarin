class TwitchStream {
  final String id;
  final String title;
  final String channelTitle;
  final String thumbnailUrl;
  final String category;
  final String viewerCount;
  final String type; // 'live' | 'channel'

  const TwitchStream({
    required this.id,
    required this.title,
    required this.channelTitle,
    required this.thumbnailUrl,
    required this.category,
    this.viewerCount = '',
    this.type = 'live',
  });

  String get url => 'https://www.twitch.tv/$id';

  factory TwitchStream.fromId({
    required String id,
    String? title,
    String? channelTitle,
    String? thumbnailUrl,
    String? category,
    String? viewerCount,
    String? type,
  }) {
    return TwitchStream(
      id: id,
      title: title ?? 'Twitch Stream ($id)',
      channelTitle: channelTitle ?? id,
      thumbnailUrl: thumbnailUrl ??
          'https://static-cdn.jtvnw.net/previews-ttv/live_user_$id-640x360.jpg',
      category: category ?? 'Live Stream',
      viewerCount: viewerCount ?? '',
      type: type ?? 'live',
    );
  }

  factory TwitchStream.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    return TwitchStream(
      id: id,
      title: json['title'] as String? ?? 'Twitch Stream',
      channelTitle: json['channelTitle'] as String? ?? id,
      thumbnailUrl: json['thumbnailUrl'] as String? ??
          'https://static-cdn.jtvnw.net/previews-ttv/live_user_$id-640x360.jpg',
      category: json['category'] as String? ?? 'Live Stream',
      viewerCount: json['viewerCount'] as String? ?? '',
      type: json['type'] as String? ?? 'live',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'channelTitle': channelTitle,
        'thumbnailUrl': thumbnailUrl,
        'category': category,
        'viewerCount': viewerCount,
        'type': type,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TwitchStream &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
