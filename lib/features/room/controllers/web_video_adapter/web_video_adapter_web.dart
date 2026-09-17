import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;
import '../../models/video_quality.dart';
import 'web_video_adapter.dart';

bool get isSupported => kIsWeb;

WebVideoAdapter createWebVideoAdapter({
  required void Function(double position) onPositionChanged,
  required void Function(double duration) onDurationChanged,
  required void Function(bool isPlaying) onPlayingChanged,
  required void Function(String error) onError,
  void Function(List<VideoQuality> qualities)? onQualitiesChanged,
}) {
  return WebVideoAdapterWeb(
    onPositionChanged: onPositionChanged,
    onDurationChanged: onDurationChanged,
    onPlayingChanged: onPlayingChanged,
    onError: onError,
    onQualitiesChanged: onQualitiesChanged,
  );
}

@JS('Hls')
extension type _HlsJS._(JSObject _) implements JSObject {
  external factory _HlsJS();
  external static bool isSupported();
  external void loadSource(String url);
  external void attachMedia(web.HTMLVideoElement video);
  external void destroy();
  external JSArray<JSObject> get levels;
  external int get currentLevel;
  external set currentLevel(int level);
  external void on(String event, JSFunction callback);
}

@JS()
extension type _HlsLevel._(JSObject _) implements JSObject {
  external int? get height;
  external int? get width;
  external int? get bitrate;
  external String? get name;
}

@JS('Hls')
external JSFunction? get _hlsConstructor;

bool _isHlsSupported() {
  try {
    if (_hlsConstructor == null) return false;
    return _HlsJS.isSupported();
  } catch (_) {
    return false;
  }
}

class WebVideoAdapterWeb implements WebVideoAdapter {
  static int _idCounter = 0;
  final String _viewType;
  final web.HTMLVideoElement _videoElement;
  final List<StreamSubscription> _subscriptions = [];
  double _pendingStartSeconds = 0.0;
  _HlsJS? _hlsInstance;

  final void Function(double position) onPositionChanged;
  final void Function(double duration) onDurationChanged;
  final void Function(bool isPlaying) onPlayingChanged;
  final void Function(String error) onError;
  final void Function(List<VideoQuality> qualities)? onQualitiesChanged;

  List<VideoQuality> _availableQualities = [
    const VideoQuality.auto(mode: QualityControlMode.directTrack),
  ];
  VideoQuality? _selectedQuality;

  @override
  List<VideoQuality> get availableQualities => List.unmodifiable(_availableQualities);

  @override
  VideoQuality? get selectedQuality => _selectedQuality;

  WebVideoAdapterWeb({
    required this.onPositionChanged,
    required this.onDurationChanged,
    required this.onPlayingChanged,
    required this.onError,
    this.onQualitiesChanged,
  })  : _viewType = 'watch_party_direct_video_${++_idCounter}',
        _videoElement = web.HTMLVideoElement() {
    _videoElement
      ..autoplay = false
      ..controls = false
      ..preload = 'auto'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'contain'
      ..style.backgroundColor = 'black'
      ..style.border = 'none'
      ..setAttribute('playsinline', 'true')
      ..setAttribute('webkit-playsinline', 'true');

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _videoElement,
    );

    _subscriptions.add(_videoElement.onPlay.listen((_) {
      onPlayingChanged(true);
    }));

    _subscriptions.add(_videoElement.onPause.listen((_) {
      onPlayingChanged(false);
    }));

    _subscriptions.add(_videoElement.onEnded.listen((_) {
      onPlayingChanged(false);
    }));

    _subscriptions.add(_videoElement.onTimeUpdate.listen((_) {
      final pos = _videoElement.currentTime.toDouble();
      onPositionChanged(pos);
    }));

