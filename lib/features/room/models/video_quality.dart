/// Mode kontrol kualitas video berdasarkan sumber media.
enum QualityControlMode {
  /// Track langsung (MediaKit Native atau HLS.js di Web)
  directTrack,

  /// Bridge WebView (Dailymotion atau Bstation)
  webviewBridge,

  /// Player adaptif dengan kontrol bawaan (YouTube iframe)
  embeddedUi,

  /// File statis tunggal tanpa variasi bitrate (MP4 langsung / P2P file lokal)
  fixedOriginal,
}

/// Model representasi kualitas/resolusi video di aplikasi WatchParty.
class VideoQuality {
  final String id;
  final String label;
  final int? height;
  final int? width;
  final int? bitrate;
  final bool isAuto;
  final QualityControlMode mode;
  final dynamic rawTrack;

  const VideoQuality({
    required this.id,
    required this.label,
    this.height,
    this.width,
    this.bitrate,
    this.isAuto = false,
    this.mode = QualityControlMode.directTrack,
    this.rawTrack,
  });

  /// Factory / const constructor untuk opsi Auto / Otomatis
  const VideoQuality.auto({
    this.label = 'Auto (Otomatis)',
    this.mode = QualityControlMode.directTrack,
  })  : id = 'auto',
        height = null,
        width = null,
        bitrate = null,
        isAuto = true,
        rawTrack = null;

  /// Factory constructor untuk video dengan kualitas tetap (Single MP4 atau File Lokal P2P)
  factory VideoQuality.fixed({
    String label = 'Kualitas Asli (Direct)',
    int? height,
    int? width,
    int? bitrate,
  }) {
    final finalLabel = height != null && height > 0
        ? '${height}p (Kualitas Asli)'
        : label;
    return VideoQuality(
      id: 'original',
      label: finalLabel,
      height: height,
      width: width,
      bitrate: bitrate,
      mode: QualityControlMode.fixedOriginal,
    );
  }

  /// Factory constructor untuk opsi Dailymotion
  factory VideoQuality.dailymotion(String q) {
    if (q == 'auto') {
      return const VideoQuality.auto(
        label: 'Auto (Otomatis Dailymotion)',
        mode: QualityControlMode.webviewBridge,
      );
    }
    final clean = q.replaceAll(RegExp(r'[^0-9]'), '');
    final parsedHeight = clean.isNotEmpty ? int.tryParse(clean) : null;
    return VideoQuality(
      id: q,
      label: parsedHeight != null ? '${parsedHeight}p' : q,
      height: parsedHeight,
      mode: QualityControlMode.webviewBridge,
    );
  }

  /// Factory constructor untuk opsi Bstation
  factory VideoQuality.bstation({
    required String id,
    required String label,
    int? height,
  }) {
    if (id == 'auto') {
      return const VideoQuality.auto(
        label: 'Auto (Otomatis Bstation)',
        mode: QualityControlMode.webviewBridge,
      );
    }
    return VideoQuality(
      id: id,
      label: label,
      height: height,
      mode: QualityControlMode.webviewBridge,
    );
  }

  /// Label ringkas untuk badge di UI (misal: "HD", "1080p", "Auto")
  String get shortLabel {
    if (isAuto) return 'Auto';
    if (id == 'original' || mode == QualityControlMode.fixedOriginal) {
      if (height != null && height! > 0) return '${height}p (Asli)';
      return 'Asli';
    }
    if (height != null && height! > 0) return '${height}p';
    if (id == 'hd1080' || id == '1080') return '1080p';
    if (id == 'hd720' || id == '720') return '720p';
    if (id == 'large' || id == '480') return '480p';
    if (id == 'medium' || id == '360') return '360p';
    if (id == 'small' || id == '240') return '240p';
    if (id == 'tiny' || id == '144') return '144p';
    if (id == 'highres') return '4K';
    return label;
  }

  /// Keterangan tambahan (misal: "Full HD", "Hemat Data", dll.)
  String get badgeDescription {
    if (isAuto) return 'Menyesuaikan koneksi internet';
    if (id == 'original' || mode == QualityControlMode.fixedOriginal) {
      return 'File diputar langsung tanpa kompresi ulang (Paling efisien)';
    }
    if (height != null) {
      if (height! >= 2160) return 'Ultra HD 4K';
      if (height! >= 1080) return 'Full HD';
      if (height! >= 720) return 'HD Resolusi Tinggi';
      if (height! >= 480) return 'Standar Definition (SD)';
      if (height! >= 360) return 'Hemat Kuota';
      return 'Sangat Hemat Kuota';
    }
    if (id == 'highres') return 'Ultra HD / 4K';
    if (id == 'hd1080' || id == '1080') return 'Full HD';
    if (id == 'hd720' || id == '720') return 'HD Resolusi Tinggi';
    if (id == 'large' || id == '480') return 'Standar Definition (SD)';
    if (id == 'medium' || id == '360') return 'Hemat Kuota';
    if (id == 'small' || id == '240' || id == 'tiny' || id == '144') {
      return 'Sangat Hemat Kuota';
    }
    return '';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoQuality &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          mode == other.mode;

  @override
  int get hashCode => Object.hash(id, mode);

  @override
  String toString() =>
      'VideoQuality(id: $id, label: $label, height: $height, mode: $mode)';
}
