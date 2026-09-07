class YouTubeVideo {
  final String id;
  final String title;
  final String channelTitle;
  final String thumbnailUrl;
  final String duration;

  const YouTubeVideo({
    required this.id,
    required this.title,
    required this.channelTitle,
    required this.thumbnailUrl,
    required this.duration,
  });

  String get url => 'https://www.youtube.com/watch?v=$id';

  factory YouTubeVideo.fromId({
    required String id,
    String? title,
    String? channelTitle,
    String? duration,
  }) {
    return YouTubeVideo(
      id: id,
      title: title ?? 'Video YouTube ($id)',
      channelTitle: channelTitle ?? 'YouTube',
      thumbnailUrl: 'https://img.youtube.com/vi/$id/hqdefault.jpg',
      duration: duration ?? '',
    );
  }

  factory YouTubeVideo.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    return YouTubeVideo(
      id: id,
      title: json['title'] as String? ?? 'Video YouTube',
      channelTitle: json['channelTitle'] as String? ?? 'YouTube',
      thumbnailUrl: json['thumbnailUrl'] as String? ??
          'https://img.youtube.com/vi/$id/hqdefault.jpg',
      duration: json['duration'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'channelTitle': channelTitle,
        'thumbnailUrl': thumbnailUrl,
        'duration': duration,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is YouTubeVideo &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