    void handleDurationAndSeek() {
      final dur = _videoElement.duration.toDouble();
      if (!dur.isNaN && !dur.isInfinite && dur > 0) {
        onDurationChanged(dur);
      }
      if (_pendingStartSeconds > 0 && _videoElement.readyState >= 1) {
        final seekTarget = _pendingStartSeconds;
        _pendingStartSeconds = 0.0;
        try {
          if (!dur.isNaN && !dur.isInfinite && dur > 0 && seekTarget > dur) {
            _videoElement.currentTime = dur;
          } else {
            _videoElement.currentTime = seekTarget;
          }
        } catch (e) {
          debugPrint('[WebVideoAdapter] Error setting currentTime: $e');
        }
      }

      // If single file (not HLS), detect video resolution from element
      if (_hlsInstance == null && _videoElement.videoHeight > 0) {
        final h = _videoElement.videoHeight;
        final w = _videoElement.videoWidth;
        if (_availableQualities.length <= 1 || _availableQualities.first.height != h) {
          _availableQualities = [
            VideoQuality.fixed(
              label: '${h}p (Kualitas Asli)',
              height: h,
              width: w,
            ),
          ];
          _selectedQuality = _availableQualities.first;
          onQualitiesChanged?.call(_availableQualities);
        }
      }
    }

    _subscriptions.add(_videoElement.onDurationChange.listen((_) => handleDurationAndSeek()));
    _subscriptions.add(_videoElement.onLoadedMetadata.listen((_) => handleDurationAndSeek()));
    _subscriptions.add(_videoElement.onCanPlay.listen((_) => handleDurationAndSeek()));

