class VimeoVideo {
  final String id;
  final String title;
  final String channelTitle;
  final String thumbnailUrl;
  final String duration;
  final String category;

  const VimeoVideo({
    required this.id,
    required this.title,
    required this.channelTitle,
    required this.thumbnailUrl,
    required this.duration,
    this.category = 'Video',
  });

  String get url => 'https://vimeo.com/$id';

  factory VimeoVideo.fromId({
    required String id,
    String? title,
    String? channelTitle,
    String? thumbnailUrl,
    String? duration,
    String? category,
  }) {
    return VimeoVideo(
      id: id,
      title: title ?? 'Vimeo Video ($id)',
      channelTitle: channelTitle ?? 'Vimeo Creator',
      thumbnailUrl: thumbnailUrl ??
          'https://vumbnail.com/$id.jpg',
      duration: duration ?? 'HD',
      category: category ?? 'Video',
    );
  }

  factory VimeoVideo.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    return VimeoVideo(
      id: id,
      title: json['title'] as String? ?? 'Vimeo Video',
      channelTitle: json['channelTitle'] as String? ?? 'Vimeo',
      thumbnailUrl: json['thumbnailUrl'] as String? ??
          'https://vumbnail.com/$id.jpg',
      duration: json['duration'] as String? ?? 'HD',
      category: json['category'] as String? ?? 'Video',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'channelTitle': channelTitle,
        'thumbnailUrl': thumbnailUrl,
        'duration': duration,
        'category': category,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VimeoVideo &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
