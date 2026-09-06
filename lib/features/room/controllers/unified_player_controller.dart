import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'web_video_adapter/web_video_adapter.dart';

class UnifiedPlayerController extends ChangeNotifier {
  String _mediaType = 'direct_url'; // 'direct_url' or 'youtube'
  String _mediaUrl = '';
  bool _isPlaying = false;
  double _position = 0.0;
  double _duration = 0.0;
  double _playbackSpeed = 1.0;
  double _volume = 1.0;
  bool _isMuted = false;
  bool _isDisposed = false;
  String? _errorMessage;

  // HTML5 Web Video Player (Web direct URL)
  WebVideoAdapter? _webVideoAdapter;

  // MediaKit Player & VideoController (Native desktop / mobile direct URL)
  Player? _mkPlayer;
  VideoController? _mkVideoController;
  final List<StreamSubscription> _subscriptions = [];

  // YouTube Player (Universal iframe)
  YoutubePlayerController? _ytController;
  final List<StreamSubscription> _ytSubscriptions = [];

  // Callbacks for SyncController
  void Function(double positionSeconds)? onPositionChanged;
  void Function(String state)? onPlaybackStateChanged;

  String get mediaType => _mediaType;
  String get mediaUrl => _mediaUrl;
  bool get isPlaying => _isPlaying;
  double get position => _position;
  double get duration => _duration;
  double get playbackSpeed => _playbackSpeed;
  double get volume => _volume;
  bool get isMuted => _isMuted;
  String? get errorMessage => _errorMessage;
  Player? get mkPlayer => _mkPlayer;
  VideoController? get mkVideoController => _mkVideoController;
  YoutubePlayerController? get ytController => _ytController;
  Widget? get webVideoWidget => _webVideoAdapter?.buildVideoWidget();

