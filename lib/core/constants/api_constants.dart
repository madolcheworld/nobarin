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

  static Map<String, dynamic> get rtcIceConfiguration {
    final List<Map<String, dynamic>> iceServers = [
      {'urls': webrtcStunServer},
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
