import 'models/twitch_stream_model.dart';

class TwitchService {
  static final RegExp _twitchChannelRegex = RegExp(
    r'(?:https?:\/\/)?(?:www\.)?twitch\.tv\/([a-zA-Z0-9_]{3,25})(?:\/.*)?$',
    caseSensitive: false,
  );

  /// Ekstrak channel username dari URL Twitch atau string username mentah
  static String? extractChannel(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final match = _twitchChannelRegex.firstMatch(trimmed);
    if (match != null) {
      return match.group(1);
    }
    // Jika hanya alphanumeric dan underscore dengan panjang 3-25 karakter
    if (RegExp(r'^[a-zA-Z0-9_]{3,25}$').hasMatch(trimmed)) {
      return trimmed;
    }
    return null;
  }

  /// Preset terkurasi berbagai kategori stream Twitch populer dan stabil
  static final Map<String, List<TwitchStream>> categoryPresets = {
    'Populer & Live': [
      const TwitchStream(
        id: 'monstercat',
        title: 'Monstercat 24/7 Live Radio - Non-stop Dance & Electronic Music',
        channelTitle: 'Monstercat',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_monstercat-640x360.jpg',
        category: 'Musik',
        viewerCount: '1.4K penonton',
      ),
      const TwitchStream(
        id: 'riotgames',
        title: 'Riot Games Official Broadcast - LoL & Valorant Esports',
        channelTitle: 'Riot Games',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_riotgames-640x360.jpg',
        category: 'Esports',
        viewerCount: '45.2K penonton',
      ),
      const TwitchStream(
        id: 'eslcs',
        title: 'ESL CS:GO & CS2 Tournaments Official Stream',
        channelTitle: 'ESLcs',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_eslcs-640x360.jpg',
        category: 'Esports',
        viewerCount: '18.9K penonton',
      ),
      const TwitchStream(
        id: 'shroud',
        title: 'shroud - Tactical Shooters & Variety Chill Gaming',
        channelTitle: 'shroud',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_shroud-640x360.jpg',
        category: 'Gaming',
        viewerCount: '22.1K penonton',
      ),
      const TwitchStream(
        id: 'insomniac',
        title: 'Insomniac Events - Festival Livestreams & EDM Sets',
        channelTitle: 'Insomniac',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_insomniac-640x360.jpg',
        category: 'Musik',
        viewerCount: '3.8K penonton',
      ),
    ],
    'Musik & Radio 24/7': [
      const TwitchStream(
        id: 'monstercat',
        title: 'Monstercat 24/7 Live Radio - Non-stop Dance & Electronic Music',
        channelTitle: 'Monstercat',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_monstercat-640x360.jpg',
        category: 'Musik',
        viewerCount: '1.4K penonton',
      ),
      const TwitchStream(
        id: 'insomniac',
        title: 'Insomniac Events - Festival Livestreams & EDM Sets',
        channelTitle: 'Insomniac',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_insomniac-640x360.jpg',
        category: 'Musik',
        viewerCount: '3.8K penonton',
      ),
      const TwitchStream(
        id: 'anjuna',
        title: 'Anjunabeats & Anjunadeep 24/7 Radio',
        channelTitle: 'Anjuna',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_anjuna-640x360.jpg',
        category: 'Musik',
        viewerCount: '950 penonton',
      ),
      const TwitchStream(
        id: 'chillhopmusic',
        title: 'Chillhop Radio - jazzy & lofi hip hop beats',
        channelTitle: 'Chillhop Music',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_chillhopmusic-640x360.jpg',
        category: 'Musik',
        viewerCount: '2.1K penonton',
      ),
    ],
    'Esports & Turnamen': [
      const TwitchStream(
        id: 'riotgames',
        title: 'Riot Games Official Broadcast - LoL & Valorant Esports',
        channelTitle: 'Riot Games',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_riotgames-640x360.jpg',
        category: 'Esports',
        viewerCount: '45.2K penonton',
      ),
      const TwitchStream(
        id: 'eslcs',
        title: 'ESL CS:GO & CS2 Tournaments Official Stream',
        channelTitle: 'ESLcs',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_eslcs-640x360.jpg',
        category: 'Esports',
        viewerCount: '18.9K penonton',
      ),
      const TwitchStream(
        id: 'rocketleague',
        title: 'Rocket League Championship Series (RLCS)',
        channelTitle: 'RocketLeague',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_rocketleague-640x360.jpg',
        category: 'Esports',
        viewerCount: '12.4K penonton',
      ),
      const TwitchStream(
        id: 'dota2ti',
        title: 'The International - Official Dota 2 Championship',
        channelTitle: 'dota2ti',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_dota2ti-640x360.jpg',
        category: 'Esports',
        viewerCount: '31.0K penonton',
      ),
    ],
    'Gaming': [
      const TwitchStream(
        id: 'shroud',
        title: 'shroud - Tactical Shooters & Variety Chill Gaming',
        channelTitle: 'shroud',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_shroud-640x360.jpg',
        category: 'Gaming',
        viewerCount: '22.1K penonton',
      ),
      const TwitchStream(
        id: 'tarik',
        title: 'tarik - VALORANT Pro & Ranked Watch Party',
        channelTitle: 'tarik',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_tarik-640x360.jpg',
        category: 'Gaming',
        viewerCount: '28.5K penonton',
      ),
      const TwitchStream(
        id: 'summit1g',
        title: 'summit1g - Variety & FPS Gaming Stream',
        channelTitle: 'summit1g',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_summit1g-640x360.jpg',
        category: 'Gaming',
        viewerCount: '15.6K penonton',
      ),
      const TwitchStream(
        id: 'lirik',
        title: 'LIRIK - Daily Variety & Indie Gaming',
        channelTitle: 'LIRIK',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_lirik-640x360.jpg',
        category: 'Gaming',
        viewerCount: '19.4K penonton',
      ),
    ],
    'Just Chatting': [
      const TwitchStream(
        id: 'hasanabi',
        title: 'HasanAbi - News, Politics & Internet Culture Talk',
        channelTitle: 'HasanAbi',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_hasanabi-640x360.jpg',
        category: 'Just Chatting',
        viewerCount: '34.0K penonton',
      ),
      const TwitchStream(
        id: 'pokimane',
        title: 'pokimane - Chilling & Catching Up with Chat',
        channelTitle: 'pokimane',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_pokimane-640x360.jpg',
        category: 'Just Chatting',
        viewerCount: '16.8K penonton',
      ),
      const TwitchStream(
        id: 'ludwig',
        title: 'Ludwig - Game Shows, Events & Stories',
        channelTitle: 'Ludwig',
        thumbnailUrl:
            'https://static-cdn.jtvnw.net/previews-ttv/live_user_ludwig-640x360.jpg',
        category: 'Just Chatting',
        viewerCount: '21.3K penonton',
      ),
    ],
  };

