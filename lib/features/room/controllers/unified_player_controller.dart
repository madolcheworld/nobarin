import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../../../core/utils/fullscreen/fullscreen_helper.dart';
import '../models/video_quality.dart';
import 'bstation_player_controller.dart';
import 'dailymotion_player_controller.dart';
import 'web_video_adapter/web_video_adapter.dart';

/// Normalized result of detecting media platform, URLs, and IDs
class DetectedMedia {
  final String mediaType; // 'direct_url' | 'youtube' | 'bstation' | 'dailymotion'
  final String mediaUrl;
  final String? mediaId;
  final String title;
  final String? thumbnailUrl;

  const DetectedMedia({
    required this.mediaType,
    required this.mediaUrl,
    this.mediaId,
    required this.title,
    this.thumbnailUrl,
  });

  bool get isDirectUrl => mediaType == 'direct_url';
  bool get isYoutube => mediaType == 'youtube';
  bool get isYouTube => isYoutube;
  bool get isBstation => mediaType == 'bstation';
  bool get isDailymotion => mediaType == 'dailymotion';
}

class UnifiedPlayerController extends ChangeNotifier {
  String _mediaType = 'direct_url';
  String _mediaUrl = '';
  bool _isPlaying = false;
  bool _isFullscreen = false;
  double _position = 0.0;
  double _duration = 0.0;
  double _playbackSpeed = 1.0;
  double _volume = 1.0;
  bool _isMuted = false;
  bool _isDisposed = false;
  String? _errorMessage;

  // Video Quality Management
  List<VideoQuality> _availableQualities = [VideoQuality.auto()];
  VideoQuality? _selectedQuality;

  // HTML5 Web Video Player (Web direct URL)
  WebVideoAdapter? _webVideoAdapter;

  // YouTube IFrame Player Controller
  YoutubePlayerController? _ytController;

  // Bstation Web / Mobile Player Controller
  BstationPlayerController? _bstationController;

  // Dailymotion Web / Mobile Player Controller
  DailymotionPlayerController? _dailymotionController;

  // MediaKit Player & VideoController (Native desktop / mobile direct URL)
  Player? _mkPlayer;
  VideoController? _mkVideoController;
  final List<StreamSubscription> _subscriptions = [];

  // Callbacks for SyncController
  void Function(double positionSeconds)? onPositionChanged;
  void Function(String state)? onPlaybackStateChanged;
  void Function()? onPlaybackEnded;

  String get mediaType => _mediaType;
  String get mediaUrl => _mediaUrl;
  bool get isLoaded => _mediaUrl.isNotEmpty;
  bool get hasMedia => _mediaUrl.isNotEmpty;
  bool get isPlaying => _isPlaying;
  bool get isFullscreen => _isFullscreen;
  double get position => _position;
  double get duration => _duration;
  double get playbackSpeed => _playbackSpeed;
  double get volume => _volume;
  bool get isMuted => _isMuted;
  String? get errorMessage => _errorMessage;
  VideoController? get mkVideoController => _mkVideoController;
  YoutubePlayerController? get ytController => _ytController;
  BstationPlayerController? get bstationController => _bstationController;
  DailymotionPlayerController? get dailymotionController => _dailymotionController;
  Widget? get webVideoWidget => _webVideoAdapter?.buildVideoWidget();

  List<VideoQuality> get availableQualities =>
      List.unmodifiable(_availableQualities);
  VideoQuality? get selectedQuality => _selectedQuality;
  bool get hasMultipleQualities => _availableQualities.length > 1;

  bool get supportsQualitySelection => _mediaType == 'direct_url';

