class QueueItem {
  final String id;
  final String roomId;
  final String mediaType; // 'youtube' or 'direct_url'
  final String mediaUrl;
  final String title;
  final String? thumbnailUrl;
  final String addedByUserId;
  final String addedByUserName;
  final int orderIndex;
  final DateTime createdAt;

  const QueueItem({
    required this.id,
    required this.roomId,
    required this.mediaType,
    required this.mediaUrl,
    required this.title,
    this.thumbnailUrl,
    required this.addedByUserId,
    required this.addedByUserName,
    this.orderIndex = 0,
    required this.createdAt,
  });

  bool get isYouTube => mediaType == 'youtube';
  bool get isBstation => mediaType == 'bstation' || mediaType == 'bilibili';
  bool get isDailymotion => mediaType == 'dailymotion';
  bool get isDirectUrl => mediaType == 'direct_url';

  factory QueueItem.fromJson(Map<String, dynamic> json) {
    return QueueItem(
      id: json['id'] as String? ?? '',
      roomId: json['room_id'] as String? ?? '',
      mediaType: json['media_type'] as String? ?? 'direct_url',
      mediaUrl: json['media_url'] as String? ?? '',
      title: json['title'] as String? ?? 'Video',
      thumbnailUrl: json['thumbnail_url'] as String?,
      addedByUserId: json['added_by_user_id'] as String? ?? '',
      addedByUserName: json['added_by_user_name'] as String? ?? 'Pengguna',
      orderIndex: (json['order_index'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())?.toLocal() ??
              DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'room_id': roomId,
      'media_type': mediaType,
      'media_url': mediaUrl,
      'title': title,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      'added_by_user_id': addedByUserId,
      'added_by_user_name': addedByUserName,
      'order_index': orderIndex,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  QueueItem copyWith({
    String? id,
    String? roomId,
    String? mediaType,
    String? mediaUrl,
    String? title,
    String? thumbnailUrl,
    String? addedByUserId,
    String? addedByUserName,
    int? orderIndex,
    DateTime? createdAt,
  }) {
    return QueueItem(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      mediaType: mediaType ?? this.mediaType,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      title: title ?? this.title,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      addedByUserId: addedByUserId ?? this.addedByUserId,
      addedByUserName: addedByUserName ?? this.addedByUserName,
      orderIndex: orderIndex ?? this.orderIndex,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueueItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
