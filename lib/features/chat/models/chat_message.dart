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
  final Map<String, List<String>> reactions; // emoji -> list of userIds
  final String? replyToId;
  final String? replyToUsername;
  final String? replyToContent;

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
    this.reactions = const {},
    this.replyToId,
    this.replyToUsername,
    this.replyToContent,
  });

  factory ChatMessage.text({
    required String id,
    required String roomId,
    String? userId,
    String username = 'Guest',
    String avatarUrl = '🦊',
    required String content,
    DateTime? createdAt,
    MessageStatus status = MessageStatus.sent,
    Map<String, List<String>> reactions = const {},
    String? replyToId,
    String? replyToUsername,
    String? replyToContent,
  }) {
    return ChatMessage(
      id: id,
      roomId: roomId,
      userId: userId,
      username: username,
      avatarUrl: avatarUrl,
      content: content,
      type: 'text',
      createdAt: createdAt ?? DateTime.now(),
      status: status,
      reactions: reactions,
      replyToId: replyToId,
      replyToUsername: replyToUsername,
      replyToContent: replyToContent,
    );
  }

  bool get isSystem => type == 'system';
  bool get isReaction => type == 'emoji_reaction';
  bool get isText => type == 'text';
  bool get hasReactions => reactions.isNotEmpty;
  bool get isReply => replyToId != null && replyToId!.isNotEmpty;
  int get totalReactionsCount =>
      reactions.values.fold(0, (sum, list) => sum + list.length);

  bool hasUserReacted(String emoji, String userId) {
    return reactions[emoji]?.contains(userId) ?? false;
  }

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
    Map<String, List<String>>? reactions,
    String? replyToId,
    String? replyToUsername,
    String? replyToContent,
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
      reactions: reactions ?? this.reactions,
      replyToId: replyToId ?? this.replyToId,
      replyToUsername: replyToUsername ?? this.replyToUsername,
      replyToContent: replyToContent ?? this.replyToContent,
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

    if (json['sender_name'] != null &&
        json['sender_name'].toString().trim().isNotEmpty) {
      senderName = json['sender_name'] as String;
      senderAvatar = json['sender_avatar'] as String? ?? '🦊';
    } else if (json['profiles'] is Map) {
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

    final Map<String, List<String>> parsedReactions = {};
    if (json['reactions'] is Map) {
      (json['reactions'] as Map).forEach((key, value) {
        if (value is List) {
          parsedReactions[key.toString()] =
              value.map((e) => e.toString()).toList();
        }
      });
    }

    return ChatMessage(
      id: id,
      roomId: json['room_id'] as String? ?? '',
      userId: json['user_id'] as String?,
      username: senderName,
      avatarUrl: senderAvatar,
      content: json['content'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      reactions: parsedReactions,
      replyToId: json['reply_to_id'] as String?,
      replyToUsername: json['reply_to_username'] as String?,
      replyToContent: json['reply_to_content'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'room_id': roomId,
      if (userId != null) 'user_id': userId,
      'sender_name': username,
      'sender_avatar': avatarUrl,
      'content': content,
      'type': type,
      'created_at': createdAt.toIso8601String(),
      if (reactions.isNotEmpty) 'reactions': reactions,
      if (replyToId != null && replyToId!.isNotEmpty) 'reply_to_id': replyToId,
      if (replyToUsername != null && replyToUsername!.isNotEmpty)
        'reply_to_username': replyToUsername,
      if (replyToContent != null && replyToContent!.isNotEmpty)
        'reply_to_content': replyToContent,
    };
  }
}
