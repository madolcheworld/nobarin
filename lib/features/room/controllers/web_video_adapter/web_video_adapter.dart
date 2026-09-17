import 'package:flutter/widgets.dart';
import '../../models/video_quality.dart';
import 'web_video_adapter_stub.dart'
    if (dart.library.js_interop) 'web_video_adapter_web.dart' as impl;

/// Cross-platform abstraction for playing direct media URLs via HTML5 Video element on web.
abstract class WebVideoAdapter {
  /// Whether WebVideoAdapter is supported in the current runtime platform.
  static bool get isSupported => impl.isSupported;

  /// Factory to instantiate WebVideoAdapter when running on web.
  static WebVideoAdapter? create({
    required void Function(double position) onPositionChanged,
    required void Function(double duration) onDurationChanged,
    required void Function(bool isPlaying) onPlayingChanged,
    required void Function(String error) onError,
    void Function(List<VideoQuality> qualities)? onQualitiesChanged,
  }) {
    if (!impl.isSupported) return null;
    return impl.createWebVideoAdapter(
      onPositionChanged: onPositionChanged,
      onDurationChanged: onDurationChanged,
      onPlayingChanged: onPlayingChanged,
      onError: onError,
      onQualitiesChanged: onQualitiesChanged,
    );
  }

  /// Builds the PlatformView widget for embedding in the Flutter tree.
  Widget buildVideoWidget();

  /// Loads media URL and applies initial autoplay & start position.
  Future<void> load(
    String url, {
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

  /// Sets video playback quality (HLS rendition level index or auto).
  Future<void> setQuality(String qualityId);

  /// List of available video qualities for this stream.
  List<VideoQuality> get availableQualities;

  /// Currently selected video quality.
  VideoQuality? get selectedQuality;

  /// Cleans up DOM elements and stream subscriptions.
  void dispose();
}
