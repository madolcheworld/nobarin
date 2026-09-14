class ApiConstants {
  // Supabase Configuration
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://afqauloszakvukebwzdl.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_QFrZVWOv5mzBQBUwjsKiCw_W15Zh5md',
  );

  // WebRTC P2P Voice Configuration
  static const String webrtcStunServer = String.fromEnvironment(
    'WEBRTC_STUN_SERVER',
    defaultValue: 'stun:stun.l.google.com:19302',
  );
  static const String webrtcTurnServer = String.fromEnvironment(
    'WEBRTC_TURN_SERVER',
    defaultValue: '',
  );
  static const String webrtcTurnUsername = String.fromEnvironment(
    'WEBRTC_TURN_USERNAME',
    defaultValue: '',
  );
  static const String webrtcTurnCredential = String.fromEnvironment(
    'WEBRTC_TURN_CREDENTIAL',
    defaultValue: '',
  );

  // Google OAuth / Drive Multi-platform Configuration
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );
  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  static Map<String, dynamic> get rtcIceConfiguration {
    final List<Map<String, dynamic>> iceServers = [
      {
        'urls': [
          webrtcStunServer,
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
          'stun:stun.cloudflare.com:3478',
        ],
      },
    ];
    if (webrtcTurnServer.isNotEmpty) {
      final turnConfig = <String, dynamic>{'urls': webrtcTurnServer};
      if (webrtcTurnUsername.isNotEmpty) {
        turnConfig['username'] = webrtcTurnUsername;
      }
      if (webrtcTurnCredential.isNotEmpty) {
        turnConfig['credential'] = webrtcTurnCredential;
      }
      iceServers.add(turnConfig);
    }
    return {
      'iceServers': iceServers,
    };
  }

  // Preset Media for Quick Playback
  static const List<Map<String, String>> presetMedia = [
    {
      'title': 'Oceans Nature (Direct MP4)',
      'type': 'direct_url',
      'url': 'https://vjs.zencdn.net/v/oceans.mp4',
    },
    {
      'title': 'Big Buck Bunny (HLS Stream)',
      'type': 'direct_url',
      'url': 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    },
    {
      'title': 'Sintel Trailer (Direct MP4)',
      'type': 'direct_url',
      'url': 'https://media.w3.org/2010/05/sintel/trailer.mp4',
    },
    {
      'title': 'Blender Big Buck Bunny (YouTube)',
      'type': 'youtube',
      'url': 'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
    },
    {
      'title': 'Lofi Hip Hop Stream Demo (YouTube)',
      'type': 'youtube',
      'url': 'https://www.youtube.com/watch?v=jfKfPfyJRdk',
    },
    {
      'title': 'Big Buck Bunny (Google Drive)',
      'type': 'google_drive',
      'url': 'https://drive.google.com/file/d/1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8/preview',
    },
    {
      'title': 'Tears of Steel 4K (Google Drive)',
      'type': 'google_drive',
      'url': 'https://drive.google.com/file/d/1A2b3C4d5E6f7G8h9I0jKlMnOpQrStUvW/preview',
    },
    {
      'title': 'Big Buck Bunny (Dailymotion)',
      'type': 'dailymotion',
      'url': 'https://www.dailymotion.com/video/x7tgad0',
    },
    {
      'title': 'Tears of Steel 4K (Dailymotion)',
      'type': 'dailymotion',
      'url': 'https://www.dailymotion.com/video/x8n6y2p',
    },
    {
      'title': 'Spy x Family Season 2 (Bstation)',
      'type': 'bstation',
      'url': 'https://www.bilibili.tv/id/video/2049971954',
    },
    {
      'title': 'Genshin Impact Concert (Bstation)',
      'type': 'bstation',
      'url': 'https://www.bilibili.com/video/BV14x411c7A2',
    },
  ];

  // Preset Avatars for Guest Profile
  static const List<String> presetAvatars = [
    '🦊',
    '🐼',
    '🚀',
    '⚡',
    '🎧',
    '👾',
    '🐱',
    '🦄',
    '🥑',
    '🥷',
    '🐯',
    '🔥',
  ];

  // Quick Emoji Reactions
  static const List<String> quickReactions = [
    '❤️',
    '😂',
    '🔥',
    '👏',
    '🍿',
    '🚀',
    '🎉',
    '😱',
  ];
}