    _subscriptions.add(_videoElement.onError.listen((_) {
      final code = _videoElement.error?.code ?? 0;
      final rawMsg = _videoElement.error?.message ?? '';
      // Code 1 is MEDIA_ERR_ABORTED - expected when user or code changes source, ignore it.
      if (code == 1) {
        debugPrint('[WebVideoAdapter] Video load aborted (code 1), ignoring.');
        return;
      }
      String msg;
      switch (code) {
        case 2:
          msg = 'Gangguan jaringan saat memuat video.';
          break;
        case 3:
          msg = 'Gagal memproses (decode) format video.';
          break;
        case 4:
          msg = 'Format video tidak didukung atau URL tidak dapat diakses (CORS/404). Pastikan URL berupa link file MP4/WebM langsung.';
          break;
        default:
          msg = rawMsg.isNotEmpty ? rawMsg : 'Gagal memutar video ($code)';
      }
      onError(msg);
    }));
  }

  void _extractHlsLevels() {
    if (_hlsInstance == null) return;
    try {
      final List<VideoQuality> qualities = [
        const VideoQuality.auto(
          label: 'Auto (Otomatis)',
          mode: QualityControlMode.directTrack,
        ),
      ];
      final rawLevels = _hlsInstance!.levels.toDart;
      for (int i = 0; i < rawLevels.length; i++) {
        final lvl = _HlsLevel._(rawLevels[i]);
        final h = lvl.height;
        final w = lvl.width;
        final b = lvl.bitrate;
        final label = (h != null && h > 0) ? '${h}p' : (lvl.name ?? 'Level $i');
        qualities.add(
          VideoQuality(
            id: '$i',
            label: label,
            height: h,
            width: w,
            bitrate: b,
            mode: QualityControlMode.directTrack,
          ),
        );
      }
      qualities.sort((a, b) {
        if (a.isAuto) return -1;
        if (b.isAuto) return 1;
        return (b.height ?? 0).compareTo(a.height ?? 0);
      });
      _availableQualities = qualities;
      _selectedQuality = qualities.first;
      onQualitiesChanged?.call(_availableQualities);
    } catch (e) {
      debugPrint('[WebVideoAdapter] Error extracting HLS levels: $e');
    }
  }

  void _cleanupHls() {
    if (_hlsInstance != null) {
      try {
        _hlsInstance!.destroy();
      } catch (e) {
        debugPrint('[WebVideoAdapter] Error destroying Hls instance: $e');
      }
      _hlsInstance = null;
    }
    _availableQualities = [
      const VideoQuality.auto(mode: QualityControlMode.directTrack),
    ];
    _selectedQuality = _availableQualities.first;
  }

  @override
  Widget buildVideoWidget() {
    return HtmlElementView(
      key: ValueKey(_viewType),
      viewType: _viewType,
    );
  }

  @override
  Future<void> load(
    String url, {
    bool autoPlay = false,
    double startSeconds = 0.0,
  }) async {
    _cleanupHls();
    _pendingStartSeconds = startSeconds;

    final isHls = url.toLowerCase().contains('.m3u8');
    final canNativeHls = _videoElement.canPlayType('application/vnd.apple.mpegurl').isNotEmpty;

    if (isHls && !canNativeHls && _isHlsSupported()) {
      try {
        final hls = _HlsJS();
        _hlsInstance = hls;
        hls.on(
          'hlsManifestParsed',
          ((JSAny? event, JSAny? data) {
            _extractHlsLevels();
          }).toJS,
        );
        hls.loadSource(url);
        hls.attachMedia(_videoElement);
      } catch (e) {
        debugPrint('[WebVideoAdapter] Failed to initialize HLS.js: $e');
        _videoElement.src = url;
        _videoElement.load();
      }
    } else {
      _videoElement.src = url;
      _videoElement.load();
    }

    if (autoPlay) {
      await play();
    } else {
      _videoElement.pause();
      onPlayingChanged(false);
    }
  }

  @override
  Future<void> setQuality(String qualityId) async {
    if (_hlsInstance != null) {
      try {
        if (qualityId == 'auto' || qualityId == '-1') {
          _hlsInstance!.currentLevel = -1;
          _selectedQuality = _availableQualities.firstWhere(
            (q) => q.isAuto,
            orElse: () => const VideoQuality.auto(),
          );
        } else {
          final idx = int.tryParse(qualityId);
          if (idx != null) {
            _hlsInstance!.currentLevel = idx;
            _selectedQuality = _availableQualities.firstWhere(
              (q) => q.id == qualityId,
              orElse: () => VideoQuality(
                id: qualityId,
                label: '${qualityId}p',
                mode: QualityControlMode.directTrack,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('[WebVideoAdapter] Error setting HLS quality: $e');
      }
    }
  }

  @override
  Future<void> play() async {
    if (_videoElement.ended) {
      _videoElement.currentTime = 0;
    }

    try {
      final promise = _videoElement.play();
      await promise.toDart;
      onPlayingChanged(true);
    } catch (e) {
      debugPrint('[WebVideoAdapter] Unmuted play failed, falling back to muted: $e');
      try {
        _videoElement.muted = true;
        final promise = _videoElement.play();
        await promise.toDart;
        onPlayingChanged(true);
      } catch (e2) {
        debugPrint('[WebVideoAdapter] Muted play also failed: $e2');
        onPlayingChanged(false);
        onError('Gagal memutar video. Browser memerlukan interaksi pengguna.');
      }
    }
  }

  @override
  Future<void> pause() async {
    _videoElement.pause();
    onPlayingChanged(false);
  }

  @override
  Future<void> seekTo(double seconds) async {
    if (seconds >= 0) {
      if (_videoElement.readyState >= 1) {
        try {
          _videoElement.currentTime = seconds;
        } catch (e) {
          debugPrint('[WebVideoAdapter] Error in seekTo: $e');
        }
      } else {
        _pendingStartSeconds = seconds;
      }
    }
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    if (speed > 0) {
      _videoElement.playbackRate = speed;
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _videoElement.volume = volume.clamp(0.0, 1.0);
    _videoElement.muted = volume == 0;
  }

  @override
  Future<void> setMuted(bool muted) async {
    _videoElement.muted = muted;
  }

  @override
  bool get isMuted => _videoElement.muted;

  @override
  void dispose() {
    _cleanupHls();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _videoElement.pause();
    _videoElement.src = '';
    _videoElement.load();
    _videoElement.remove();
  }
}
