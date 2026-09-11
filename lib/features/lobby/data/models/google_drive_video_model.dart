import 'playable_media_item.dart';

class GoogleDriveVideo implements PlayableMediaItem {
  @override
  final String id;
  @override
  final String title;
  final String ownerName;
  @override
  String get author => ownerName;
  @override
  final String thumbnailUrl;
  @override
  final String duration;
  final String fileSize;
  final String category;
  final bool isPublic;
  @override
  String get mediaType => 'google_drive';

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
  @override
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

  GoogleDriveVideo copyWith({
    String? id,
    String? title,
    String? ownerName,
    String? thumbnailUrl,
    String? duration,
    String? fileSize,
    String? category,
    bool? isPublic,
  }) {
    return GoogleDriveVideo(
      id: id ?? this.id,
      title: title ?? this.title,
      ownerName: ownerName ?? this.ownerName,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      duration: duration ?? this.duration,
      fileSize: fileSize ?? this.fileSize,
      category: category ?? this.category,
      isPublic: isPublic ?? this.isPublic,
    );
  }

  factory GoogleDriveVideo.fromDriveApiJson(
    Map<String, dynamic> json, {
    String owner = 'Google Drive Saya',
  }) {
    final fileId = json['id'] as String? ?? '';
    final fileName = json['name'] as String? ?? 'Video Google Drive';

    // Parse thumbnail link
    String thumb = json['thumbnailLink'] as String? ?? '';
    if (thumb.isEmpty && fileId.isNotEmpty) {
      thumb = 'https://drive.google.com/thumbnail?id=$fileId&sz=w640';
    }

    // Parse duration from videoMediaMetadata
    String dur = '';
    final videoMeta = json['videoMediaMetadata'] as Map<String, dynamic>?;
    if (videoMeta != null && videoMeta['durationMillis'] != null) {
      final millis = int.tryParse(videoMeta['durationMillis'].toString()) ?? 0;
      dur = _formatDuration(millis);
    }

    // Parse size
    String formattedSize = '';
    if (json['size'] != null) {
      final bytes = int.tryParse(json['size'].toString()) ?? 0;
      formattedSize = _formatFileSize(bytes);
    }

    // Check if permission includes 'anyone'
    bool publicAccess = false;
    final perms = json['permissions'] as List<dynamic>?;
    if (perms != null) {
      publicAccess = perms.any((p) {
        if (p is Map<String, dynamic>) {
          return p['type'] == 'anyone';
        }
        return false;
      });
    }

    return GoogleDriveVideo(
      id: fileId,
      title: fileName,
      ownerName: owner,
      thumbnailUrl: thumb,
      duration: dur.isNotEmpty ? dur : 'Drive Video',
      fileSize: formattedSize.isNotEmpty ? formattedSize : 'Cloud Media',
      category: 'Drive Saya',
      isPublic: publicAccess,
    );
  }

  static String _formatDuration(int millis) {
    if (millis <= 0) return '00:00';
    final duration = Duration(milliseconds: millis);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  static String _formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
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
