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
  final double? fps;
  final String? streamUrl;
  final bool isAuto;
  final QualityControlMode mode;
  final dynamic rawTrack;

  const VideoQuality({
    required this.id,
    required this.label,
    this.height,
    this.width,
    this.bitrate,
    this.fps,
    this.streamUrl,
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
        fps = null,
        streamUrl = null,
        isAuto = true,
        rawTrack = null;

  /// Factory constructor untuk video dengan kualitas tetap (Single MP4 atau File Lokal P2P)
  factory VideoQuality.fixed({
    String label = 'Kualitas Asli (Direct)',
    int? height,
    int? width,
    int? bitrate,
    double? fps,
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
      fps: fps,
      mode: QualityControlMode.fixedOriginal,
    );
  }

  /// Factory constructor untuk opsi Dailymotion
  factory VideoQuality.dailymotion(
    String q, {
    String? label,
    int? height,
    String? streamUrl,
  }) {
    if (q == 'auto') {
      return const VideoQuality.auto(
        label: 'Auto (Otomatis Dailymotion)',
        mode: QualityControlMode.webviewBridge,
      );
    }
    final clean = q.replaceAll(RegExp(r'[^0-9]'), '');
    final parsedHeight = height ?? (clean.isNotEmpty ? int.tryParse(clean) : null);
    return VideoQuality(
      id: q,
      label: label ?? (parsedHeight != null ? '${parsedHeight}p' : q),
      height: parsedHeight,
      streamUrl: streamUrl,
      mode: QualityControlMode.webviewBridge,
    );
  }

  /// Factory constructor untuk opsi Bstation
  factory VideoQuality.bstation({
    required String id,
    required String label,
    int? height,
    int? width,
    int? bitrate,
    double? fps,
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
      height: height ?? int.tryParse(id.replaceAll(RegExp(r'[^0-9]'), '')),
      width: width,
      bitrate: bitrate,
      fps: fps,
      mode: QualityControlMode.webviewBridge,
    );
  }

  /// Factory constructor untuk opsi Web Browser
  factory VideoQuality.webBrowser({
    required String id,
    required String label,
    int? height,
    int? width,
    int? bitrate,
    double? fps,
  }) {
    if (id == 'auto') {
      return const VideoQuality.auto(
        label: 'Auto (Otomatis Web)',
        mode: QualityControlMode.webviewBridge,
      );
    }
    return VideoQuality(
      id: id,
      label: label,
      height: height ?? int.tryParse(id.replaceAll(RegExp(r'[^0-9]'), '')),
      width: width,
      bitrate: bitrate,
      fps: fps,
      mode: QualityControlMode.webviewBridge,
    );
  }

  /// Factory constructor untuk opsi YouTube IFrame API
  factory VideoQuality.youtube(String code) {
    final clean = code.trim().toLowerCase();
    if (clean == 'auto' || clean == 'default' || clean.isEmpty) {
      return const VideoQuality.auto(
        label: 'Auto (Otomatis YouTube)',
        mode: QualityControlMode.embeddedUi,
      );
    }
    switch (clean) {
      case 'highres':
        return const VideoQuality(
          id: 'highres',
          label: '4320p (8K Ultra HD)',
          height: 4320,
          mode: QualityControlMode.embeddedUi,
        );
      case 'hd2880':
        return const VideoQuality(
          id: 'hd2880',
          label: '2880p (5K Ultra HD)',
          height: 2880,
          mode: QualityControlMode.embeddedUi,
        );
      case 'hd2160':
      case '2160':
        return const VideoQuality(
          id: 'hd2160',
          label: '2160p (4K Ultra HD)',
          height: 2160,
          mode: QualityControlMode.embeddedUi,
        );
      case 'hd1440':
      case '1440':
        return const VideoQuality(
          id: 'hd1440',
          label: '1440p (2K QHD)',
          height: 1440,
          mode: QualityControlMode.embeddedUi,
        );
      case 'hd1080':
      case '1080':
        return const VideoQuality(
          id: 'hd1080',
          label: '1080p (Full HD)',
          height: 1080,
          mode: QualityControlMode.embeddedUi,
        );
      case 'hd720':
      case '720':
        return const VideoQuality(
          id: 'hd720',
          label: '720p (HD)',
          height: 720,
          mode: QualityControlMode.embeddedUi,
        );
      case 'large':
      case '480':
        return const VideoQuality(
          id: 'large',
          label: '480p (SD)',
          height: 480,
          mode: QualityControlMode.embeddedUi,
        );
      case 'medium':
      case '360':
        return const VideoQuality(
          id: 'medium',
          label: '360p (Hemat Kuota)',
          height: 360,
          mode: QualityControlMode.embeddedUi,
        );
      case 'small':
      case '240':
        return const VideoQuality(
          id: 'small',
          label: '240p (Rendah)',
          height: 240,
          mode: QualityControlMode.embeddedUi,
        );
      case 'tiny':
      case '144':
        return const VideoQuality(
          id: 'tiny',
          label: '144p (Sangat Rendah)',
          height: 144,
          mode: QualityControlMode.embeddedUi,
        );
      default:
        final digits = clean.replaceAll(RegExp(r'[^0-9]'), '');
        final parsedH = digits.isNotEmpty ? int.tryParse(digits) : null;
        return VideoQuality(
          id: clean,
          label: parsedH != null ? '${parsedH}p' : code,
          height: parsedH,
          mode: QualityControlMode.embeddedUi,
        );
    }
  }

  /// Menormalisasi tinggi resolusi video dengan memperhitungkan video vertikal (9:16)
  /// serta rasio sinematik ultrawide (21:9, misal 1920x800 -> 1080p).
  static int? normalizeResolutionHeight({int? width, int? height}) {
    if ((height == null || height <= 0) && (width == null || width <= 0)) {
      return null;
    }
    if (width == null || width <= 0) return height;
    if (height == null || height <= 0) return width;

    final int shortSide = width < height ? width : height;
    final int longSide = width > height ? width : height;

    if (longSide >= 3800 && shortSide >= 1500 && shortSide <= 2160) {
      return 2160;
    }
    if (longSide >= 2500 && longSide < 3800 && shortSide >= 1000 && shortSide <= 1440) {
      return 1440;
    }
    if (longSide >= 1900 && longSide < 2500 && shortSide >= 750 && shortSide <= 1080) {
      return 1080;
    }
    if (longSide >= 1260 && longSide < 1900 && shortSide >= 500 && shortSide <= 720) {
      return 720;
    }
    if (longSide >= 840 && longSide < 1260 && shortSide >= 340 && shortSide <= 480) {
      return 480;
    }
    if (longSide >= 620 && longSide < 840 && shortSide >= 250 && shortSide <= 360) {
      return 360;
    }
    return shortSide;
  }

  /// Label ringkas untuk badge di UI (misal: "HD", "1080p", "Auto")
  String get shortLabel {
    if (isAuto) return 'Auto';
    if (id == 'original' || mode == QualityControlMode.fixedOriginal) {
      if (height != null && height! > 0) return '${height}p (Asli)';
      return 'Asli';
    }
    if (height != null && height! > 0) return '${height}p';
    if (id == 'hd2160' || id == '2160') return '2160p';
    if (id == 'hd1440' || id == '1440') return '1440p';
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
      if (height! >= 1440) return 'Quad HD 2K';
      if (height! >= 1080) return 'Full HD';
      if (height! >= 720) return 'HD Resolusi Tinggi';
      if (height! >= 480) return 'Standar Definition (SD)';
      if (height! >= 360) return 'Hemat Kuota';
      return 'Sangat Hemat Kuota';
    }
    if (id == 'highres' || id == 'hd2160' || id == '2160') return 'Ultra HD / 4K';
    if (id == 'hd1440' || id == '1440') return 'Quad HD 2K';
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
