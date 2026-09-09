import 'models/bstation_video_model.dart';

class BstationService {
  static final RegExp _tvVideoRegex = RegExp(
    r'(?:https?:\/\/)?(?:www\.)?bilibili\.tv\/(?:id|en)\/video\/([0-9]+)',
    caseSensitive: false,
  );

  static final RegExp _tvPlayRegex = RegExp(
    r'(?:https?:\/\/)?(?:www\.)?bilibili\.tv\/(?:id|en)\/play\/([0-9]+(?:\/[0-9]+)?)',
    caseSensitive: false,
  );

  static final RegExp _comVideoRegex = RegExp(
    r'(?:https?:\/\/)?(?:www\.)?bilibili\.com\/video\/(BV[a-zA-Z0-9]+|av[0-9]+)',
    caseSensitive: false,
  );

  static final RegExp _shortRegex = RegExp(
    r'(?:https?:\/\/)?b23\.tv\/([a-zA-Z0-9]+)',
    caseSensitive: false,
  );

  /// Extract Bstation/Bilibili Video ID or Play ID from URL or raw ID
  static String? extractVideoId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // 1. Direct BV ID (e.g. BV1xx411c7mD)
    if (RegExp(r'^BV[a-zA-Z0-9]{10}$', caseSensitive: false).hasMatch(trimmed)) {
      return trimmed;
    }

    // 2. Direct Anime Play Path or numeric ID (e.g. 2117053 or 36571/30624556)
    if (RegExp(r'^\d+(?:\/\d+)?$').hasMatch(trimmed)) {
      return trimmed;
    }

    // 3. bilibili.tv /id/play/ or /en/play/ (with optional query params)
    final playMatch = _tvPlayRegex.firstMatch(trimmed);
    if (playMatch != null) {
      return playMatch.group(1);
    }

    // 4. bilibili.tv /id/video/ or /en/video/
    final tvMatch = _tvVideoRegex.firstMatch(trimmed);
    if (tvMatch != null) {
      return tvMatch.group(1);
    }

    // 5. bilibili.com /video/
    final comMatch = _comVideoRegex.firstMatch(trimmed);
    if (comMatch != null) {
      return comMatch.group(1);
    }

    // 6. b23.tv short link
    final shortMatch = _shortRegex.firstMatch(trimmed);
    if (shortMatch != null) {
      return shortMatch.group(1);
    }