  /// Mencari stream Twitch berdasarkan query atau URL channel
  static Future<List<TwitchStream>> search(String query, {int page = 1}) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      return categoryPresets['Populer & Live'] ?? [];
    }

    // Cek apakah query adalah channel URL atau valid username
    final channelFromInput = extractChannel(clean);
    final results = <TwitchStream>[];

    if (channelFromInput != null) {
      // Cari apakah sudah ada di preset
      TwitchStream? matchedPreset;
      for (final list in categoryPresets.values) {
        for (final stream in list) {
          if (stream.id.toLowerCase() == channelFromInput.toLowerCase()) {
            matchedPreset = stream;
            break;
          }
        }
        if (matchedPreset != null) break;
      }

      if (matchedPreset != null) {
        results.add(matchedPreset);
      } else {
        results.add(
          TwitchStream.fromId(
            id: channelFromInput.toLowerCase(),
            title: 'Twitch Channel: $channelFromInput',
            channelTitle: channelFromInput,
            category: 'Live Stream',
            viewerCount: 'Live',
          ),
        );
      }
    }

    // Filter preset berdasarkan kata kunci judul, nama channel, atau kategori
    final lower = clean.toLowerCase();
    for (final list in categoryPresets.values) {
      for (final stream in list) {
        if (stream.id.toLowerCase().contains(lower) ||
            stream.title.toLowerCase().contains(lower) ||
            stream.channelTitle.toLowerCase().contains(lower) ||
            stream.category.toLowerCase().contains(lower)) {
          if (!results.any((s) => s.id.toLowerCase() == stream.id.toLowerCase())) {
            results.add(stream);
          }
        }
      }
    }

    return results;
  }
}
