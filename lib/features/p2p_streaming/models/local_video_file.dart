import 'dart:typed_data';

class LocalVideoFile {
  final String id;
  final String name;
  final String? path;
  final Uint8List? bytes;
  final int size;
  final String mimeType;
  final String extension;

  const LocalVideoFile({
    required this.id,
    required this.name,
    this.path,
    this.bytes,
    required this.size,
    required this.mimeType,
    required this.extension,
  });

  /// Human-readable file size format (e.g. "1.24 GB", "450.0 MB")
  String get formattedSize {
    if (size <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double s = size.toDouble();
    while (s >= 1024 && i < suffixes.length - 1) {
      s /= 1024;
      i++;
    }
    return '${s.toStringAsFixed(s >= 100 ? 0 : 1)} ${suffixes[i]}';
  }

  /// Automatically guess MIME type from file extension
  static String guessMimeType(String ext) {
    final lower = ext.toLowerCase().replaceAll('.', '');
    switch (lower) {
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'ts':
        return 'video/mp2t';
      case 'flv':
        return 'video/x-flv';
      default:
        return 'video/mp4';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'size': size,
        'mimeType': mimeType,
        'extension': extension,
      };

  factory LocalVideoFile.fromJson(Map<String, dynamic> json, {String? path, Uint8List? bytes}) {
    return LocalVideoFile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Local Video',
      path: path,
      bytes: bytes,
      size: (json['size'] as num?)?.toInt() ?? 0,
      mimeType: json['mimeType'] as String? ?? 'video/mp4',
      extension: json['extension'] as String? ?? 'mp4',
    );
  }

  /// Tries to parse a p2p:// URI string into a LocalVideoFile instance
  static LocalVideoFile? tryFromP2pUri(String url) {
    if (!url.startsWith('p2p://')) return null;
    try {
      final uri = Uri.parse(url);
      final id = uri.host.isNotEmpty
          ? uri.host
          : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
      final title = uri.queryParameters['title'] ?? 'Local Video';
      final path = uri.queryParameters['path'];
      final ext = title.contains('.') ? title.split('.').last : 'mp4';
      return LocalVideoFile(
        id: id,
        name: title,
        path: path,
        size: 0,
        mimeType: guessMimeType(ext),
        extension: ext,
      );
    } catch (_) {
      return null;
    }
  }
}