    return null;
  }

  /// Curated presets grouped by anime and creative categories
  static final Map<String, List<BstationVideo>> categoryPresets = {
    'Anime Populer': [
      const BstationVideo(
        id: '2117053',
        title: 'Kisah Penggembala Dewa (Tales of Herding Gods)',
        description: 'Di Desa Can Lao yang terpencil, Qin Mu dibesarkan oleh sembilan tetua misterius. Petualangan magis di tanah para dewa yang penuh aksi spektakuler.',
        uploaderName: 'Bstation Anime Hub',
        thumbnailUrl: 'https://pic.bstarstatic.com/ogv/bac6048b713c32beea4a489e6be4a38c.png@720w_405h_1e_1c_90q.webp',
        durationSeconds: 1200,
        viewsTotal: 40100000,
        category: 'Anime Populer',
        episodeNumber: 'EP 01',
      ),
      const BstationVideo(
        id: '36571/30624556',
        title: "A Mortal's Journey to Immortality (Fanren Xiu Xian Chuan)",
        description: 'Perjalanan pemuda desa biasa Han Li melangkah di jalan kultivasi abadi yang penuh bahaya dan intrik.',
        uploaderName: 'Bstation Official',
        thumbnailUrl: 'https://pic.bstarstatic.com/ogv/84b5173bdb997d1d3bf1828fa2a440d4.png',
        durationSeconds: 1320,
        viewsTotal: 56900000,
        category: 'Anime Populer',
        episodeNumber: 'EP 190',
      ),
      const BstationVideo(
        id: '2410921/30654199',
        title: 'Penguasa Tertinggi Sepanjang Masa: Li Yunxiao',
        description: 'Kaisar Bela Diri legendaris bereinkarnasi 15 tahun kemudian dalam tubuh pemuda berbakat yang harus bangkit kembali ke puncak kejayaan.',
        uploaderName: 'Ani-One Asia',
        thumbnailUrl: 'https://pic.bstarstatic.com/ogv/fae86f3b72da36feed0e31d764c2c897.png',
        durationSeconds: 1260,
        viewsTotal: 327000,
        category: 'Anime Populer',
        episodeNumber: 'EP 16',
      ),
      const BstationVideo(
        id: '2315270/26461480',
        title: 'Aliens Among Immortals',
        description: 'Petualangan aksi fiksi ilmiah kultivasi menakjubkan dengan animasi CGI mutakhir.',
        uploaderName: 'Muse Asia',
        thumbnailUrl: 'https://pic.bstarstatic.com/ogv/6e3ac0aee83e74acce24378d8c6b3f3f62240f74.png',
        durationSeconds: 1140,
        viewsTotal: 371000,
        category: 'Anime Populer',
        episodeNumber: 'EP 59',
      ),
      const BstationVideo(
        id: '2411218/30661758',
        title: 'Fabulous Beasts: Season 6 (Wan Sheng Jie)',
        description: 'Kisah komedi kehidupan sehari-hari monster dan iblis lucu yang tinggal bersama di apartemen modern.',
        uploaderName: 'Bstation Premiere',
        thumbnailUrl: 'https://pic.bstarstatic.com/ogv/88c478a9abac1208e9ad20893e14a083.png',
        durationSeconds: 600,
        viewsTotal: 36300,
        category: 'Anime Populer',
        episodeNumber: 'EP 07',
      ),
    ],
    'Trending & Kreator': [
      const BstationVideo(
        id: 'BV1xx411c7mD',
        title: 'Rick Astley - Never Gonna Give You Up (Official Music Video)',
        description: 'Video musik ikonik legendaris di platform Bilibili dengan jutaan pemutaran dan komentar danmaku.',
        uploaderName: 'Rick Astley Official',
        thumbnailUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=800&auto=format&fit=crop&q=80',
        durationSeconds: 213,
        viewsTotal: 89000000,
        category: 'Trending & Kreator',
        episodeNumber: 'MV',
      ),
      const BstationVideo(
        id: 'BV14x411c7A2',
        title: 'Genshin Impact Concert - Melodies of an Endless Journey',
        description: 'Konser simfoni orkestra spektakuler membawakan soundtrack orisinal Teyvat dengan animasi visual memukau.',
        uploaderName: 'Genshin Impact Official',
        thumbnailUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=800&auto=format&fit=crop&q=80',
        durationSeconds: 4200,
        viewsTotal: 1750000,
        category: 'Trending & Kreator',
        episodeNumber: 'LIVE',
      ),
      const BstationVideo(
        id: 'BV1Pt411z7bW',
        title: 'Bilibili ACG World Creator Expo & Cosplay Highlights',
        description: 'Kompilasi keseruan pameran anime, cosplayer profesional, dan pertunjukan panggung terbesar Bilibili.',
        uploaderName: 'Bilibili ACG Channel',
        thumbnailUrl: 'https://images.unsplash.com/photo-1566737236500-c8ac43014a67?w=800&auto=format&fit=crop&q=80',
        durationSeconds: 1120,
        viewsTotal: 960000,
        category: 'Trending & Kreator',
      ),
    ],
    'AMV & Musik': [
      const BstationVideo(
        id: 'BV1b5411b7m7',
        title: 'YOASOBI - Idol (Oshi no Ko OP) Official Animated MV',
        description: 'Video musik animasi lengkap lagu hit sensasional Idol karya YOASOBI untuk serial Oshi no Ko.',
        uploaderName: 'YOASOBI Official Music',
        thumbnailUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=800&auto=format&fit=crop&q=80',
        durationSeconds: 228,
        viewsTotal: 8400000,
        category: 'AMV & Musik',
        episodeNumber: 'MV',
      ),
      const BstationVideo(
        id: 'BV1GJ411x7h7',
        title: 'RADWIMPS feat. Toaka - Suzume Anime Theme Song',
        description: 'Lagu tema emosional film animasi mahakarya Makoto Shinkai "Suzume no Tojimari".',
        uploaderName: 'CoMix Wave Films',
        thumbnailUrl: 'https://images.unsplash.com/photo-1511735111819-9a3f7709049c?w=800&auto=format&fit=crop&q=80',
        durationSeconds: 245,
        viewsTotal: 3650000,
        category: 'AMV & Musik',
        episodeNumber: 'MV',
      ),
      const BstationVideo(
        id: 'BV14b411P7kZ',
        title: 'Aimer - Zankyou Sanka (Demon Slayer Entertainment District OP)',
        description: 'Penampilan memukau video musik Zankyou Sanka dengan nuansa visual gemerlap.',
        uploaderName: 'SACRA MUSIC',
        thumbnailUrl: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=800&auto=format&fit=crop&q=80',
        durationSeconds: 215,
        viewsTotal: 2980000,
        category: 'AMV & Musik',
        episodeNumber: 'MV',
      ),
    ],
    'Komedi & Parodi': [
      const BstationVideo(
        id: 'BV1xx411c7mD',
        title: 'Never Gonna Give You Up - ACG Community Meme Edition',
        description: 'Kompilasi meme legendaris dan parodi animasi terpopuler di komunitas Bilibili.',
        uploaderName: 'Meme ACG Lab',
        thumbnailUrl: 'https://images.unsplash.com/photo-1579783902614-a3fb3927b675?w=800&auto=format&fit=crop&q=80',
        durationSeconds: 430,
        viewsTotal: 2430000,
        category: 'Komedi & Parodi',
      ),
      const BstationVideo(
        id: '2411218/30661758',
        title: 'Fabulous Beasts (Wan Sheng Jie) - Momen Paling Lucu',
        description: 'Kumpulan kelucuan para monster dan iblis di kota metropolitan.',
        uploaderName: 'Anime Fun Corner',
        thumbnailUrl: 'https://images.unsplash.com/photo-1531306728370-e2ebd9d7bb99?w=800&auto=format&fit=crop&q=80',
        durationSeconds: 520,
        viewsTotal: 1870000,
        category: 'Komedi & Parodi',
      ),
    ],
  };

  /// All preset videos combined
  static List<BstationVideo> get allPresets {
    final List<BstationVideo> all = [];
    final seenIds = <String>{};
    for (final list in categoryPresets.values) {
      for (final v in list) {
        if (seenIds.add(v.id)) {
          all.add(v);
        }
      }
    }
    return all;
  }

  /// Returns videos for a category
  static List<BstationVideo> getPresetsForCategory(String category) {
    if (category.isEmpty || category == 'Semua') {
      return allPresets;
    }
    return categoryPresets[category] ?? allPresets;
  }

  /// Search videos locally from catalog or presets
  static Future<List<BstationVideo>> searchVideos(
    String query, {
    int limit = 15,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return allPresets;
    }

    final lower = trimmed.toLowerCase();
    final results = allPresets.where((video) {
      return video.title.toLowerCase().contains(lower) ||
          video.description.toLowerCase().contains(lower) ||
          video.uploaderName.toLowerCase().contains(lower) ||
          video.category.toLowerCase().contains(lower) ||
          video.id.toLowerCase().contains(lower);
    }).take(limit).toList();

    return results;
  }

  /// Search alias for consistency with other services
  static Future<List<BstationVideo>> search(
    String query, {
    int limit = 15,
  }) =>
      searchVideos(query, limit: limit);

  /// Fetch single video details by ID or URL
  static Future<BstationVideo?> fetchVideoDetails(String input) async {
    final id = extractVideoId(input) ?? input.trim();
    if (id.isEmpty) return null;

    // Check presets first
    for (final v in allPresets) {
      if (v.id.toLowerCase() == id.toLowerCase()) {
        return v;
      }
    }

    return BstationVideo.fromId(id);
  }
}