  void clearError() {
    _errorMessage = null;
    notifyListeners();
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

      _subscriptions.add(_mkPlayer!.stream.error.listen((err) {
        if (_isDisposed || _mediaType != 'direct_url') return;
        _errorMessage = 'Gagal memutar video: $err';
        _isPlaying = false;
        notifyListeners();
      }));
    } catch (e) {
      debugPrint('[UnifiedPlayerController] Error init media_kit: $e');
    }
  }

  /// Extracts YouTube video ID from URL or raw 11-char ID
  static String? extractYouTubeVideoId(String url) {
    final trimmed = url.trim();
    if (RegExp(r'^[\w-]{11}$').hasMatch(trimmed)) {
      return trimmed;
    }
    try {
      final regExp = RegExp(
        r'(?:youtu\.be\/|(?:youtube\.com|youtube-nocookie\.com)\/(?:embed\/|v\/|shorts\/|live\/|watch\?v=|watch\?.+&v=))([\w-]{11})',
        caseSensitive: false,
      );
      final match = regExp.firstMatch(trimmed);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// Loads media by type and URL
  Future<void> loadMedia(
    String type,
    String url, {
    bool autoPlay = false,
    double startSeconds = 0.0,
  }) async {
    _errorMessage = null;

    // Smart-detect media type if user entered a YouTube link or direct media URL
    var effectiveType = type;
    final isYtUrl = extractYouTubeVideoId(url) != null;
    if (isYtUrl) {
      effectiveType = 'youtube';
    } else if (effectiveType == 'youtube') {
      effectiveType = 'direct_url';
    }

    _mediaType = effectiveType;
    _mediaUrl = url;
    _position = startSeconds;
    _playbackSpeed = 1.0;

    if (effectiveType == 'youtube') {
      // Pause direct video players
      if (kIsWeb) {
        await _webVideoAdapter?.pause();
      } else {
        await _mkPlayer?.pause();
      }

      final videoId = extractYouTubeVideoId(url) ?? 'aqz-KE-bpKQ';

      // If YouTube controller already exists for this video ID, reuse it
      if (_ytController != null && _ytController?.key == videoId) {
        if (startSeconds > 0) {
          await _ytController!.seekTo(
            seconds: startSeconds,
            allowSeekAhead: true,
          );
        }
        if (autoPlay) {
          await _ytController!.playVideo();
          _isPlaying = true;
        } else {
          await _ytController!.pauseVideo();
          _isPlaying = false;
        }
        notifyListeners();
        return;
      }

      // Recreate YouTube controller with fromVideoId so it loads without blocking
      _ytController?.close();
      for (final sub in _ytSubscriptions) {
        sub.cancel();
      }
      _ytSubscriptions.clear();

      // On web, start muted to comply with browser autoplay policies
      final bool startMuted = kIsWeb;
      _isMuted = startMuted;

      _ytController = YoutubePlayerController.fromVideoId(
        videoId: videoId,
        autoPlay: autoPlay,
        startSeconds: startSeconds > 0 ? startSeconds : null,
        params: YoutubePlayerParams(
          showControls: false,
          showFullscreenButton: false,
          mute: startMuted,
          enableCaption: false,
          pointerEvents: PointerEvents.none,
          enableKeyboard: false,
        ),
      );
      _isPlaying = autoPlay;
      notifyListeners();

      // Listen to YouTube video position stream
      _ytSubscriptions.add(_ytController!.videoStateStream.listen((state) {
        if (_isDisposed || _mediaType != 'youtube') return;
        _position = state.position.inMilliseconds / 1000.0;
        notifyListeners();
        onPositionChanged?.call(_position);
      }));

      // Listen to YouTube player state and metadata duration
      _ytSubscriptions.add(_ytController!.stream.listen((value) {
        if (_isDisposed || _mediaType != 'youtube') return;
        final durSeconds = value.metaData.duration.inMilliseconds / 1000.0;
        if (durSeconds > 0 && durSeconds != _duration) {
          _duration = durSeconds;
          notifyListeners();
        }

        final ytState = value.playerState;
        final bool hasMetadata = value.metaData.duration.inMilliseconds > 0;
        final bool isPlayingOrReady = ytState == PlayerState.playing ||
            ytState == PlayerState.cued ||
            ytState == PlayerState.paused;

        if (value.error != YoutubeError.none) {
          // Ignore transient invalidParam error during player creation when metadata is loaded or player is ready
          final bool isTransient = value.error == YoutubeError.invalidParam &&
              (hasMetadata || isPlayingOrReady);

          if (!isTransient) {
            String msg;
            switch (value.error) {
              case YoutubeError.notEmbeddable:
                msg = 'Video ini tidak mengizinkan pemutaran di situs lain (embed diblokir oleh pemilik video).';
                break;
              case YoutubeError.videoNotFound:
                msg = 'Video YouTube tidak ditemukan atau telah dihapus.';
                break;
              case YoutubeError.html5Error:
                msg = 'Kesalahan pemutar HTML5 YouTube.';
                break;
              default:
                msg = 'Gagal memutar video YouTube (${value.error.name})';
            }
            _errorMessage = msg;
            _isPlaying = false;
            notifyListeners();
          }
        }

        final bool playing = ytState == PlayerState.playing;
        if ((playing || isPlayingOrReady) && _errorMessage != null && value.error == YoutubeError.none) {
          _errorMessage = null;
          notifyListeners();
        }
        if (_isPlaying != playing) {
          _isPlaying = playing;
          notifyListeners();
          onPlaybackStateChanged?.call(playing ? 'playing' : 'paused');
        }
      }));
    } else {
      // Direct URL
      _ytController?.pauseVideo();

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
        await _mkPlayer!.open(Media(url), play: autoPlay);
        if (startSeconds > 0) {
          await _mkPlayer!.seek(
            Duration(milliseconds: (startSeconds * 1000).round()),
          );
        }
        _isPlaying = autoPlay;
      }
    }
    notifyListeners();
  }

  Future<void> play() async {
    _isPlaying = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (_mediaType == 'youtube') {
        if (kIsWeb && _isMuted) {
          await _ytController?.mute();
        }
        try {
          await _ytController?.playVideo();
        } catch (e) {
          debugPrint('[UnifiedPlayerController] YouTube play failed, fallback to muted: $e');
          await _ytController?.mute();
          await _ytController?.playVideo();
          _isMuted = true;
          notifyListeners();
        }
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
        if (_isMuted) {
          await _ytController?.mute();
        } else {
          await _ytController?.unMute();
          await _ytController?.setVolume((_volume * 100).toInt());
        }
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

  @override
  void dispose() {
    _isDisposed = true;
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    for (final sub in _ytSubscriptions) {
      sub.cancel();
    }
    _webVideoAdapter?.dispose();
    _mkPlayer?.dispose();
    _ytController?.close();
    super.dispose();
  }
}
