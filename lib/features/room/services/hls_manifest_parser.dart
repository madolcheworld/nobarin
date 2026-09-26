import 'package:flutter/foundation.dart';
import '../../../core/network/app_http_client.dart';
import '../models/video_quality.dart';

/// Representasi satu varian stream dari Master Playlist HLS (`#EXT-X-STREAM-INF`).
class HlsVariantInfo {
  final int? width;
  final int? height;
  final int? bandwidth;
  final double? frameRate;
  final String? name;
  final String streamUrl;

  const HlsVariantInfo({
    this.width,
    this.height,
    this.bandwidth,
    this.frameRate,
    this.name,
    required this.streamUrl,
  });
}

/// Service untuk mendeteksi dan mem-parsing Master Playlist HLS (`.m3u8`)
/// agar daftar resolusi/bitrate video yang sebenarnya dapat ditampilkan tanpa hardcode.
class HlsManifestParser {
  /// Mengecek apakah URL mengarah ke stream HLS (`.m3u8`).
  static bool isHlsUrl(String url) {
    final lower = url.trim().toLowerCase();
    if (lower.isEmpty) return false;
    return lower.contains('.m3u8') ||
        lower.contains('application/x-mpegurl') ||
        lower.contains('vnd.apple.mpegurl');
  }

  /// Mengambil dan mem-parsing daftar kualitas dari URL Master Playlist `.m3u8`.
  /// Mengembalikan daftar kosong jika bukan Master Playlist atau gagal diakses.
  static Future<List<VideoQuality>> fetchAndParseQualities(String url) async {
    if (!isHlsUrl(url)) return const [];
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return const [];
    }

    try {
      final response = await AppHttpClient.get(
        uri,
        timeout: const Duration(seconds: 6),
        maxRetries: 1,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final parsed = parseMasterPlaylist(response.body, baseUri: uri);
        if (parsed.isNotEmpty) return parsed;
      }
    } catch (e) {
      debugPrint('[HlsManifestParser] Failed to fetch HLS manifest: $e');
    }

    // Fallback: jika URL merupakan varian resolusi langsung seperti .../480.m3u8?x=1
    // atau .../720.m3u8?x=1 (umum pada CDN streaming seperti playcdn), sediakan opsi
    // sibling kualitas (1080p, 720p, 480p, 360p).
    final siblingMatch = RegExp(
      r'^(https?://[^?#]+/)(360|480|720|1080)\.m3u8(\?.*)?$',
      caseSensitive: false,
    ).firstMatch(url.trim());
    if (siblingMatch != null) {
      final prefix = siblingMatch.group(1)!;
      final suffix = siblingMatch.group(3) ?? '';
      const heights = [1080, 720, 480, 360];
      return [
        const VideoQuality.auto(
          label: 'Auto (Otomatis)',
          mode: QualityControlMode.directTrack,
        ),
        for (final h in heights)
          VideoQuality(
            id: '$h',
            label: '${h}p',
            height: h,
            streamUrl: '$prefix$h.m3u8$suffix',
            mode: QualityControlMode.directTrack,
          ),
      ];
    }

