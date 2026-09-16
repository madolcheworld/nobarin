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
