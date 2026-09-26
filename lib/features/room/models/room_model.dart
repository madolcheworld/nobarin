class RoomModel {
  final String id;
  final String code;
  final String title;
  final String? description;
  final String? hostId;
  final String? hostName;
  final bool isPublic;
  final String controlMode; // 'host_only' or 'collaborative'
  final String? currentMediaType; // 'youtube' or 'direct_url'
  final String? currentMediaUrl;
  final String currentState; // 'playing', 'paused', 'buffering'
  final double currentPosition;
  final String livekitRoomName;
  final int participantCount;
  final String? thumbnailUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const RoomModel({
    required this.id,
    required this.code,
    required this.title,
    this.description,
    this.hostId,
    this.hostName,
    this.isPublic = true,
    this.controlMode = 'host_only',
    this.currentMediaType,
    this.currentMediaUrl,
    this.currentState = 'paused',
    this.currentPosition = 0.0,
    required this.livekitRoomName,
    this.participantCount = 1,
    this.thumbnailUrl,
    this.createdAt,
    this.updatedAt,
  });

  bool get isHostOnly => controlMode == 'host_only';
  bool get isCollaborative => controlMode == 'collaborative';
  bool get isPlaying => currentState == 'playing';

  /// Automatically resolves or extracts a thumbnail URL from video URL and media type
  static String? resolveThumbnail({String? url, String? type}) {
    if (url == null || url.trim().isEmpty) return null;
    final trimmed = url.trim();

    // If the URL itself is an image format
    final lower = trimmed.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp')) {
      return trimmed;
    }

    // YouTube thumbnail resolution (including Shorts, Live, embed, and youtu.be)
    if (type == 'youtube' || lower.contains('youtube.com') || lower.contains('youtu.be')) {
      final patterns = [
        RegExp(r'(?:youtube\.com|youtu\.be).*?[?&]v=([_\-a-zA-Z0-9]{11})', caseSensitive: false),
        RegExp(r'(?:youtube\.com|youtube-nocookie\.com)\/embed\/([_\-a-zA-Z0-9]{11})', caseSensitive: false),
        RegExp(r'youtube\.com\/shorts\/([_\-a-zA-Z0-9]{11})', caseSensitive: false),
        RegExp(r'youtube\.com\/live\/([_\-a-zA-Z0-9]{11})', caseSensitive: false),
        RegExp(r'youtu\.be\/([_\-a-zA-Z0-9]{11})', caseSensitive: false),
        RegExp(r'^[_\-a-zA-Z0-9]{11}$'),
      ];
      for (final p in patterns) {
        final match = p.firstMatch(trimmed);
        if (match != null) {
          final id = match.groupCount >= 1 ? match.group(1) : trimmed;
          if (id != null && id.isNotEmpty) {
            return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
          }
        }
      }
    }

    // Dailymotion thumbnail resolution
    if (type == 'dailymotion' || lower.contains('dailymotion.com') || lower.contains('dai.ly')) {
      final regExp = RegExp(r'(?:dailymotion\.com\/(?:video|embed\/video)\/([a-zA-Z0-9]+)|dai\.ly\/([a-zA-Z0-9]+)|video=([a-zA-Z0-9]+))');
      final match = regExp.firstMatch(trimmed);
      final id = match?.group(1) ?? match?.group(2) ?? match?.group(3);
      if (id != null && id.isNotEmpty) {
        return 'https://www.dailymotion.com/thumbnail/video/$id';
      }
      if (RegExp(r'^[a-zA-Z0-9]+$').hasMatch(trimmed)) {
        return 'https://www.dailymotion.com/thumbnail/video/$trimmed';
      }
    }

    return null;
  }

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    final rawDesc = json['description'] as String?;
    String? cleanDesc = rawDesc;
    String? metaHostName;
    String? metaHostId;
    String? metaThumb;

    if (rawDesc != null) {
      final metaMatch = RegExp(r'\[HOST:(?:name=([^;\]]+))?(?:;id=([^\]]+))?\]').firstMatch(rawDesc);
      if (metaMatch != null) {
        metaHostName = metaMatch.group(1);
        metaHostId = metaMatch.group(2);
        cleanDesc = rawDesc.replaceAll(RegExp(r'\[HOST:[^\]]+\]\s*'), '').trim();
      } else {
        final simpleMatch = RegExp(r'\[HOST:(.+?)\]').firstMatch(rawDesc);
        if (simpleMatch != null) {
          metaHostName = simpleMatch.group(1);
          cleanDesc = rawDesc.replaceAll(RegExp(r'\[HOST:.+?\]\s*'), '').trim();
        }
      }

      if (cleanDesc != null) {
        final thumbMatch = RegExp(r'\[THUMB:(.+?)\]').firstMatch(cleanDesc);
        if (thumbMatch != null) {
          metaThumb = thumbMatch.group(1)?.trim();
          cleanDesc = cleanDesc.replaceAll(RegExp(r'\[THUMB:.+?\]\s*'), '').trim();
        }
      }

      if (cleanDesc != null && cleanDesc.isEmpty) cleanDesc = null;
    }

    String? resolvedHostName = json['host_name'] as String?;
    if (resolvedHostName == null || resolvedHostName.isEmpty || resolvedHostName == 'Host') {
      if (json['profiles'] is Map) {
        resolvedHostName = json['profiles']['username'] as String?;
      } else if (json['profiles'] is List &&
              (json['profiles'] as List).isNotEmpty &&
              json['profiles'][0] is Map) {
        resolvedHostName = json['profiles'][0]['username'] as String?;
      }
    }
    resolvedHostName ??= metaHostName;

    final resolvedHostId = (json['host_id'] as String?) ?? metaHostId;
    final mediaUrl = json['current_media_url'] as String?;
    final mediaType = json['current_media_type'] as String?;
    final resolvedThumb = (json['thumbnail_url'] as String?) ??
        metaThumb ??
        resolveThumbnail(url: mediaUrl, type: mediaType);

    return RoomModel(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      title: json['title'] as String? ?? 'Untitled Room',
      description: cleanDesc,
      hostId: resolvedHostId,
      hostName: (resolvedHostName != null && resolvedHostName.isNotEmpty)
          ? resolvedHostName
          : 'Host',
      isPublic: json['is_public'] as bool? ?? true,
      controlMode: json['control_mode'] as String? ?? 'host_only',
      currentMediaType: mediaType,
      currentMediaUrl: mediaUrl,
      currentState: json['current_state'] as String? ?? 'paused',
      currentPosition: (json['current_position'] as num?)?.toDouble() ?? 0.0,
      livekitRoomName:
          json['livekit_room_name'] as String? ?? 'room_${json['code']}',
      participantCount: (json['participant_count'] as num?)?.toInt() ?? 1,
      thumbnailUrl: resolvedThumb,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'title': title,
      if (description != null) 'description': description,
      if (hostId != null) 'host_id': hostId,
      if (hostName != null) 'host_name': hostName,
      'is_public': isPublic,
      'control_mode': controlMode,
      'current_media_type': currentMediaType,
      'current_media_url': currentMediaUrl,
      'current_state': currentState,
      'current_position': currentPosition,
      'livekit_room_name': livekitRoomName,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  RoomModel copyWith({
    String? id,
    String? code,
    String? title,
    String? description,
    String? hostId,
    String? hostName,
    bool? isPublic,
    String? controlMode,
    String? currentMediaType,
    String? currentMediaUrl,
    String? currentState,
    double? currentPosition,
    String? livekitRoomName,
    int? participantCount,
    String? thumbnailUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RoomModel(
      id: id ?? this.id,
      code: code ?? this.code,
      title: title ?? this.title,
      description: description ?? this.description,
      hostId: hostId ?? this.hostId,
      hostName: hostName ?? this.hostName,
      isPublic: isPublic ?? this.isPublic,
      controlMode: controlMode ?? this.controlMode,
      currentMediaType: currentMediaType ?? this.currentMediaType,
      currentMediaUrl: currentMediaUrl ?? this.currentMediaUrl,
      currentState: currentState ?? this.currentState,
      currentPosition: currentPosition ?? this.currentPosition,
      livekitRoomName: livekitRoomName ?? this.livekitRoomName,
      participantCount: participantCount ?? this.participantCount,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
