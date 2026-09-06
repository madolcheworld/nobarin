class UserProfile {
  final String id;
  final String username;
  final String avatarUrl;
  final bool isGuest;
  final DateTime? createdAt;

  const UserProfile({
    required this.id,
    required this.username,
    this.avatarUrl = '🦊',
    this.isGuest = true,
    this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String? ?? 'Guest',
      avatarUrl: json['avatar_url'] as String? ?? '🦊',
      isGuest: json['is_guest'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'avatar_url': avatarUrl,
      'is_guest': isGuest,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  UserProfile copyWith({
    String? id,
    String? username,
    String? avatarUrl,
    bool? isGuest,
    DateTime? createdAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isGuest: isGuest ?? this.isGuest,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          username == other.username &&
          avatarUrl == other.avatarUrl &&
          isGuest == other.isGuest;

  @override
  int get hashCode =>
      id.hashCode ^ username.hashCode ^ avatarUrl.hashCode ^ isGuest.hashCode;
}