  String get currentQualityLabel {
    if (_selectedQuality != null && !_selectedQuality!.isAuto) {
      return _selectedQuality!.shortLabel;
    }
    if (_mediaType == 'direct_url' && _mkPlayer != null) {
      try {
        final currentTrack = _mkPlayer!.state.track.video;
        if (currentTrack.h != null && currentTrack.h! > 0) {
          return 'Auto (${currentTrack.h}p)';
        }
      } catch (_) {}
    }
    return _selectedQuality?.shortLabel ?? 'Auto';
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Reloads current media from scratch at current position
  Future<void> reloadCurrentMedia() async {
    if (_mediaUrl.isEmpty) return;
    clearError();
    await loadMedia(
      _mediaType,
      _mediaUrl,
      autoPlay: true,
      startSeconds: _position,
    );
  }

  UnifiedPlayerController() {
    if (kIsWeb) {
      _initWebVideo();
    } else {
      _initMediaKit();
    }
  }

  void _initWebVideo() {
    try {
      _webVideoAdapter = WebVideoAdapter.create(
        onPositionChanged: (pos) {
          if (_isDisposed || _mediaType != 'direct_url') return;
          _position = pos;
          notifyListeners();
          onPositionChanged?.call(_position);
        },
        onDurationChanged: (dur) {
          if (_isDisposed || _mediaType != 'direct_url') return;
          if (dur > 0 && dur != _duration) {
            _duration = dur;
            notifyListeners();
          }
        },
        onPlayingChanged: (playing) {
          if (_isDisposed || _mediaType != 'direct_url') return;
          if (playing && _errorMessage != null) {
            _errorMessage = null;
          }
          if (_webVideoAdapter != null && _webVideoAdapter!.isMuted != _isMuted) {
            _isMuted = _webVideoAdapter!.isMuted;
          }
          if (_isPlaying != playing) {
            _isPlaying = playing;
            notifyListeners();
            onPlaybackStateChanged?.call(playing ? 'playing' : 'paused');
            if (!playing && _duration > 0 && _position >= _duration - 0.5) {
              onPlaybackEnded?.call();
            }
          }
        },
        onError: (err) {
          debugPrint('[UnifiedPlayerController] Web video error: $err');
          _errorMessage = err;
          _isPlaying = false;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('[UnifiedPlayerController] Error init WebVideoAdapter: $e');
    }
  }

  void _initMediaKit() {
    try {
      _mkPlayer = Player();
      _mkVideoController = VideoController(_mkPlayer!);

      _subscriptions.add(_mkPlayer!.stream.position.listen((pos) {
        if (_isDisposed || _mediaType != 'direct_url') return;
        _position = pos.inMilliseconds / 1000.0;
        notifyListeners();
        onPositionChanged?.call(_position);
      }));

      _subscriptions.add(_mkPlayer!.stream.duration.listen((dur) {
        if (_isDisposed || _mediaType != 'direct_url') return;
        _duration = dur.inMilliseconds / 1000.0;
        notifyListeners();
      }));

      _subscriptions.add(_mkPlayer!.stream.playing.listen((playing) {
        if (_isDisposed || _mediaType != 'direct_url') return;
        if (playing && _errorMessage != null) {
          _errorMessage = null;
        }
        if (_isPlaying != playing) {
          _isPlaying = playing;
          notifyListeners();
          onPlaybackStateChanged?.call(playing ? 'playing' : 'paused');
        }
      }));

      _subscriptions.add(_mkPlayer!.stream.completed.listen((completed) {
        if (_isDisposed || _mediaType != 'direct_url') return;
        if (completed) {
          onPlaybackEnded?.call();
        }
      }));

      _subscriptions.add(_mkPlayer!.stream.error.listen((err) {
        if (_isDisposed || _mediaType != 'direct_url') return;
        _errorMessage = 'Gagal memutar video: $err';
        _isPlaying = false;
        notifyListeners();
      }));

      // Listen to available video tracks for quality selection
      _subscriptions.add(_mkPlayer!.stream.tracks.listen((tracks) {
        if (_isDisposed || _mediaType != 'direct_url') return;
        _updateMediaKitQualities(tracks.video);
      }));

      // Listen to active video track
      _subscriptions.add(_mkPlayer!.stream.track.listen((track) {
        if (_isDisposed || _mediaType != 'direct_url') return;
        _updateSelectedMediaKitQuality(track.video);
      }));
    } catch (e) {
      debugPrint('[UnifiedPlayerController] Error init media_kit: $e');
    }
  }

  void _updateMediaKitQualities(List<VideoTrack> videoTracks) {
    final List<VideoQuality> list = [VideoQuality.auto()];
    final Set<String> seen = {'auto'};

    final validTracks = videoTracks
        .where((t) => t.id != 'no' && t.id != 'auto')
        .toList();

    validTracks.sort((a, b) {
      final hA = a.h ?? 0;
      final hB = b.h ?? 0;
      if (hA != hB) return hB.compareTo(hA);
      return (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
    });

    for (final track in validTracks) {
      String label;
      if (track.h != null && track.h! > 0) {
        label = '${track.h}p';
        if (track.fps != null && track.fps! > 30) {
          label += '${track.fps!.round()}';
        }
      } else if (track.title != null && track.title!.isNotEmpty) {
        label = track.title!;
      } else {
        label = 'Track ${track.id}';
      }

      if (!seen.contains(track.id)) {
        seen.add(track.id);
        list.add(
          VideoQuality(
            id: track.id,
            label: label,
            height: track.h,
            bitrate: track.bitrate,
            rawTrack: track,
          ),
        );
      }
    }

    _availableQualities = list;
    notifyListeners();
  }

  void _updateSelectedMediaKitQuality(VideoTrack currentTrack) {
    if (currentTrack.id == 'auto' || currentTrack.id == 'no') {
      _selectedQuality = _availableQualities.firstWhere(
        (q) => q.isAuto,
        orElse: () => VideoQuality.auto(),
      );
    } else {
      _selectedQuality = _availableQualities.firstWhere(
        (q) => q.id == currentTrack.id,
        orElse: () => VideoQuality(
          id: currentTrack.id,
          label: currentTrack.h != null ? '${currentTrack.h}p' : currentTrack.id,
          height: currentTrack.h,
          bitrate: currentTrack.bitrate,
          rawTrack: currentTrack,
        ),
      );
    }
    notifyListeners();
  }

  /// Centralized detection of platform, ID, and title from any video URL (Direct or YouTube)
  static DetectedMedia? detectMediaFromUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.contains('youtube.com') || trimmed.contains('youtu.be')) {
      final ytId = YoutubePlayerController.convertUrlToId(trimmed);
      if (ytId != null && ytId.isNotEmpty) {
        return DetectedMedia(
          mediaType: 'youtube',
          mediaUrl: 'https://www.youtube.com/watch?v=$ytId',
          mediaId: ytId,
          title: 'YouTube Video ($ytId)',
          thumbnailUrl: 'https://img.youtube.com/vi/$ytId/hqdefault.jpg',
        );
      }
    }

    if (trimmed.contains('bilibili.tv') ||
        trimmed.contains('bilibili.com') ||
        trimmed.contains('b23.tv')) {
      final uri = Uri.tryParse(trimmed);
      String title = 'Video Bstation';
      String? mediaId;
      if (uri != null && uri.pathSegments.isNotEmpty) {
        mediaId = uri.pathSegments.last;
        title = 'Bstation Video ($mediaId)';
      }
      return DetectedMedia(
        mediaType: 'bstation',
        mediaUrl: trimmed,
        mediaId: mediaId,
        title: title,
      );
    }

    if (trimmed.contains('dailymotion.com') || trimmed.contains('dai.ly')) {
      final dmId = DailymotionPlayerController.extractVideoId(trimmed);
      if (dmId != null && dmId.isNotEmpty) {
        return DetectedMedia(
          mediaType: 'dailymotion',
          mediaUrl: 'https://www.dailymotion.com/video/$dmId',
          mediaId: dmId,
          title: 'Dailymotion Video ($dmId)',
          thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/$dmId',
        );
      }
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final uri = Uri.tryParse(trimmed);
      final filename = uri != null && uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'Direct Video';
      return DetectedMedia(
        mediaType: 'direct_url',
        mediaUrl: trimmed,
        title: filename.isNotEmpty ? filename : 'Direct Video Stream',
      );
    }

    return null;
  }

  void _setupYoutubeListeners() {
    if (_ytController == null) return;

    _subscriptions.add(_ytController!.videoStateStream.listen((state) {
      if (_isDisposed || _mediaType != 'youtube') return;
      final pos = state.position.inMilliseconds / 1000.0;
      if ((pos - _position).abs() >= 0.25) {
        _position = pos;
        notifyListeners();
        onPositionChanged?.call(_position);
      }
    }));

    _subscriptions.add(_ytController!.stream.listen((value) {
      if (_isDisposed || _mediaType != 'youtube') return;
      final dur = value.metaData.duration.inMilliseconds / 1000.0;
      if (dur > 0 && dur != _duration) {
        _duration = dur;
      }
      final bool playing = value.playerState == PlayerState.playing;
      if (value.playerState == PlayerState.ended) {
        onPlaybackEnded?.call();
      }
      if (_isPlaying != playing &&
          value.playerState != PlayerState.buffering &&
          value.playerState != PlayerState.unknown &&
          value.playerState != PlayerState.cued) {
        _isPlaying = playing;
        notifyListeners();
        onPlaybackStateChanged?.call(playing ? 'playing' : 'paused');
      }
    }));
  }

  void _setupBstationListeners() {
    if (_bstationController == null) return;
    _bstationController!.onPositionChanged = (pos) {
      if (_isDisposed || _mediaType != 'bstation') return;
      if ((pos - _position).abs() >= 0.25) {
        _position = pos;
        notifyListeners();
        onPositionChanged?.call(_position);
      }
    };
    _bstationController!.onDurationChanged = (dur) {
      if (_isDisposed || _mediaType != 'bstation') return;
      if (dur > 0 && dur != _duration) {
        _duration = dur;
        notifyListeners();
      }
    };
    _bstationController!.onPlayingChanged = (playing) {
      if (_isDisposed || _mediaType != 'bstation') return;
      if (_isPlaying != playing) {
        _isPlaying = playing;
        notifyListeners();
        onPlaybackStateChanged?.call(playing ? 'playing' : 'paused');
      }
    };
    _bstationController!.onPlaybackEnded = () {
      if (_isDisposed || _mediaType != 'bstation') return;
      onPlaybackEnded?.call();
    };
    _bstationController!.onError = (err) {
      if (_isDisposed || _mediaType != 'bstation') return;
      _errorMessage = err;
      _isPlaying = false;
      notifyListeners();
    };
  }

  void _setupDailymotionListeners() {
    if (_dailymotionController == null) return;
    _dailymotionController!.onPositionChanged = (pos) {
      if (_isDisposed || _mediaType != 'dailymotion') return;
      if ((pos - _position).abs() >= 0.25) {
        _position = pos;
        notifyListeners();
        onPositionChanged?.call(_position);
      }
    };
    _dailymotionController!.onDurationChanged = (dur) {
      if (_isDisposed || _mediaType != 'dailymotion') return;
      if (dur > 0 && dur != _duration) {
        _duration = dur;
        notifyListeners();
      }
    };
    _dailymotionController!.onPlayingChanged = (playing) {
      if (_isDisposed || _mediaType != 'dailymotion') return;
      if (_isPlaying != playing) {
        _isPlaying = playing;
        notifyListeners();
        onPlaybackStateChanged?.call(playing ? 'playing' : 'paused');
      }
    };
    _dailymotionController!.onPlaybackEnded = () {
      if (_isDisposed || _mediaType != 'dailymotion') return;
      onPlaybackEnded?.call();
    };
    _dailymotionController!.onError = (err) {
      if (_isDisposed || _mediaType != 'dailymotion') return;
      _errorMessage = err;
      _isPlaying = false;
      notifyListeners();
    };
  }

  /// Loads media into player
  Future<void> loadMedia(
    String type,
    String url, {
    bool autoPlay = false,
    double startSeconds = 0.0,
  }) async {
    _errorMessage = null;
    _mediaType = type;
    _mediaUrl = url;
    _position = startSeconds;
    _playbackSpeed = 1.0;
    _availableQualities = [VideoQuality.auto()];
    _selectedQuality = _availableQualities.first;

    if (url.isEmpty) {
      _isPlaying = false;
      notifyListeners();
      return;
    }

    if (type == 'youtube') {
      // Pause direct video player, Bstation, and Dailymotion player if active
      await _bstationController?.pause();
      await _dailymotionController?.pause();
      if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.pause();
      } else if (_mkPlayer != null) {
        await _mkPlayer?.pause();
      }

      final videoId = YoutubePlayerController.convertUrlToId(url) ?? url;
      try {
        if (_ytController == null) {
          _ytController = YoutubePlayerController(
            params: const YoutubePlayerParams(
              showControls: true,
              showFullscreenButton: false,
              mute: false,
              enableJavaScript: true,
            ),
          );
          _setupYoutubeListeners();
        }

        if (autoPlay) {
          await _ytController!.loadVideoById(
            videoId: videoId,
            startSeconds: startSeconds > 0 ? startSeconds : null,
          );
          _isPlaying = true;
        } else {
          await _ytController!.cueVideoById(
            videoId: videoId,
            startSeconds: startSeconds > 0 ? startSeconds : null,
          );
          _isPlaying = false;
        }
      } catch (e) {
        debugPrint('[UnifiedPlayerController] YouTube load error: $e');
        _errorMessage = 'Gagal memuat YouTube video: $e';
        _isPlaying = false;
      }
      notifyListeners();
      return;
    }

    if (type == 'bstation') {
      // Pause YouTube, Dailymotion, and direct video player if active
      if (_ytController != null) {
        try {
          await _ytController!.pauseVideo();
        } catch (_) {}
      }
      await _dailymotionController?.pause();
      if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.pause();
      } else if (_mkPlayer != null) {
        await _mkPlayer?.pause();
      }

      try {
        _bstationController ??= BstationPlayerController();
        _setupBstationListeners();
        await _bstationController!.loadUrl(
          url,
          autoPlay: autoPlay,
          startSeconds: startSeconds,
        );
        _isPlaying = autoPlay;
      } catch (e) {
        debugPrint('[UnifiedPlayerController] Bstation load error: $e');
        _errorMessage = 'Gagal memuat Bstation video: $e';
        _isPlaying = false;
      }
      notifyListeners();
      return;
    }

    if (type == 'dailymotion') {
      // Pause YouTube, Bstation, and direct video player if active
      if (_ytController != null) {
        try {
          await _ytController!.pauseVideo();
        } catch (_) {}
      }
      await _bstationController?.pause();
      if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.pause();
      } else if (_mkPlayer != null) {
        await _mkPlayer?.pause();
      }

      try {
        _dailymotionController ??= DailymotionPlayerController();
        _setupDailymotionListeners();
        await _dailymotionController!.loadUrl(
          url,
          autoPlay: autoPlay,
          startSeconds: startSeconds,
        );
        _isPlaying = autoPlay;
      } catch (e) {
        debugPrint('[UnifiedPlayerController] Dailymotion load error: $e');
        _errorMessage = 'Gagal memuat Dailymotion video: $e';
        _isPlaying = false;
      }
      notifyListeners();
      return;
    }

