import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  static const String _prefQualityKey = 'nobarin_pref_video_quality';

  String _mediaType = 'direct_url';
  String _mediaUrl = '';
  bool _isPlaying = false;
  bool _isFullscreen = false;
  double _position = 0.0;
  double _duration = 0.0;
  double _playbackSpeed = 1.0;
  double _volume = 1.0;
  bool _isMuted = kIsWeb;
  bool _isDisposed = false;
  String? _errorMessage;

  // Video Quality Management
  List<VideoQuality> _availableQualities = [const VideoQuality.auto()];
  VideoQuality? _selectedQuality;
  String _youtubeQuality = '';

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

  static bool? _isAndroidEmulator;

  /// Initializes platform-specific video controller settings (e.g. Android emulator detection).
  static Future<void> initializePlatformSettings() async {
    if (kIsWeb || !Platform.isAndroid) {
      _isAndroidEmulator = false;
      return;
    }
    try {
      final res = await const MethodChannel('com.alexmercerind/media_kit_video')
          .invokeMethod<bool>('Utils.IsEmulator');
      _isAndroidEmulator = res ?? false;
      debugPrint('[UnifiedPlayerController] Is Android Emulator: $_isAndroidEmulator');
    } catch (e) {
      debugPrint('[UnifiedPlayerController] Check emulator status failed: $e');
      _isAndroidEmulator = false;
    }
  }

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

  /// Whether the user can select an explicit quality from the quality sheet for this media
  bool get supportsQualitySelection {
    if (_mediaType == 'youtube') return false; // Handled by YouTube internal adaptive player & gear menu
    if (isLocalFile || isP2PStream) return false; // Handled by Fixed Original passthrough
    if (_mediaType == 'dailymotion') return true;
    if (_mediaType == 'bstation') return true;
    if (_mediaType == 'direct_url') return true;
    return false;
  }

  /// Checks whether a given URL or path points to a local device file
  static bool isLocalFilePath(String url) {
    final trimmed = url.trim();
    return trimmed.startsWith('/') ||
        trimmed.startsWith('file://') ||
        trimmed.startsWith('blob:') ||
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed);
  }

  /// Whether current media is playing directly from a local device file
  bool get isLocalFile => isLocalFilePath(_mediaUrl);

  /// Whether current media is an active P2P direct stream or loopback stream
  bool get isP2PStream =>
      _mediaUrl.startsWith('p2p://') || _mediaUrl.contains('127.0.0.1');

  String get currentQualityLabel {
    if (_selectedQuality != null && !_selectedQuality!.isAuto) {
      return _selectedQuality!.shortLabel;
    }

    if (_mediaType == 'youtube') {
      if (_youtubeQuality.isNotEmpty) {
        return _formatYoutubeQuality(_youtubeQuality);
      }
      return 'Auto';
    }

    if (_mediaType == 'bstation') {
      if (_bstationController?.detectedHeight != null) {
        return 'Auto (${_bstationController!.detectedHeight}p)';
      }
      return _bstationController?.selectedQuality?.shortLabel ?? 'Auto';
    }

    if (_mediaType == 'dailymotion') {
      if (_dailymotionController?.detectedHeight != null) {
        return 'Auto (${_dailymotionController!.detectedHeight}p)';
      }
      return _dailymotionController?.selectedQuality?.shortLabel ?? 'Auto';
    }

    if (_mediaType == 'direct_url') {
      if (isLocalFile || isP2PStream) {
        final h = _mkPlayer?.state.height;
        if (h != null && h > 0) return '${h}p (Asli)';
        return 'Asli';
      }
      if (kIsWeb && _webVideoAdapter?.selectedQuality != null) {
        return _webVideoAdapter!.selectedQuality!.shortLabel;
      }
      if (_mkPlayer != null) {
        try {
          final currentTrack = _mkPlayer!.state.track.video;
          if (currentTrack.h != null && currentTrack.h! > 0) {
            return 'Auto (${currentTrack.h}p)';
          }
          final stateH = _mkPlayer!.state.height;
          if (stateH != null && stateH > 0) {
            return 'Auto (${stateH}p)';
          }
        } catch (_) {}
      }
    }
    return _selectedQuality?.shortLabel ?? 'Auto';
  }

  String _formatYoutubeQuality(String q) {
    if (q == 'hd1080' || q == '1080') return 'Auto (1080p)';
    if (q == 'hd720' || q == '720') return 'Auto (720p)';
    if (q == 'large' || q == '480') return 'Auto (480p)';
    if (q == 'medium' || q == '360') return 'Auto (360p)';
    if (q == 'small' || q == '240') return 'Auto (240p)';
    if (q == 'tiny' || q == '144') return 'Auto (144p)';
    if (q == 'highres') return 'Auto (4K)';
    return 'Auto ($q)';
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
        onQualitiesChanged: (qualities) {
          if (_isDisposed || _mediaType != 'direct_url') return;
          _availableQualities = qualities;
          if (_webVideoAdapter?.selectedQuality != null) {
            _selectedQuality = _webVideoAdapter!.selectedQuality;
          }
          notifyListeners();
          _applySavedQualityPreference();
        },
      );
    } catch (e) {
      debugPrint('[UnifiedPlayerController] Error init WebVideoAdapter: $e');
    }
  }

  void _initMediaKit() {
    try {
      _mkPlayer = Player();
      _mkPlayer!.setVolume(_volume * 100);

      // On Android Emulator, default vo=gpu fails with EGL_BAD_ATTRIBUTE (0x3004) causing black screen.
      // mediacodec_embed renders directly to the Surface without EGL context creation failures.
      final bool isEmu = (!kIsWeb && Platform.isAndroid) && (_isAndroidEmulator == true);
      _mkVideoController = VideoController(
        _mkPlayer!,
        configuration: VideoControllerConfiguration(
          vo: isEmu ? 'mediacodec_embed' : null,
          hwdec: isEmu ? 'mediacodec' : null,
        ),
      );

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

      // Listen to video dimensions for single files / P2P stream
      _subscriptions.add(_mkPlayer!.stream.videoParams.listen((params) {
        if (_isDisposed || _mediaType != 'direct_url') return;
        if ((isLocalFile || isP2PStream || _availableQualities.length <= 1) &&
            params.h != null &&
            params.h! > 0) {
          _availableQualities = [
            VideoQuality.fixed(
              label: '${params.h}p (Kualitas Asli)',
              height: params.h,
              width: params.w,
            ),
          ];
          _selectedQuality = _availableQualities.first;
          notifyListeners();
        }
      }));
    } catch (e) {
      debugPrint('[UnifiedPlayerController] Error init media_kit: $e');
    }
  }

  void _updateMediaKitQualities(List<VideoTrack> videoTracks) {
    final validTracks = videoTracks
        .where((t) => t.id != 'no' && t.id != 'auto')
        .toList();

    // If local file or single track container, treat as original fixed quality
    if (isLocalFile || isP2PStream || validTracks.length <= 1) {
      final h = validTracks.isNotEmpty
          ? (validTracks.first.h ?? _mkPlayer?.state.height)
          : _mkPlayer?.state.height;
      final w = validTracks.isNotEmpty
          ? (validTracks.first.w ?? _mkPlayer?.state.width)
          : _mkPlayer?.state.width;
      _availableQualities = [
        VideoQuality.fixed(
          label: (h != null && h > 0)
              ? '${h}p (Kualitas Asli)'
              : 'Kualitas Asli (Direct)',
          height: h,
          width: w,
        ),
      ];
      _selectedQuality = _availableQualities.first;
      notifyListeners();
      return;
    }

    final List<VideoQuality> list = [
      const VideoQuality.auto(mode: QualityControlMode.directTrack),
    ];
    final Set<String> seen = {'auto'};

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
            width: track.w,
            bitrate: track.bitrate,
            mode: QualityControlMode.directTrack,
            rawTrack: track,
          ),
        );
      }
    }

    _availableQualities = list;
    notifyListeners();
    _applySavedQualityPreference();
  }

  void _updateSelectedMediaKitQuality(VideoTrack currentTrack) {
    if (isLocalFile || isP2PStream || _availableQualities.length <= 1) {
      if (_availableQualities.isNotEmpty) {
        _selectedQuality = _availableQualities.first;
      }
      return;
    }
    if (currentTrack.id == 'auto' || currentTrack.id == 'no') {
      _selectedQuality = _availableQualities.firstWhere(
        (q) => q.isAuto,
        orElse: () => const VideoQuality.auto(),
      );
    } else {
      _selectedQuality = _availableQualities.firstWhere(
        (q) => q.id == currentTrack.id,
        orElse: () => VideoQuality(
          id: currentTrack.id,
          label: currentTrack.h != null ? '${currentTrack.h}p' : currentTrack.id,
          height: currentTrack.h,
          width: currentTrack.w,
          bitrate: currentTrack.bitrate,
          mode: QualityControlMode.directTrack,
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
          title: 'Video YouTube',
          thumbnailUrl: 'https://img.youtube.com/vi/$ytId/hqdefault.jpg',
        );
      }
    }

    if (trimmed.contains('bilibili.tv') ||
        trimmed.contains('bilibili.com') ||
        trimmed.contains('b23.tv')) {
      final uri = Uri.tryParse(trimmed);
      String? mediaId;
      if (uri != null && uri.pathSegments.isNotEmpty) {
        mediaId = uri.pathSegments.last;
      }
      return DetectedMedia(
        mediaType: 'bstation',
        mediaUrl: trimmed,
        mediaId: mediaId,
        title: 'Video Bstation',
      );
    }

    if (trimmed.contains('dailymotion.com') || trimmed.contains('dai.ly')) {
      final dmId = DailymotionPlayerController.extractVideoId(trimmed);
      if (dmId != null && dmId.isNotEmpty) {
        return DetectedMedia(
          mediaType: 'dailymotion',
          mediaUrl: 'https://www.dailymotion.com/video/$dmId',
          mediaId: dmId,
          title: 'Video Dailymotion',
          thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/$dmId',
        );
      }
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final uri = Uri.tryParse(trimmed);
      var filename = uri != null && uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'Direct Video';
      if (filename.contains('?')) {
        filename = filename.split('?').first;
      }
      if (RegExp(r'^\d+(\.[a-zA-Z0-9]+)?$').hasMatch(filename)) {
        filename = 'Video Stream';
      }
      return DetectedMedia(
        mediaType: 'direct_url',
        mediaUrl: trimmed,
        title: filename.isNotEmpty ? filename : 'Direct Video Stream',
      );
    }

    if (trimmed.startsWith('/') ||
        trimmed.startsWith('file://') ||
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed)) {
      final cleanPath = trimmed.replaceFirst(RegExp(r'^file:\/\/'), '');
      final filename = cleanPath.split(RegExp(r'[/\\]')).last;
      return DetectedMedia(
        mediaType: 'direct_url',
        mediaUrl: trimmed,
        title: filename.isNotEmpty ? filename : 'File Video Lokal',
      );
    }

    if (trimmed.startsWith('p2p://')) {
      final uri = Uri.tryParse(trimmed);
      final filename = uri != null && uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : 'P2P Stream';
      return DetectedMedia(
        mediaType: 'direct_url',
        mediaUrl: trimmed,
        title: filename.isNotEmpty ? filename : 'P2P Video Stream',
      );
    }

    if (trimmed.startsWith('blob:')) {
      return DetectedMedia(
        mediaType: 'direct_url',
        mediaUrl: trimmed,
        title: 'File Video Lokal',
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
        if (playing && !_isMuted && !kIsWeb) {
          _ytController?.unMute();
          _ytController?.setVolume((_volume * 100).round());
        }
        notifyListeners();
        onPlaybackStateChanged?.call(playing ? 'playing' : 'paused');
      }
      if (value.playbackQuality != null &&
          value.playbackQuality!.isNotEmpty &&
          value.playbackQuality != _youtubeQuality) {
        _updateYoutubeQuality(value.playbackQuality);
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
    _bstationController!.onQualitiesChanged = (qualities) {
      if (_isDisposed || _mediaType != 'bstation') return;
      _availableQualities = qualities;
      notifyListeners();
      _applySavedQualityPreference();
    };
    _bstationController!.onQualitySelectedChanged = (quality) {
      if (_isDisposed || _mediaType != 'bstation') return;
      _selectedQuality = quality;
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
    _dailymotionController!.onQualitiesChanged = (qualities) {
      if (_isDisposed || _mediaType != 'dailymotion') return;
      _availableQualities = qualities;
      notifyListeners();
      _applySavedQualityPreference();
    };
    _dailymotionController!.onQualitySelectedChanged = (quality) {
      if (_isDisposed || _mediaType != 'dailymotion') return;
      _selectedQuality = quality;
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
      _youtubeQuality = '';
      _availableQualities = [
        const VideoQuality(
          id: 'auto',
          label: 'Auto (Adaptif)',
          mode: QualityControlMode.embeddedUi,
        ),
      ];
      _selectedQuality = _availableQualities.first;

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
            params: YoutubePlayerParams(
              showControls: false,
              showFullscreenButton: false,
              mute: kIsWeb,
              enableJavaScript: true,
              pointerEvents: PointerEvents.none,
              enableKeyboard: false,
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
          if (!_isMuted && !kIsWeb) {
            await _ytController!.unMute();
            await _ytController!.setVolume((_volume * 100).round());
          }
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
      _availableQualities = _bstationController?.availableQualities.isNotEmpty == true
          ? _bstationController!.availableQualities
          : [
              const VideoQuality.auto(
                label: 'Auto (Otomatis Bstation)',
                mode: QualityControlMode.webviewBridge,
              ),
              VideoQuality.bstation(id: '720', label: '720p HD', height: 720),
              VideoQuality.bstation(id: '480', label: '480p Standar', height: 480),
              VideoQuality.bstation(id: '360', label: '360p Hemat', height: 360),
            ];
      _selectedQuality =
          _bstationController?.selectedQuality ?? _availableQualities.first;

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
        if (!_isMuted) {
          await _bstationController!.setVolume(_volume);
        }
      } catch (e) {
        debugPrint('[UnifiedPlayerController] Bstation load error: $e');
        _errorMessage = 'Gagal memuat Bstation video: $e';
        _isPlaying = false;
      }
      notifyListeners();
      return;
    }

    if (type == 'dailymotion') {
      _availableQualities = _dailymotionController?.availableQualities.isNotEmpty == true
          ? _dailymotionController!.availableQualities
          : [
              const VideoQuality.auto(
                label: 'Auto (Otomatis Dailymotion)',
                mode: QualityControlMode.webviewBridge,
              ),
              VideoQuality.dailymotion('1080'),
              VideoQuality.dailymotion('720'),
              VideoQuality.dailymotion('480'),
              VideoQuality.dailymotion('360'),
              VideoQuality.dailymotion('240'),
            ];
      _selectedQuality =
          _dailymotionController?.selectedQuality ?? _availableQualities.first;

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
        if (!_isMuted) {
          await _dailymotionController!.setVolume(_volume);
        }
      } catch (e) {
        debugPrint('[UnifiedPlayerController] Dailymotion load error: $e');
        _errorMessage = 'Gagal memuat Dailymotion video: $e';
        _isPlaying = false;
      }
      notifyListeners();
      return;
    }

    // Direct URL: pause YouTube, Bstation, and Dailymotion player if active
    if (isLocalFile || isP2PStream) {
      _availableQualities = [
        VideoQuality.fixed(label: 'Kualitas Asli (Direct)'),
      ];
      _selectedQuality = _availableQualities.first;
    }
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
    } else if (url.startsWith('blob:') && !kIsWeb) {
      _errorMessage = 'Host sedang memutar video lokal dari Web. Gunakan tombol "Punya File?" di atas untuk memutar salinan file video Anda (Syncplay).';
      _isPlaying = false;
    } else if (_mkPlayer != null) {
      try {
        await _mkPlayer!.setVolume(_isMuted ? 0 : _volume * 100);
        await _mkPlayer!.open(Media(url), play: autoPlay);
        if (startSeconds > 0) {
          await _mkPlayer!.seek(
            Duration(milliseconds: (startSeconds * 1000).round()),
          );
        }
        _isPlaying = autoPlay;
      } catch (e) {
        debugPrint('[UnifiedPlayerController] MediaKit open error: $e');
        if (isLocalFilePath(url)) {
          _errorMessage =
              'File video ini berada di penyimpanan perangkat Host. Anda dapat menggunakan tombol "Pilih File Lokal Saya" (Syncplay) jika memiliki salinan filenya, atau minta Host mengaktifkan "Bagi Layar".';
        } else {
          _errorMessage = 'Gagal memutar video: $e';
        }
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
      if (kIsWeb && _mediaType == 'youtube') {
        try {
          await _ytController?.mute();
          _isMuted = true;
          await _ytController?.playVideo();
          notifyListeners();
          return;
        } catch (_) {}
      }
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

  /// Explicitly unmutes the player, restoring volume.
  Future<void> unmute() async {
    _isMuted = false;
    if (_volume <= 0.05) _volume = 1.0;
    notifyListeners();

    try {
      if (_mediaType == 'youtube') {
        await _ytController?.unMute();
        await _ytController?.setVolume((_volume * 100).round());
      } else if (_mediaType == 'bstation') {
        await _bstationController?.setVolume(_volume);
      } else if (_mediaType == 'dailymotion') {
        await _dailymotionController?.setVolume(_volume);
      } else if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.setMuted(false);
        await _webVideoAdapter?.setVolume(_volume);
      } else {
        await _mkPlayer?.setVolume(_volume * 100);
      }
    } catch (e) {
      debugPrint('[UnifiedPlayerController] unmute error: $e');
    }
  }

  /// Sets video playback quality (local client preference).
  Future<void> setVideoQuality(VideoQuality quality) async {
    _selectedQuality = quality;
    notifyListeners();
    _saveUserQualityPreference(quality);

    try {
      if (_mediaType == 'bstation') {
        await _bstationController?.setQuality(quality.id);
      } else if (_mediaType == 'dailymotion') {
        await _dailymotionController?.setQuality(quality.id);
      } else if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.setQuality(quality.id);
      } else if (_mkPlayer != null) {
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

  void _updateYoutubeQuality(String? quality) {
    _youtubeQuality = quality ?? '';
    final label = _formatYoutubeQuality(_youtubeQuality);
    _availableQualities = [
      VideoQuality(
        id: quality ?? 'auto',
        label: label,
        mode: QualityControlMode.embeddedUi,
      ),
    ];
    _selectedQuality = _availableQualities.first;
    notifyListeners();
  }

  Future<void> _saveUserQualityPreference(VideoQuality quality) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (quality.isAuto) {
        await prefs.remove(_prefQualityKey);
      } else if (quality.height != null) {
        await prefs.setInt(_prefQualityKey, quality.height!);
      }
    } catch (e) {
      debugPrint('[UnifiedPlayerController] Failed to save quality preference: $e');
    }
  }

  Future<void> _applySavedQualityPreference() async {
    if (_availableQualities.length <= 1) return;
    if (!supportsQualitySelection) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final targetHeight = prefs.getInt(_prefQualityKey);
      if (targetHeight == null) return;

      // Find the best matching quality
      VideoQuality? match;
      for (final q in _availableQualities) {
        if (!q.isAuto && q.height == targetHeight) {
          match = q;
          break;
        }
      }
      // If not exact match, find closest height <= targetHeight
      if (match == null) {
        final sorted = _availableQualities
            .where((q) => !q.isAuto && q.height != null)
            .toList()
          ..sort((a, b) => b.height!.compareTo(a.height!));
        for (final q in sorted) {
          if (q.height! <= targetHeight) {
            match = q;
            break;
          }
        }
      }

      if (match != null && match.id != _selectedQuality?.id) {
        debugPrint(
          '[UnifiedPlayerController] Restoring saved quality preference: ${match.label}',
        );
        await setVideoQuality(match);
      }
    } catch (e) {
      debugPrint(
        '[UnifiedPlayerController] Failed to apply saved quality preference: $e',
      );
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
