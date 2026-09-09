import 'package:uuid/uuid.dart';

enum MessageStatus { sending, sent, failed }

class ChatMessage {
  final String id;
  final String roomId;
  final String? userId;
  final String username;
  final String avatarUrl;
  final String content;
  final String type; // 'text', 'system', 'emoji_reaction'
  final DateTime createdAt;
  final MessageStatus status;

  const ChatMessage({
    required this.id,
    required this.roomId,
    this.userId,
    this.username = 'Guest',
    this.avatarUrl = '🦊',
    required this.content,
    this.type = 'text',
    required this.createdAt,
    this.status = MessageStatus.sent,
  });

  bool get isSystem => type == 'system';
  bool get isReaction => type == 'emoji_reaction';
  bool get isText => type == 'text';

  ChatMessage copyWith({
    String? id,
    String? roomId,
    String? userId,
    String? username,
    String? avatarUrl,
    String? content,
    String? type,
    DateTime? createdAt,
    MessageStatus? status,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      content: content ?? this.content,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> raw) {
    final json = (raw['payload'] is Map<String, dynamic>)
        ? raw['payload'] as Map<String, dynamic>
        : (raw['payload'] is Map)
            ? Map<String, dynamic>.from(raw['payload'] as Map)
            : raw;

    String senderName = 'Guest';
    String senderAvatar = '🦊';

    if (json['profiles'] is Map) {
      final profile = json['profiles'] as Map<String, dynamic>;
      senderName = profile['username'] as String? ?? 'Guest';
      senderAvatar = profile['avatar_url'] as String? ?? '🦊';
    } else if (json['profiles'] is List &&
        (json['profiles'] as List).isNotEmpty &&
        json['profiles'][0] is Map) {
      final profile = json['profiles'][0] as Map<String, dynamic>;
      senderName = profile['username'] as String? ?? 'Guest';
      senderAvatar = profile['avatar_url'] as String? ?? '🦊';
    } else if (json['username'] != null) {
      senderName = json['username'] as String? ?? 'Guest';
      senderAvatar = json['avatar_url'] as String? ?? '🦊';
    }

    final rawId = json['id'] as String?;
    final id = (rawId != null && rawId.isNotEmpty) ? rawId : const Uuid().v4();

    return ChatMessage(
      id: id,
      roomId: json['room_id'] as String? ?? '',
      userId: json['user_id'] as String?,
      username: senderName,
      avatarUrl: senderAvatar,
      content: json['content'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'room_id': roomId,
      if (userId != null) 'user_id': userId,
      'content': content,
      'type': type,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