    // Direct URL: pause YouTube, Bstation, and Dailymotion player if active
    await _bstationController?.pause();
    await _dailymotionController?.pause();
    if (_ytController != null) {
      try {
        await _ytController!.pauseVideo();
      } catch (_) {}
    }

    if (kIsWeb && _webVideoAdapter != null) {
      await _webVideoAdapter!.load(
        url,
        autoPlay: autoPlay,
        startSeconds: startSeconds,
      );
      if (_webVideoAdapter!.isMuted != _isMuted) {
        _isMuted = _webVideoAdapter!.isMuted;
      }
      if (_errorMessage != null) {
        _isPlaying = false;
      } else {
        _isPlaying = autoPlay;
      }
    } else if (_mkPlayer != null) {
      try {
        await _mkPlayer!.open(Media(url), play: autoPlay);
        if (startSeconds > 0) {
          await _mkPlayer!.seek(
            Duration(milliseconds: (startSeconds * 1000).round()),
          );
        }
        _isPlaying = autoPlay;
      } catch (e) {
        debugPrint('[UnifiedPlayerController] MediaKit open error: $e');
        _errorMessage = 'Gagal memutar video: $e';
        _isPlaying = false;
        notifyListeners();
      }
    } else {
      _isPlaying = autoPlay;
    }
    notifyListeners();
  }

  Future<void> play() async {
    _isPlaying = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (_mediaType == 'youtube') {
        await _ytController?.playVideo();
      } else if (_mediaType == 'bstation') {
        await _bstationController?.play();
      } else if (_mediaType == 'dailymotion') {
        await _dailymotionController?.play();
      } else if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.play();
        if (_webVideoAdapter!.isMuted != _isMuted) {
          _isMuted = _webVideoAdapter!.isMuted;
          notifyListeners();
        }
      } else {
        await _mkPlayer?.play();
      }
    } catch (e) {
      debugPrint('[UnifiedPlayerController] play error: $e');
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    _isPlaying = false;
    notifyListeners();

    try {
      if (_mediaType == 'youtube') {
        await _ytController?.pauseVideo();
      } else if (_mediaType == 'bstation') {
        await _bstationController?.pause();
      } else if (_mediaType == 'dailymotion') {
        await _dailymotionController?.pause();
      } else if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.pause();
      } else {
        await _mkPlayer?.pause();
      }
    } catch (e) {
      debugPrint('[UnifiedPlayerController] pause error: $e');
    }
  }

  Future<void> seekTo(double seconds) async {
    _position = seconds < 0 ? 0 : seconds;
    notifyListeners();

    try {
      if (_mediaType == 'youtube') {
        await _ytController?.seekTo(seconds: seconds, allowSeekAhead: true);
      } else if (_mediaType == 'bstation') {
        await _bstationController?.seekTo(seconds);
      } else if (_mediaType == 'dailymotion') {
        await _dailymotionController?.seekTo(seconds);
      } else if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.seekTo(seconds);
      } else {
        await _mkPlayer?.seek(
          Duration(milliseconds: (seconds * 1000).round()),
        );
      }
    } catch (e) {
      debugPrint('[UnifiedPlayerController] seekTo error: $e');
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    notifyListeners();

    try {
      if (_mediaType == 'youtube') {
        await _ytController?.setPlaybackRate(speed);
      } else if (_mediaType == 'bstation') {
        await _bstationController?.setPlaybackSpeed(speed);
      } else if (_mediaType == 'dailymotion') {
        await _dailymotionController?.setPlaybackSpeed(speed);
      } else if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.setPlaybackSpeed(speed);
      } else {
        await _mkPlayer?.setRate(speed);
      }
    } catch (e) {
      debugPrint('[UnifiedPlayerController] setPlaybackSpeed error: $e');
    }
  }

  Future<void> setVolume(double vol) async {
    _volume = vol.clamp(0.0, 1.0);
    _isMuted = _volume == 0;
    notifyListeners();

    try {
      if (_mediaType == 'youtube') {
        await _ytController?.setVolume((_volume * 100).round());
        if (_volume == 0) {
          await _ytController?.mute();
        } else {
          await _ytController?.unMute();
        }
      } else if (_mediaType == 'bstation') {
        await _bstationController?.setVolume(_volume);
      } else if (_mediaType == 'dailymotion') {
        await _dailymotionController?.setVolume(_volume);
      } else if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.setVolume(_volume);
      } else {
        await _mkPlayer?.setVolume(_volume * 100);
      }
    } catch (e) {
      debugPrint('[UnifiedPlayerController] setVolume error: $e');
    }
  }

  Future<void> toggleMute() async {
    if (_isMuted) {
      await setVolume(_volume > 0 ? _volume : 1.0);
    } else {
      _isMuted = true;
      notifyListeners();
      try {
        if (_mediaType == 'youtube') {
          await _ytController?.mute();
        } else if (_mediaType == 'bstation') {
          await _bstationController?.toggleMute();
        } else if (_mediaType == 'dailymotion') {
          await _dailymotionController?.toggleMute();
        } else if (kIsWeb && _webVideoAdapter != null) {
          await _webVideoAdapter?.setMuted(true);
        } else {
          await _mkPlayer?.setVolume(0);
        }
      } catch (e) {
        debugPrint('[UnifiedPlayerController] toggleMute error: $e');
      }
    }
  }

  /// Sets video playback quality (local client preference).
  Future<void> setVideoQuality(VideoQuality quality) async {
    _selectedQuality = quality;
    notifyListeners();

    try {
      if (_mkPlayer != null) {
        if (quality.isAuto) {
          await _mkPlayer!.setVideoTrack(VideoTrack.auto());
        } else if (quality.rawTrack is VideoTrack) {
          await _mkPlayer!.setVideoTrack(quality.rawTrack as VideoTrack);
        } else {
          final track = _mkPlayer!.state.tracks.video.firstWhere(
            (t) => t.id == quality.id,
            orElse: () => VideoTrack.auto(),
          );
          await _mkPlayer!.setVideoTrack(track);
        }
      }
    } catch (e) {
      debugPrint('[UnifiedPlayerController] setVideoQuality error: $e');
    }
  }

  Future<void> enterFullscreen() async {
    if (_isFullscreen) return;
    _isFullscreen = true;
    notifyListeners();

    await FullscreenHelper.enterFullscreen();
  }

  Future<void> exitFullscreen() async {
    _isFullscreen = false;
    notifyListeners();

    await FullscreenHelper.exitFullscreen();
  }

  Future<void> toggleFullscreen() async {
    if (_isFullscreen) {
      await exitFullscreen();
    } else {
      await enterFullscreen();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    if (_isFullscreen) {
      exitFullscreen();
    }
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _ytController?.close();
    _bstationController?.dispose();
    _dailymotionController?.dispose();
    _webVideoAdapter?.dispose();
    _mkPlayer?.dispose();
    super.dispose();
  }
}
