import 'dart:convert';

/// Model representing a connected Google Drive user account.
class GoogleDriveAccount {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? accessToken;
  final bool isMock;

  const GoogleDriveAccount({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.accessToken,
    this.isMock = false,
  });

  GoogleDriveAccount copyWith({
    String? id,
    String? email,
    String? displayName,
    String? photoUrl,
    String? accessToken,
    bool? isMock,
  }) {
    return GoogleDriveAccount(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      accessToken: accessToken ?? this.accessToken,
      isMock: isMock ?? this.isMock,
    );
  }

  factory GoogleDriveAccount.fromGoogleSignIn({
    required String id,
    required String email,
    required String displayName,
    String? photoUrl,
    String? accessToken,
  }) {
    return GoogleDriveAccount(
      id: id,
      email: email,
      displayName: displayName,
      photoUrl: photoUrl,
      accessToken: accessToken,
      isMock: false,
    );
  }

  factory GoogleDriveAccount.mockDemo({
    String name = 'Pengguna Google Drive',
    String email = 'user.drive@gmail.com',
  }) {
    return GoogleDriveAccount(
      id: 'mock_gdrive_user_99',
      email: email,
      displayName: name,
      photoUrl: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=160&q=80',
      accessToken: 'mock_access_token_xyz',
      isMock: true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'display_name': displayName,
      'photo_url': photoUrl,
      'access_token': accessToken,
      'is_mock': isMock,
    };
  }

  factory GoogleDriveAccount.fromMap(Map<String, dynamic> map) {
    return GoogleDriveAccount(
      id: map['id'] as String? ?? '',
      email: map['email'] as String? ?? '',
      displayName: map['display_name'] as String? ?? 'Akun Google Drive',
      photoUrl: map['photo_url'] as String?,
      accessToken: map['access_token'] as String?,
      isMock: map['is_mock'] as bool? ?? false,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory GoogleDriveAccount.fromJson(String source) =>
      GoogleDriveAccount.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
