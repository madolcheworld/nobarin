class P2pConstants {
  const P2pConstants._();

  /// WebRTC DataChannel label used for P2P video streaming
  static const String dataChannelLabel = 'p2p_video_stream';

  /// Supabase Realtime broadcast event names
  static const String eventAnnounce = 'P2P_STREAM_ANNOUNCE';
  static const String eventOffline = 'P2P_STREAM_OFFLINE';
  static const String eventSignalOffer = 'P2P_STREAM_OFFER';
  static const String eventSignalAnswer = 'P2P_STREAM_ANSWER';
  static const String eventSignalIce = 'P2P_STREAM_ICE';

  /// Message types inside WebRTC DataChannel
  static const String msgMetadataReq = 'METADATA_REQ';
  static const String msgMetadataRes = 'METADATA_RES';
  static const String msgChunkReq = 'CHUNK_REQ';
  static const String msgChunkEof = 'CHUNK_EOF';
  static const String msgPing = 'PING';
  static const String msgPong = 'PONG';

  /// Chunk size for binary streaming over WebRTC (64 KB)
  static const int chunkSize = 64 * 1024;

  /// High watermark for RTCDataChannel bufferedAmount (2 MB)
  static const int maxBufferedAmount = 2 * 1024 * 1024;

  /// Default viewer proxy loopback port (0 = OS assigns random free port)
  static const int defaultProxyPort = 0;
}
