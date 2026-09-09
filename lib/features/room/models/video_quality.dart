/// Model representasi kualitas/resolusi video di aplikasi WatchParty.
class VideoQuality {
  final String id;
  final String label;
  final int? height;
  final int? bitrate;
  final bool isAuto;
  final dynamic rawTrack;

  const VideoQuality({
    required this.id,
    required this.label,
    this.height,
    this.bitrate,
    this.isAuto = false,
    this.rawTrack,
  });

  /// Factory / const constructor untuk opsi Auto / Otomatis
  const VideoQuality.auto({this.label = 'Auto (Otomatis)'})
      : id = 'auto',
        height = null,
        bitrate = null,
        isAuto = true,
        rawTrack = null;

  /// Label ringkas untuk badge di UI (misal: "HD", "1080p", "Auto")
  String get shortLabel {
    if (isAuto) return 'Auto';
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
    if (height != null) {
      if (height! >= 2160) return 'Ultra HD 4K';
      if (height! >= 1080) return 'Full HD';
      if (height! >= 720) return 'HD Resolusi Tinggi';
      if (height! >= 480) return 'Standar Definition (SD)';
      return 'Hemat Kuota';
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
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'VideoQuality(id: $id, label: $label, height: $height)';
}
