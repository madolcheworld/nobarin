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
    this.createdAt,
    this.updatedAt,
  });

  bool get isHostOnly => controlMode == 'host_only';
  bool get isCollaborative => controlMode == 'collaborative';
  bool get isPlaying => currentState == 'playing';

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    final rawDesc = json['description'] as String?;
    String? cleanDesc = rawDesc;
    String? metaHostName;
    String? metaHostId;

    if (rawDesc != null) {
      final metaMatch = RegExp(r'\[HOST:(?:name=([^;\]]+))?(?:;id=([^\]]+))?\]').firstMatch(rawDesc);
      if (metaMatch != null) {
        metaHostName = metaMatch.group(1);
        metaHostId = metaMatch.group(2);
        cleanDesc = rawDesc.replaceAll(RegExp(r'\[HOST:[^\]]+\]\s*'), '').trim();
        if (cleanDesc.isEmpty) cleanDesc = null;
      } else {
        final simpleMatch = RegExp(r'\[HOST:(.+?)\]').firstMatch(rawDesc);
        if (simpleMatch != null) {
          metaHostName = simpleMatch.group(1);
          cleanDesc = rawDesc.replaceAll(RegExp(r'\[HOST:.+?\]\s*'), '').trim();
          if (cleanDesc.isEmpty) cleanDesc = null;
        }
      }
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
      currentMediaType: json['current_media_type'] as String?,
      currentMediaUrl: json['current_media_url'] as String?,
      currentState: json['current_state'] as String? ?? 'paused',
      currentPosition: (json['current_position'] as num?)?.toDouble() ?? 0.0,
      livekitRoomName:
          json['livekit_room_name'] as String? ?? 'room_${json['code']}',
      participantCount: (json['participant_count'] as num?)?.toInt() ?? 1,
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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
