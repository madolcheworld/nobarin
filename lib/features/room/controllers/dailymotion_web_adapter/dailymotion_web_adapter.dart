import 'package:flutter/widgets.dart';
import '../../models/video_quality.dart';
import 'dailymotion_web_adapter_stub.dart'
    if (dart.library.js_interop) 'dailymotion_web_adapter_web.dart' as impl;

/// Cross-platform abstraction for playing Dailymotion videos via iframe & postMessage API on web.
abstract class DailymotionWebAdapter {
  /// Whether DailymotionWebAdapter is supported in the current runtime platform.
  static bool get isSupported => impl.isSupported;

  /// Factory to instantiate DailymotionWebAdapter when running on web.
  static DailymotionWebAdapter? create({
    required void Function(double position) onPositionChanged,
    required void Function(double duration) onDurationChanged,
    required void Function(bool isPlaying) onPlayingChanged,
    required void Function() onPlaybackEnded,
    required void Function(String error) onError,
    void Function(List<VideoQuality> qualities)? onQualitiesChanged,
    void Function(VideoQuality quality)? onQualitySelectedChanged,
    void Function(int width, int height)? onResolutionChanged,
  }) {
    if (!impl.isSupported) return null;
    return impl.createDailymotionWebAdapter(
      onPositionChanged: onPositionChanged,
      onDurationChanged: onDurationChanged,
      onPlayingChanged: onPlayingChanged,
      onPlaybackEnded: onPlaybackEnded,
      onError: onError,
      onQualitiesChanged: onQualitiesChanged,
      onQualitySelectedChanged: onQualitySelectedChanged,
      onResolutionChanged: onResolutionChanged,
    );
  }

  /// Builds the PlatformView widget for embedding in the Flutter tree.
  Widget buildPlayerWidget();

  /// Loads Dailymotion video by ID or URL and applies initial autoplay & start position.
  Future<void> load(
    String videoId, {
    bool autoPlay = false,
    double startSeconds = 0.0,
  });

  /// Plays the video.
  Future<void> play();

  /// Pauses the video.
  Future<void> pause();

  /// Seeks to specified position in seconds.
  Future<void> seekTo(double seconds);

  /// Sets playback speed (e.g. 0.5 - 2.0).
  Future<void> setPlaybackSpeed(double speed);

  /// Sets audio volume (0.0 to 1.0).
  Future<void> setVolume(double volume);

  /// Mutes or unmutes audio.
  Future<void> setMuted(bool muted);

  /// Whether the video is currently muted.
  bool get isMuted;

  /// Current video ID loaded in the web adapter.
  String get currentVideoId;

  /// Current audio volume (0.0 to 1.0).
  double get volume;

  /// Current playback speed (e.g. 1.0).
  double get playbackSpeed;

  /// Sets video playback quality (e.g. '1080', '720', '480', '380', 'auto').
  Future<void> setQuality(String qualityId);

  /// List of available video qualities for this stream.
  List<VideoQuality> get availableQualities;

  /// Currently selected video quality.
  VideoQuality? get selectedQuality;

  /// Cleans up iframe and event listeners.
  void dispose();
}
