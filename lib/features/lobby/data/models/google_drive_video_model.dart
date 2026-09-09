class GoogleDriveVideo {
  final String id;
  final String title;
  final String ownerName;
  final String thumbnailUrl;
  final String duration;
  final String fileSize;
  final String category;
  final bool isPublic;

  const GoogleDriveVideo({
    required this.id,
    required this.title,
    this.ownerName = 'Google Drive Shared',
    this.thumbnailUrl = '',
    this.duration = '',
    this.fileSize = '',
    this.category = 'Umum',
    this.isPublic = true,
  });

  /// Full shareable Google Drive link
  String get url => 'https://drive.google.com/file/d/$id/view?usp=sharing';

  /// Embeddable preview link used by iframe / webview
  String get previewUrl => 'https://drive.google.com/file/d/$id/preview';

  /// Direct download stream link (subject to virus-scan warning on >100MB files)
  String get downloadUrl => 'https://drive.google.com/uc?export=download&id=$id';

  /// Google Drive thumbnail API URL
  String get driveThumbnailUrl => thumbnailUrl.isNotEmpty
      ? thumbnailUrl
      : 'https://drive.google.com/thumbnail?id=$id&sz=w640';

  factory GoogleDriveVideo.fromId(String id, {String? title}) {
    return GoogleDriveVideo(
      id: id,
      title: title ?? 'Google Drive Video ($id)',
      ownerName: 'Google Drive',
      category: 'Koleksi Drive',
    );
  }

  factory GoogleDriveVideo.fromJson(Map<String, dynamic> json) {
    return GoogleDriveVideo(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Video Google Drive',
      ownerName: json['owner_name'] as String? ?? 'Google Drive Shared',
      thumbnailUrl: json['thumbnail_url'] as String? ?? '',
      duration: json['duration'] as String? ?? '',
      fileSize: json['file_size'] as String? ?? '',
      category: json['category'] as String? ?? 'Umum',
      isPublic: json['is_public'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'owner_name': ownerName,
      'thumbnail_url': thumbnailUrl,
      'duration': duration,
      'file_size': fileSize,
      'category': category,
      'is_public': isPublic,
    };
  }
}