    return const [];
  }

  /// Mem-parsing isi teks `.m3u8` Master Playlist menjadi daftar [VideoQuality].
  ///
  /// - Jika memiliki > 1 varian `#EXT-X-STREAM-INF`, mengembalikan `[Auto, ...varian terurut]`.
  /// - Jika hanya memiliki 1 varian `#EXT-X-STREAM-INF`, mengembalikan `[VideoQuality.fixed(...)]`.
  /// - Jika merupakan Media Playlist tunggal (hanya `#EXTINF` tanpa `#EXT-X-STREAM-INF`),
  ///   mengembalikan `[]` agar pemutar menanganinya sebagai single-track stream.
  static List<VideoQuality> parseMasterPlaylist(
    String content, {
    Uri? baseUri,
  }) {
    final variants = extractVariants(content, baseUri: baseUri);
    if (variants.isEmpty) return const [];

    if (variants.length == 1) {
      final v = variants.first;
      final normH = VideoQuality.normalizeResolutionHeight(
        width: v.width,
        height: v.height,
      );
      return [
        VideoQuality.fixed(
          label: (normH != null && normH > 0)
              ? '${normH}p (Kualitas Asli)'
              : (v.name ?? 'Kualitas Asli (Direct)'),
          height: normH,
          width: v.width,
          bitrate: v.bandwidth,
          fps: v.frameRate,
        ),
      ];
    }

    // Hitung jumlah kemunculan setiap tinggi resolusi untuk membedakan varian ber-resolusi sama
    final Map<int, int> heightCounts = {};
    for (final v in variants) {
      final normH = VideoQuality.normalizeResolutionHeight(
        width: v.width,
        height: v.height,
      );
      if (normH != null && normH > 0) {
        heightCounts[normH] = (heightCounts[normH] ?? 0) + 1;
      }
    }

    final List<VideoQuality> qualities = [
      const VideoQuality.auto(
        label: 'Auto (Otomatis)',
        mode: QualityControlMode.directTrack,
      ),
    ];

    final Set<String> seenIds = {'auto'};

    for (int i = 0; i < variants.length; i++) {
      final v = variants[i];
      final normH = VideoQuality.normalizeResolutionHeight(
        width: v.width,
        height: v.height,
      );
      final isDuplicateHeight =
          normH != null && (heightCounts[normH] ?? 0) > 1;

      String label;
      if (normH != null && normH > 0) {
        if (normH >= 2160) {
          label = '4K (${normH}p)';
        } else if (normH >= 1440) {
          label = '2K (${normH}p)';
        } else {
          label = '${normH}p';
        }
        if (v.frameRate != null && v.frameRate! >= 50) {
          label += ' ${v.frameRate!.round()}fps';
        }
        if (isDuplicateHeight && v.bandwidth != null && v.bandwidth! > 0) {
          final mbps = (v.bandwidth! / 1000000).toStringAsFixed(1);
          label += ' ($mbps Mbps)';
        }
      } else if (v.name != null && v.name!.isNotEmpty) {
        label = v.name!;
      } else if (v.bandwidth != null && v.bandwidth! > 0) {
        final kbps = (v.bandwidth! / 1000).round();
        label = '$kbps kbps';
      } else {
        label = 'Stream ${i + 1}';
      }

      // Gunakan ID unik berbasis tinggi/bandwidth atau indeks
      final String id = isDuplicateHeight
          ? '${normH}_${v.bandwidth ?? i}'
          : (normH != null ? '$normH' : 'hls_$i');

      if (!seenIds.contains(id)) {
        seenIds.add(id);
        qualities.add(
          VideoQuality(
            id: id,
            label: label,
            height: normH,
            width: v.width,
            bitrate: v.bandwidth,
            fps: v.frameRate,
            streamUrl: v.streamUrl,
            mode: QualityControlMode.directTrack,
          ),
        );
      }
    }

    qualities.sort((a, b) {
      if (a.isAuto) return -1;
      if (b.isAuto) return 1;
      final hCmp = (b.height ?? 0).compareTo(a.height ?? 0);
      if (hCmp != 0) return hCmp;
      return (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
    });

    return qualities;
  }

  /// Mengekstrak daftar [HlsVariantInfo] mentah dari konten `#EXT-X-STREAM-INF`.
  static List<HlsVariantInfo> extractVariants(
    String content, {
    Uri? baseUri,
  }) {
    if (!content.contains('#EXT-X-STREAM-INF')) return const [];

    final lines = content.split(RegExp(r'\r?\n'));
    final List<HlsVariantInfo> variants = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;

      final attrs = line.substring('#EXT-X-STREAM-INF:'.length);

      // Abaikaan stream khusus audio-only jika tidak memiliki resolusi dan memiliki codecs audio saja
      final codecsMatch = RegExp(r'CODECS="([^"]+)"', caseSensitive: false)
          .firstMatch(attrs);
      final resolutionMatch = RegExp(
        r'RESOLUTION=(\d+)x(\d+)',
        caseSensitive: false,
      ).firstMatch(attrs);

      if (resolutionMatch == null && codecsMatch != null) {
        final codecs = codecsMatch.group(1)!.toLowerCase();
        final hasVideoCodec = codecs.contains('avc1') ||
            codecs.contains('hev1') ||
            codecs.contains('hvc1') ||
            codecs.contains('vp09') ||
            codecs.contains('av01');
        if (!hasVideoCodec) {
          continue;
        }
      }

      int? width;
      int? height;
      if (resolutionMatch != null) {
        width = int.tryParse(resolutionMatch.group(1)!);
        height = int.tryParse(resolutionMatch.group(2)!);
      }

      final avgBwMatch = RegExp(
        r'AVERAGE-BANDWIDTH=(\d+)',
        caseSensitive: false,
      ).firstMatch(attrs);
      final bwMatch = RegExp(
        r'(?:^|,)BANDWIDTH=(\d+)',
        caseSensitive: false,
      ).firstMatch(attrs);
      final int? bandwidth = avgBwMatch != null
          ? int.tryParse(avgBwMatch.group(1)!)
          : (bwMatch != null ? int.tryParse(bwMatch.group(1)!) : null);

      final fpsMatch = RegExp(
        r'FRAME-RATE=([\d.]+)',
        caseSensitive: false,
      ).firstMatch(attrs);
      final double? frameRate =
          fpsMatch != null ? double.tryParse(fpsMatch.group(1)!) : null;

      final nameMatch = RegExp(
        r'NAME="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(attrs);
      final String? name = nameMatch?.group(1);

      // Cari baris berikutnya yang bukan komentar dan tidak kosong sebagai URL varian
      String? uriLine;
      for (int j = i + 1; j < lines.length; j++) {
        final candidate = lines[j].trim();
        if (candidate.isEmpty) continue;
        if (candidate.startsWith('#')) {
          // Jika bertemu tag STREAM-INF baru sebelum menemukan URI, hentikan pencarian
          if (candidate.startsWith('#EXT-X-STREAM-INF:')) break;
          continue;
        }
        uriLine = candidate;
        i = j;
        break;
      }

      if (uriLine == null || uriLine.isEmpty) continue;

      final resolvedUrl = baseUri != null
          ? baseUri.resolve(uriLine).toString()
          : uriLine;

      variants.add(
        HlsVariantInfo(
          width: width,
          height: height,
          bandwidth: bandwidth,
          frameRate: frameRate,
          name: name,
          streamUrl: resolvedUrl,
        ),
      );
    }

    return variants;
  }
}
