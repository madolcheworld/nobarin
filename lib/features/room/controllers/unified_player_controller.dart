import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../../../core/utils/fullscreen/fullscreen_helper.dart';
import '../models/video_quality.dart';
import '../services/hls_manifest_parser.dart';
import 'bstation_player_controller.dart';
import 'dailymotion_player_controller.dart';
import 'google_drive_player_controller.dart';
import 'vimeo_player_controller.dart';
import 'web_browser_player_controller.dart';
import 'web_video_adapter/web_video_adapter.dart';

/// Normalized result of detecting media platform, URLs, and IDs
class DetectedMedia {
  final String mediaType; // 'direct_url' | 'youtube' | 'bstation' | 'dailymotion' | 'vimeo' | 'google_drive' | 'web_browser'
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
  bool get isVimeo => mediaType == 'vimeo';
  bool get isGoogleDrive => mediaType == 'google_drive';
  bool get isWebBrowser => mediaType == 'web_browser';
}

class UnifiedPlayerController extends ChangeNotifier {
  static const String _prefQualityKey = 'nobarin_pref_video_quality';

  String _mediaType = 'direct_url';
  String _mediaUrl = '';
  final ValueNotifier<bool> hasMediaNotifier = ValueNotifier<bool>(false);
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isFullscreen = false;
  bool _isFullscreenTransition = false;
  bool _wasPlayingBeforeFullscreen = false;
  Timer? _fullscreenTransitionTimer;
  double _position = 0.0;
  final ValueNotifier<double> positionNotifier = ValueNotifier<double>(0.0);
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
  bool _isDetectingQualities = false;
  String _hlsMasterUrl = '';
  String _activeVariantStreamUrl = '';
  double? _pendingQualitySeekSeconds;
  bool _isSwitchingQuality = false;
  bool _hasAppliedSavedQualityForCurrentMedia = false;
  List<VideoQuality> _parsedHlsQualities = [];
  Timer? _ytQualityPollTimer;
  Timer? _qualityDetectTimeoutTimer;

  // HTML5 Web Video Player (Web direct URL)
  WebVideoAdapter? _webVideoAdapter;

  // YouTube IFrame Player Controller
  YoutubePlayerController? _ytController;

  // Bstation Web / Mobile Player Controller
  BstationPlayerController? _bstationController;

  // Dailymotion Web / Mobile Player Controller
  DailymotionPlayerController? _dailymotionController;

  // Vimeo Web / Mobile Player Controller
  VimeoPlayerController? _vimeoController;

  // Google Drive Web / Mobile Player Controller
  GoogleDrivePlayerController? _googleDriveController;

  // Web Browser Universal Player Controller
  WebBrowserPlayerController? _webBrowserController;

  // MediaKit Player & VideoController (Native desktop / mobile direct URL)
  Player? _mkPlayer;
  VideoController? _mkVideoController;
  final List<StreamSubscription> _subscriptions = [];

  static bool? _isAndroidEmulator;

  /// Initializes platform-specific video controller settings (e.g. Android emulator detection).
  static Future<void> initializePlatformSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
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

  /// Optional hook allowing RoomScreen to intercept back-button fullscreen exit
  /// (e.g., to close the fullscreen comment drawer first). Returns true if intercepted.
  bool Function()? onInterceptExitFullscreen;

  String get mediaType => _mediaType;
  String get mediaUrl => _mediaUrl;
  bool get isLoaded => _mediaUrl.isNotEmpty;
  bool get hasMedia => _mediaUrl.isNotEmpty;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  bool get isFullscreen => _isFullscreen;
  bool get isFullscreenTransition => _isFullscreenTransition;
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
  VimeoPlayerController? get vimeoController => _vimeoController;
  GoogleDrivePlayerController? get googleDriveController => _googleDriveController;
  WebBrowserPlayerController? get webBrowserController => _webBrowserController;
  Widget? get webVideoWidget => _webVideoAdapter?.buildVideoWidget();

  List<VideoQuality> get availableQualities =>
      List.unmodifiable(_availableQualities);
  VideoQuality? get selectedQuality => _selectedQuality;
  bool get hasMultipleQualities => _availableQualities.length > 1;
  bool get isDetectingQualities => _isDetectingQualities;

  /// Number of explicit (non-Auto) resolution options detected for the current video
  int get explicitQualityCount =>
      _availableQualities.where((q) => !q.isAuto).length;

  /// Maximum resolution height detected across available qualities or active video stream
  int? get maxDetectedHeight {
    int maxH = 0;
    for (final q in _availableQualities) {
      if (q.height != null && q.height! > maxH) {
        maxH = q.height!;
      }
    }
    if (maxH > 0) return maxH;

    if (_mediaType == 'bstation' && _bstationController?.detectedHeight != null) {
      return _bstationController!.detectedHeight;
    }
    if (_mediaType == 'dailymotion' && _dailymotionController?.detectedHeight != null) {
      return _dailymotionController!.detectedHeight;
    }
    if (_mediaType == 'vimeo' && _vimeoController?.detectedHeight != null) {
      return _vimeoController!.detectedHeight;
    }
    if (_mediaType == 'google_drive' && _googleDriveController?.detectedHeight != null) {
      return _googleDriveController!.detectedHeight;
    }
    if (_mediaType == 'web_browser' && _webBrowserController?.detectedHeight != null) {
      return _webBrowserController!.detectedHeight;
    }
    if (_mediaType == 'youtube' && _youtubeQuality.isNotEmpty) {
      return VideoQuality.youtube(_youtubeQuality).height;
    }
    if (_mediaType == 'direct_url' && _mkPlayer != null) {
      try {
        final h = _mkPlayer!.state.height;
        final w = _mkPlayer!.state.width;
        return VideoQuality.normalizeResolutionHeight(width: w, height: h);
      } catch (_) {}
    }
    return null;
  }

  /// Formatted label of the maximum resolution supported by the current video
  String? get maxResolutionLabel {
    final h = maxDetectedHeight;
    if (h == null || h <= 0) return null;
    if (h >= 4320) return '8K (${h}p)';
    if (h >= 2160) return '4K (${h}p)';
    if (h >= 1440) return '2K (${h}p)';
    if (h >= 1080) return 'Full HD (${h}p)';
    if (h >= 720) return 'HD (${h}p)';
    return '${h}p';
  }

  /// Whether the user can select from multiple detected resolutions for this media
  bool get supportsQualitySelection {
    if (isLocalFile || isP2PStream) return false;
    return _availableQualities.length > 1;
  }

  /// Checks whether a given URL or path points to a local device file
  static bool isLocalFilePath(String url) {
    final trimmed = url.trim();
    return trimmed.startsWith('/') ||
        trimmed.startsWith('file://') ||
        trimmed.startsWith('content://') ||
        trimmed.startsWith('blob:') ||
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed);
  }

  /// Whether current media is playing directly from a local device file
  bool get isLocalFile => isLocalFilePath(_mediaUrl);

  /// Whether current media is an active P2P direct stream or loopback stream
  bool get isP2PStream =>
      _mediaUrl.startsWith('p2p://') || _mediaUrl.contains('127.0.0.1');

  /// Whether current direct URL is an HLS (.m3u8) stream
  bool get isHlsStream =>
      _mediaType == 'direct_url' &&
      (HlsManifestParser.isHlsUrl(_mediaUrl) || _hlsMasterUrl.isNotEmpty);

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

    if (_mediaType == 'vimeo') {
      if (_vimeoController?.detectedHeight != null) {
        return 'Auto (${_vimeoController!.detectedHeight}p)';
      }
      return _vimeoController?.selectedQuality?.shortLabel ?? 'Auto';
    }

    if (_mediaType == 'google_drive') {
      if (_googleDriveController?.detectedHeight != null) {
        return 'Auto (${_googleDriveController!.detectedHeight}p)';
      }
      return _googleDriveController?.selectedQuality?.shortLabel ?? 'Auto';
    }

    if (_mediaType == 'web_browser') {
      if (_webBrowserController?.detectedHeight != null) {
        return 'Auto (${_webBrowserController!.detectedHeight}p)';
      }
      return _webBrowserController?.selectedQuality?.shortLabel ?? 'Auto';
    }

    if (_mediaType == 'direct_url') {
      if (isLocalFile || isP2PStream) {
        final rawH = _mkPlayer?.state.height;
        final rawW = _mkPlayer?.state.width;
        final h = VideoQuality.normalizeResolutionHeight(width: rawW, height: rawH);
        if (h != null && h > 0) return '${h}p (Asli)';
        return 'Asli';
      }
      if (kIsWeb && _webVideoAdapter?.selectedQuality != null) {
        return _webVideoAdapter!.selectedQuality!.shortLabel;
      }
      if (_mkPlayer != null) {
        try {
          final currentTrack = _mkPlayer!.state.track.video;
          final normTrackH = VideoQuality.normalizeResolutionHeight(
            width: currentTrack.w,
            height: currentTrack.h,
          );
          if (normTrackH != null && normTrackH > 0) {
            return 'Auto (${normTrackH}p)';
          }
          final stateH = VideoQuality.normalizeResolutionHeight(
            width: _mkPlayer!.state.width,
            height: _mkPlayer!.state.height,
          );
          if (stateH != null && stateH > 0) {
            return 'Auto (${stateH}p)';
          }
        } catch (_) {}
      }
    }
    return _selectedQuality?.shortLabel ?? 'Auto';
  }

  String _formatYoutubeQuality(String q) {
    if (q == 'hd2160' || q == '2160' || q == 'highres') return 'Auto (4K)';
    if (q == 'hd2880' || q == '2880') return 'Auto (5K)';
    if (q == 'hd1440' || q == '1440') return 'Auto (1440p)';
    if (q == 'hd1080' || q == '1080') return 'Auto (1080p)';
    if (q == 'hd720' || q == '720') return 'Auto (720p)';
    if (q == 'large' || q == '480') return 'Auto (480p)';
    if (q == 'medium' || q == '360') return 'Auto (360p)';
    if (q == 'small' || q == '240') return 'Auto (240p)';
    if (q == 'tiny' || q == '144') return 'Auto (144p)';
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
          positionNotifier.value = pos;
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
          if (!playing && _isFullscreenTransition && _wasPlayingBeforeFullscreen) {
            debugPrint('[UnifiedPlayerController] WebVideoAdapter spurious pause ignored during fullscreen transition');
            _webVideoAdapter?.play();
            return;
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

      // Allow HLS streams whose MPEG-TS segments use non-standard extensions
      // (e.g. .pict, .png, .jpg, .txt, .html used by streaming CDNs like playcdn).
      try {
        final dynamic nativePlatform = _mkPlayer!.platform;
        nativePlatform.setProperty('tls-verify', 'no');
        nativePlatform.setProperty(
          'demuxer-lavf-o',
          'allowed_extensions=ALL,allowed_segment_extensions=ALL',
        );
        nativePlatform.setProperty(
          'user-agent',
          'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
        );
      } catch (_) {}

      // On Android Emulator, default vo=gpu fails with EGL_BAD_ATTRIBUTE (0x3004) causing black screen.
      // mediacodec_embed renders directly to the Surface without EGL context creation failures.
      final bool isEmu = (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) && (_isAndroidEmulator == true);
      _mkVideoController = VideoController(
        _mkPlayer!,
        configuration: VideoControllerConfiguration(
          vo: isEmu ? 'mediacodec_embed' : null,
          hwdec: isEmu ? 'mediacodec' : null,
        ),
      );

      _bindMediaKitListeners();
    } catch (e) {
      debugPrint('[UnifiedPlayerController] Error init media_kit: $e');
    }
  }

  void _bindMediaKitListeners() {
    if (_mkPlayer == null) return;
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    if (_ytController != null) {
      _setupYoutubeListeners();
    }

    _subscriptions.add(_mkPlayer!.stream.position.listen((pos) {
      if (_isDisposed || _mediaType != 'direct_url') return;
      final posSec = pos.inMilliseconds / 1000.0;
      if (posSec > 0 && _errorMessage != null && (_mkPlayer?.state.playing ?? false)) {
        _errorMessage = null;
        _isPlaying = true;
        notifyListeners();
      }
      if (_isSwitchingQuality && _pendingQualitySeekSeconds != null) {
        if (posSec < 0.5 && _pendingQualitySeekSeconds! > 1.0) {
          return;
        }
        if ((posSec - _pendingQualitySeekSeconds!).abs() <= 2.5) {
          _isSwitchingQuality = false;
          _pendingQualitySeekSeconds = null;
        }
      }
      _position = posSec;
      positionNotifier.value = posSec;
      onPositionChanged?.call(_position);
    }));

    _subscriptions.add(_mkPlayer!.stream.duration.listen((dur) {
      if (_isDisposed || _mediaType != 'direct_url') return;
      final durSec = dur.inMilliseconds / 1000.0;
      if (durSec > 0) {
        _duration = durSec;
        if (_pendingQualitySeekSeconds != null && _pendingQualitySeekSeconds! > 0) {
          final targetSeek = _pendingQualitySeekSeconds!;
          _pendingQualitySeekSeconds = null;
          _mkPlayer
              ?.seek(Duration(milliseconds: (targetSeek * 1000).round()))
              .whenComplete(() {
            _isSwitchingQuality = false;
          });
        }
        notifyListeners();
      }
    }));

    _subscriptions.add(_mkPlayer!.stream.playing.listen((playing) {
      if (_isDisposed || _mediaType != 'direct_url') return;
      if (playing && _errorMessage != null) {
        _errorMessage = null;
      }
      if (!playing && _isSwitchingQuality) {
        return;
      }
      if (!playing && _isFullscreenTransition && _wasPlayingBeforeFullscreen) {
        debugPrint('[UnifiedPlayerController] MediaKit spurious pause ignored during fullscreen transition');
        _mkPlayer?.play();
        return;
      }
      if (_isPlaying != playing) {
        _isPlaying = playing;
        notifyListeners();
        onPlaybackStateChanged?.call(playing ? 'playing' : 'paused');
      }
    }));

    _subscriptions.add(_mkPlayer!.stream.buffering.listen((buffering) {
      if (_isDisposed || _mediaType != 'direct_url') return;
      if (_isBuffering != buffering) {
        _isBuffering = buffering;
        notifyListeners();
      }
    }));

    _subscriptions.add(_mkPlayer!.stream.completed.listen((completed) {
      if (_isDisposed || _mediaType != 'direct_url') return;
      if (completed && !_isSwitchingQuality) {
        onPlaybackEnded?.call();
      }
    }));

    _subscriptions.add(_mkPlayer!.stream.error.listen((err) {
      if (_isDisposed || _mediaType != 'direct_url') return;
      final trimmedErr = err.trim();
      final isFatalOpenError = trimmedErr.startsWith('Failed to open') ||
          trimmedErr.startsWith('Can not open') ||
          trimmedErr.contains('Unrecognized file format');
      if (!isFatalOpenError) {
        debugPrint('[UnifiedPlayerController] Non-fatal MediaKit warning ignored: $trimmedErr');
        return;
      }
      debugPrint('[UnifiedPlayerController] MediaKit fatal stream.error: $trimmedErr');
      _errorMessage = 'Gagal memutar video: $trimmedErr';
      _isPlaying = false;
      notifyListeners();
    }));

    _subscriptions.add(_mkPlayer!.stream.log.listen((log) {
      if (_isDisposed) return;
      debugPrint('[MPV:${log.level}] ${log.prefix}: ${log.text}');
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
      final normH = VideoQuality.normalizeResolutionHeight(
        width: params.w,
        height: params.h,
      );
      if (params.w != null && params.h != null && params.h! > 0) {
        if (_errorMessage != null) {
          _errorMessage = null;
        }
        debugPrint(
          '[UnifiedPlayerController] MediaKit videoParams: ${params.w}x${params.h} (norm=${normH}p)',
        );
      }
      if ((isLocalFile ||
              isP2PStream ||
              (!_isDetectingQualities &&
                  _availableQualities.length <= 1 &&
                  _parsedHlsQualities.isEmpty &&
                  _activeVariantStreamUrl.isEmpty)) &&
          normH != null &&
          normH > 0) {
        _availableQualities = [
          VideoQuality.fixed(
            label: '${normH}p (Kualitas Asli)',
            height: normH,
            width: params.w,
          ),
        ];
        _selectedQuality = _availableQualities.first;
        notifyListeners();
      } else if (normH != null && normH > 0) {
        notifyListeners();
      }
    }));
  }

  Future<void> _probeHlsManifestQualities(String url) async {
    try {
      final parsed = await HlsManifestParser.fetchAndParseQualities(url);
      if (_isDisposed || _mediaType != 'direct_url') return;
      if (_mediaUrl != url && _hlsMasterUrl != url) return;
      _isDetectingQualities = false;
      _qualityDetectTimeoutTimer?.cancel();
      if (parsed.isNotEmpty) {
        _parsedHlsQualities = parsed;
        _mergeHlsAndMediaKitQualities(
          _mkPlayer?.state.tracks.video ?? const <VideoTrack>[],
        );
      } else if (_parsedHlsQualities.isEmpty && _availableQualities.length <= 1) {
        _updateMediaKitQualities(
          _mkPlayer?.state.tracks.video ?? const <VideoTrack>[],
        );
      }
    } catch (e) {
      debugPrint('[UnifiedPlayerController] HLS manifest probe error: $e');
      if (!_isDisposed) {
        _isDetectingQualities = false;
        notifyListeners();
      }
    }
  }

  void _mergeHlsAndMediaKitQualities(List<VideoTrack> videoTracks) {
    final validTracks = videoTracks
        .where((t) => t.id != 'no' && t.id != 'auto')
        .toList();

    if (_parsedHlsQualities.isEmpty) {
      _updateMediaKitQualities(videoTracks);
      return;
    }

    if (_parsedHlsQualities.length == 1 &&
        _parsedHlsQualities.first.mode == QualityControlMode.fixedOriginal) {
      _availableQualities = _parsedHlsQualities;
      _selectedQuality = _availableQualities.first;
      notifyListeners();
      return;
    }

    final List<VideoQuality> enriched = [];
    for (final q in _parsedHlsQualities) {
      if (q.isAuto) {
        enriched.add(q);
        continue;
      }
      VideoTrack? matchedTrack;
      if (_activeVariantStreamUrl.isEmpty) {
        for (final track in validTracks) {
          final normH = VideoQuality.normalizeResolutionHeight(
            width: track.w,
            height: track.h,
          );
          if (normH != null && q.height != null && normH == q.height) {
            matchedTrack = track;
            break;
          }
          if (track.bitrate != null &&
              q.bitrate != null &&
              track.bitrate! > 0 &&
              (track.bitrate! - q.bitrate!).abs() < 50000) {
            matchedTrack = track;
            break;
          }
        }
      }
      enriched.add(
        VideoQuality(
          id: q.id,
          label: q.label,
          height: q.height,
          width: q.width,
          bitrate: q.bitrate,
          fps: q.fps,
          streamUrl: q.streamUrl,
          mode: QualityControlMode.directTrack,
          rawTrack: matchedTrack ?? (_activeVariantStreamUrl.isEmpty ? q.rawTrack : null),
        ),
      );
    }

    _availableQualities = enriched;
    if (_selectedQuality == null ||
        !_availableQualities.any((q) => q.id == _selectedQuality!.id)) {
      _selectedQuality = _availableQualities.first;
    }
    notifyListeners();
    _applySavedQualityPreference();
  }

  void _updateMediaKitQualities(List<VideoTrack> videoTracks) {
    if (_parsedHlsQualities.isNotEmpty) {
      _mergeHlsAndMediaKitQualities(videoTracks);
      return;
    }

    final validTracks = videoTracks
        .where((t) => t.id != 'no' && t.id != 'auto')
        .toList();

    // If HLS manifest is still being probed and libmpv hasn't exposed multiple resolved tracks yet, wait
    if (_isDetectingQualities && isHlsStream && validTracks.length <= 1) {
      return;
    }

    // If local file or single track container, treat as original fixed quality
    if (isLocalFile || isP2PStream || validTracks.length <= 1) {
      final rawH = validTracks.isNotEmpty
          ? (validTracks.first.h ?? _mkPlayer?.state.height)
          : _mkPlayer?.state.height;
      final rawW = validTracks.isNotEmpty
          ? (validTracks.first.w ?? _mkPlayer?.state.width)
          : _mkPlayer?.state.width;
      final normH = VideoQuality.normalizeResolutionHeight(width: rawW, height: rawH);
      _availableQualities = [
        VideoQuality.fixed(
          label: (normH != null && normH > 0)
              ? '${normH}p (Kualitas Asli)'
              : 'Kualitas Asli (Direct)',
          height: normH,
          width: rawW,
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
      final hA = VideoQuality.normalizeResolutionHeight(width: a.w, height: a.h) ?? 0;
      final hB = VideoQuality.normalizeResolutionHeight(width: b.w, height: b.h) ?? 0;
      if (hA != hB) return hB.compareTo(hA);
      return (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
    });

    // Count occurrences of each normalized height to disambiguate duplicate heights by bitrate
    final Map<int, int> heightCounts = {};
    for (final track in validTracks) {
      final normH = VideoQuality.normalizeResolutionHeight(width: track.w, height: track.h);
      if (normH != null && normH > 0) {
        heightCounts[normH] = (heightCounts[normH] ?? 0) + 1;
      }
    }

    for (final track in validTracks) {
      final normH = VideoQuality.normalizeResolutionHeight(width: track.w, height: track.h);
      String label;
      if (normH != null && normH > 0) {
        if (normH >= 2160) {
          label = '4K (${normH}p)';
        } else if (normH >= 1440) {
          label = '2K (${normH}p)';
        } else {
          label = '${normH}p';
        }
        if (track.fps != null && track.fps! > 30) {
          label += ' ${track.fps!.round()}fps';
        }
        if ((heightCounts[normH] ?? 0) > 1 && track.bitrate != null && track.bitrate! > 0) {
          final mbps = (track.bitrate! / 1000000).toStringAsFixed(1);
          label += ' ($mbps Mbps)';
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
            height: normH,
            width: track.w,
            bitrate: track.bitrate,
            fps: track.fps,
            mode: QualityControlMode.directTrack,
            rawTrack: track,
          ),
        );
      }
    }

    _isDetectingQualities = false;
    _qualityDetectTimeoutTimer?.cancel();
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
    if (_activeVariantStreamUrl.isNotEmpty ||
        (_parsedHlsQualities.isNotEmpty &&
            _selectedQuality != null &&
            !_selectedQuality!.isAuto &&
            _selectedQuality!.streamUrl != null)) {
      // Keep explicit HLS variant selection
      return;
    }
    if (_selectedQuality != null && _selectedQuality!.isAuto) {
      // Preserve Auto selection when libmpv resolves an adaptive track;
      // currentQualityLabel will dynamically display 'Auto (720p)'.
      notifyListeners();
      return;
    }
    if (currentTrack.id == 'auto' || currentTrack.id == 'no') {
      _selectedQuality = _availableQualities.firstWhere(
        (q) => q.isAuto,
        orElse: () => const VideoQuality.auto(),
      );
    } else {
      final normH = VideoQuality.normalizeResolutionHeight(
        width: currentTrack.w,
        height: currentTrack.h,
      );
      _selectedQuality = _availableQualities.firstWhere(
        (q) => q.id == currentTrack.id || (normH != null && q.height == normH),
        orElse: () => VideoQuality(
          id: currentTrack.id,
          label: normH != null ? '${normH}p' : currentTrack.id,
          height: normH,
          width: currentTrack.w,
          bitrate: currentTrack.bitrate,
          fps: currentTrack.fps,
          mode: QualityControlMode.directTrack,
          rawTrack: currentTrack,
        ),
      );
    }
    notifyListeners();
  }

  /// Extracts an 11-character YouTube video ID reliably from any URL format,
  /// including Shorts, Live streams, embed URLs, and URLs with tracking parameters.
  static String? extractYoutubeId(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    // 1. Direct 11-char ID
    if (RegExp(r'^[_\-a-zA-Z0-9]{11}$').hasMatch(trimmed)) {
      return trimmed;
    }

    // 2. Try library method first
    final libId = YoutubePlayerController.convertUrlToId(trimmed);
    if (libId != null && RegExp(r'^[_\-a-zA-Z0-9]{11}$').hasMatch(libId)) {
      return libId;
    }

    // 3. Fallback regexes
    final patterns = [
      RegExp(r'(?:youtube\.com|youtu\.be).*?[?&]v=([_\-a-zA-Z0-9]{11})', caseSensitive: false),
      RegExp(r'(?:youtube\.com|youtube-nocookie\.com)\/embed\/([_\-a-zA-Z0-9]{11})', caseSensitive: false),
      RegExp(r'youtube\.com\/shorts\/([_\-a-zA-Z0-9]{11})', caseSensitive: false),
      RegExp(r'youtube\.com\/live\/([_\-a-zA-Z0-9]{11})', caseSensitive: false),
      RegExp(r'youtu\.be\/([_\-a-zA-Z0-9]{11})', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(trimmed);
      if (match != null && match.groupCount >= 1) {
        return match.group(1);
      }
    }

    return null;
  }

  /// Centralized detection of platform, ID, and title from any video URL (Direct or YouTube)
  static DetectedMedia? detectMediaFromUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.contains('youtube.com') || trimmed.contains('youtu.be')) {
      final ytId = extractYoutubeId(trimmed);
      if (ytId != null && ytId.isNotEmpty) {
        return DetectedMedia(
          mediaType: 'youtube',
          mediaUrl: 'https://www.youtube.com/watch?v=$ytId',
          mediaId: ytId,
          title: 'Video YouTube',
          thumbnailUrl: 'https://img.youtube.com/vi/$ytId/hqdefault.jpg',
        );
      }
      // If recognized as YouTube domain but video ID cannot be parsed (e.g. channel or search URL),
      // DO NOT fall through to direct_url!
      return null;
    }

    if (trimmed.contains('bilibili.tv') ||
        trimmed.contains('bilibili.com') ||
        trimmed.contains('b23.tv')) {
      final canonicalUrl = trimmed.startsWith('http') ? trimmed : 'https://$trimmed';
      final uri = Uri.tryParse(canonicalUrl);
      String? mediaId;
      if (uri != null && uri.pathSegments.isNotEmpty) {
        mediaId = uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
      }
      return DetectedMedia(
        mediaType: 'bstation',
        mediaUrl: canonicalUrl,
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
      // If recognized as Dailymotion domain but video ID cannot be parsed,
      // DO NOT fall through to direct_url!
      return null;
    }

    if (trimmed.contains('vimeo.com')) {
      final vId = VimeoPlayerController.extractVideoId(trimmed);
      if (vId != null && vId.isNotEmpty) {
        return DetectedMedia(
          mediaType: 'vimeo',
          mediaUrl: 'https://vimeo.com/$vId',
          mediaId: vId,
          title: 'Video Vimeo',
          thumbnailUrl: 'https://vumbnail.com/$vId.jpg',
        );
      }
      // If recognized as Vimeo domain but video ID cannot be parsed,
      // DO NOT fall through to direct_url!
      return null;
    }

    if (trimmed.startsWith('webbrowser://')) {
      final normalized = WebBrowserPlayerController.normalizeWebUrl(trimmed);
      final uri = Uri.tryParse(normalized);
      final host = uri?.host.replaceFirst('www.', '') ?? 'Web';
      return DetectedMedia(
        mediaType: 'web_browser',
        mediaUrl: normalized,
        title: 'Video Web ($host)',
      );
    }

    if (trimmed.contains('drive.google.com') || trimmed.contains('docs.google.com')) {
      final gId = GoogleDrivePlayerController.extractFileId(trimmed);
      if (gId != null && gId.isNotEmpty) {
        return DetectedMedia(
          mediaType: 'google_drive',
          mediaUrl: 'https://drive.google.com/file/d/$gId/view',
          mediaId: gId,
          title: 'Video Google Drive',
        );
      }
      // If recognized as Google Drive domain but file ID cannot be parsed,
      // DO NOT fall through to direct_url!
      return null;
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final uri = Uri.tryParse(trimmed);
      var filename = uri != null && uri.pathSegments.isNotEmpty
          ? uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'Direct Video'
          : 'Direct Video';
      if (filename.contains('?')) {
        filename = filename.split('?').first;
      }
      try {
        filename = Uri.decodeComponent(filename);
      } catch (_) {}
      final dotIdx = filename.lastIndexOf('.');
      if (dotIdx != -1 && dotIdx > 0) {
        filename = filename.substring(0, dotIdx);
      }
      filename = filename.replaceAll(RegExp(r'[-_]+'), ' ').trim();
      if (RegExp(r'^\d+$').hasMatch(filename) || filename.isEmpty) {
        filename = 'Video Stream';
      }
      return DetectedMedia(
        mediaType: 'direct_url',
        mediaUrl: trimmed,
        title: filename,
      );
    }

    if (trimmed.startsWith('/') ||
        trimmed.startsWith('file://') ||
        trimmed.startsWith('content://') ||
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed)) {
      var cleanPath = trimmed.replaceFirst(RegExp(r'^(file|content):\/\/'), '');
      try {
        cleanPath = Uri.decodeComponent(cleanPath);
      } catch (_) {}
      var filename = cleanPath.split(RegExp(r'[/\\]')).last;
      if (filename.contains('?')) {
        filename = filename.split('?').first;
      }
      final dotIdx = filename.lastIndexOf('.');
      if (dotIdx != -1 && dotIdx > 0) {
        filename = filename.substring(0, dotIdx);
      }
      filename = filename.replaceAll(RegExp(r'[-_]+'), ' ').trim();
      return DetectedMedia(
        mediaType: 'direct_url',
        mediaUrl: trimmed,
        title: filename.isNotEmpty ? filename : 'File Video Lokal',
      );
    }

    if (trimmed.startsWith('p2p://')) {
      final uri = Uri.tryParse(trimmed);
      final filename = uri != null && uri.pathSegments.isNotEmpty
          ? uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'P2P Stream'
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

    _ytController!.setFullScreenListener((isYtFullscreen) {
      if (_isDisposed || _mediaType != 'youtube') return;
      if (!isYtFullscreen && _isFullscreen) {
        if (onInterceptExitFullscreen != null && onInterceptExitFullscreen!()) {
          _ytController?.enterFullScreen(lock: false);
          return;
        }
        exitFullscreen();
      } else if (isYtFullscreen && !_isFullscreen) {
        enterFullscreen();
      }
    });

    _subscriptions.add(_ytController!.videoStateStream.listen((state) {
      if (_isDisposed || _mediaType != 'youtube') return;
      final pos = state.position.inMilliseconds / 1000.0;
      if ((pos - _position).abs() >= 0.25) {
        _position = pos;
        positionNotifier.value = pos;
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
      final bool buffering = value.playerState == PlayerState.buffering;
      if (_isBuffering != buffering) {
        _isBuffering = buffering;
        notifyListeners();
      }
      if (value.playerState == PlayerState.ended) {
        onPlaybackEnded?.call();
      }
      if (playing || value.playerState == PlayerState.cued) {
        if (_availableQualities.length <= 1) {
          _fetchYoutubeAvailableQualities();
        }
      }
      if (_isPlaying != playing &&
          !buffering &&
          value.playerState != PlayerState.unknown &&
          value.playerState != PlayerState.cued) {
        if (!playing && _isFullscreenTransition && _wasPlayingBeforeFullscreen) {
          debugPrint('[UnifiedPlayerController] YouTube spurious pause ignored during fullscreen transition');
          _ytController?.playVideo();
          return;
        }
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
        positionNotifier.value = pos;
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
      if (!playing && _isFullscreenTransition && _wasPlayingBeforeFullscreen) {
        debugPrint('[UnifiedPlayerController] Bstation spurious pause ignored during fullscreen transition');
        _bstationController?.play();
        return;
      }
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
      if (qualities.length > 1) {
        _isDetectingQualities = false;
        _qualityDetectTimeoutTimer?.cancel();
      }
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
        positionNotifier.value = pos;
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
      if (!playing && _isFullscreenTransition && _wasPlayingBeforeFullscreen) {
        debugPrint('[UnifiedPlayerController] Dailymotion spurious pause ignored during fullscreen transition');
        _dailymotionController?.play();
        return;
      }
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
      if (qualities.length > 1) {
        _isDetectingQualities = false;
        _qualityDetectTimeoutTimer?.cancel();
      }
      notifyListeners();
      _applySavedQualityPreference();
    };
    _dailymotionController!.onQualitySelectedChanged = (quality) {
      if (_isDisposed || _mediaType != 'dailymotion') return;
      _selectedQuality = quality;
      notifyListeners();
    };
  }

  void _setupVimeoListeners() {
    if (_vimeoController == null) return;
    _vimeoController!.onPositionChanged = (pos) {
      if (_isDisposed || _mediaType != 'vimeo') return;
      if ((pos - _position).abs() >= 0.25) {
        _position = pos;
        positionNotifier.value = pos;
        onPositionChanged?.call(_position);
      }
    };
    _vimeoController!.onDurationChanged = (dur) {
      if (_isDisposed || _mediaType != 'vimeo') return;
      if (dur > 0 && dur != _duration) {
        _duration = dur;
        notifyListeners();
      }
    };
    _vimeoController!.onPlayingChanged = (playing) {
      if (_isDisposed || _mediaType != 'vimeo') return;
      if (!playing && _isFullscreenTransition && _wasPlayingBeforeFullscreen) {
        debugPrint('[UnifiedPlayerController] Vimeo spurious pause ignored during fullscreen transition');
        _vimeoController?.play();
        return;
      }
      if (_isPlaying != playing) {
        _isPlaying = playing;
        notifyListeners();
        onPlaybackStateChanged?.call(playing ? 'playing' : 'paused');
      }
    };
    _vimeoController!.onPlaybackEnded = () {
      if (_isDisposed || _mediaType != 'vimeo') return;
      onPlaybackEnded?.call();
    };
    _vimeoController!.onError = (err) {
      if (_isDisposed || _mediaType != 'vimeo') return;
      _errorMessage = err;
      _isPlaying = false;
      notifyListeners();
    };
    _vimeoController!.onQualitiesChanged = (qualities) {
      if (_isDisposed || _mediaType != 'vimeo') return;
      _availableQualities = qualities;
      if (qualities.length > 1) {
        _isDetectingQualities = false;
        _qualityDetectTimeoutTimer?.cancel();
      }
      notifyListeners();
      _applySavedQualityPreference();
    };
    _vimeoController!.onQualitySelectedChanged = (quality) {
      if (_isDisposed || _mediaType != 'vimeo') return;
      _selectedQuality = quality;
      notifyListeners();
    };
  }

  void _setupGoogleDriveListeners() {
    if (_googleDriveController == null) return;
    _googleDriveController!.onPositionChanged = (pos) {
      if (_isDisposed || _mediaType != 'google_drive') return;
      if ((pos - _position).abs() >= 0.25) {
        _position = pos;
        positionNotifier.value = pos;
        onPositionChanged?.call(_position);
      }
    };
    _googleDriveController!.onDurationChanged = (dur) {
      if (_isDisposed || _mediaType != 'google_drive') return;
      if (dur > 0 && dur != _duration) {
        _duration = dur;
        notifyListeners();
      }
    };
    _googleDriveController!.onPlayingChanged = (playing) {
      if (_isDisposed || _mediaType != 'google_drive') return;
      if (!playing && _isFullscreenTransition && _wasPlayingBeforeFullscreen) {
        debugPrint('[UnifiedPlayerController] Google Drive spurious pause ignored during fullscreen transition');
        _googleDriveController?.play();
        return;
      }
      if (_isPlaying != playing) {
        _isPlaying = playing;
        notifyListeners();
        onPlaybackStateChanged?.call(playing ? 'playing' : 'paused');
      }
    };
    _googleDriveController!.onPlaybackEnded = () {
      if (_isDisposed || _mediaType != 'google_drive') return;
      onPlaybackEnded?.call();
    };
    _googleDriveController!.onError = (err) {
      if (_isDisposed || _mediaType != 'google_drive') return;
      _errorMessage = err;
      _isPlaying = false;
      notifyListeners();
    };
    _googleDriveController!.onQualitiesChanged = (qualities) {
      if (_isDisposed || _mediaType != 'google_drive') return;
      _availableQualities = qualities;
      if (qualities.length > 1) {
        _isDetectingQualities = false;
        _qualityDetectTimeoutTimer?.cancel();
      }
      notifyListeners();
      _applySavedQualityPreference();
    };
    _googleDriveController!.onQualitySelectedChanged = (quality) {
      if (_isDisposed || _mediaType != 'google_drive') return;
      _selectedQuality = quality;
      notifyListeners();
    };
  }

  void _setupWebBrowserListeners() {
    if (_webBrowserController == null) return;
    _webBrowserController!.onPositionChanged = (pos) {
      if (_isDisposed || _mediaType != 'web_browser') return;
      if ((pos - _position).abs() >= 0.25) {
        _position = pos;
        positionNotifier.value = pos;
        onPositionChanged?.call(_position);
      }
    };
    _webBrowserController!.onDurationChanged = (dur) {
      if (_isDisposed || _mediaType != 'web_browser') return;
      if (dur > 0 && dur != _duration) {
        _duration = dur;
        notifyListeners();
      }
    };
    _webBrowserController!.onPlayingChanged = (playing) {
      if (_isDisposed || _mediaType != 'web_browser') return;
      if (!playing && _isFullscreenTransition && _wasPlayingBeforeFullscreen) {
        debugPrint('[UnifiedPlayerController] Web Browser spurious pause ignored during fullscreen transition');
        _webBrowserController?.play();
        return;
      }
      if (_isPlaying != playing) {
        _isPlaying = playing;
        notifyListeners();
        onPlaybackStateChanged?.call(playing ? 'playing' : 'paused');
      }
    };
    _webBrowserController!.onPlaybackEnded = () {
      if (_isDisposed || _mediaType != 'web_browser') return;
      onPlaybackEnded?.call();
    };
    _webBrowserController!.onError = (err) {
      if (_isDisposed || _mediaType != 'web_browser') return;
      _errorMessage = err;
      _isPlaying = false;
      notifyListeners();
    };
    _webBrowserController!.onQualitiesChanged = (qualities) {
      if (_isDisposed || _mediaType != 'web_browser') return;
      _availableQualities = qualities;
      if (qualities.length > 1) {
        _isDetectingQualities = false;
        _qualityDetectTimeoutTimer?.cancel();
      }
      notifyListeners();
      _applySavedQualityPreference();
    };
    _webBrowserController!.onQualitySelectedChanged = (quality) {
      if (_isDisposed || _mediaType != 'web_browser') return;
      _selectedQuality = quality;
      notifyListeners();
    };
    _webBrowserController!.onDirectStreamExtracted = (streamUrl) {
      if (_isDisposed || _mediaType != 'web_browser') return;
      debugPrint(
        '[UnifiedPlayerController] Upgraded web_browser to native direct_url player: $streamUrl',
      );
      loadMedia(
        'direct_url',
        streamUrl,
        autoPlay: true,
        startSeconds: _position,
      );
    };
  }

  void _startQualityDetectTimeout([Duration timeout = const Duration(seconds: 8)]) {
    _qualityDetectTimeoutTimer?.cancel();
    _qualityDetectTimeoutTimer = Timer(timeout, () {
      if (_isDisposed) return;
      if (_isDetectingQualities) {
        _isDetectingQualities = false;
        notifyListeners();
      }
    });
  }

  void _scheduleYoutubeQualityProbe() {
    _ytQualityPollTimer?.cancel();
    int attempts = 0;
    _ytQualityPollTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      if (_isDisposed || _mediaType != 'youtube') {
        timer.cancel();
        return;
      }
      attempts++;
      await _fetchYoutubeAvailableQualities();
      if (_availableQualities.length > 1 || attempts >= 8) {
        timer.cancel();
        if (_isDetectingQualities) {
          _isDetectingQualities = false;
          notifyListeners();
        }
      }
    });
  }

  /// Manually re-triggers resolution detection for the currently active video stream.
  Future<void> refreshAvailableQualities() async {
    if (_isDisposed || _mediaUrl.isEmpty) return;
    if (isLocalFile || isP2PStream) return;

    _isDetectingQualities = true;
    notifyListeners();
    _startQualityDetectTimeout(const Duration(seconds: 12));
    debugPrint('[UnifiedPlayerController] refreshAvailableQualities(type=$_mediaType, url=$_mediaUrl)');

    if (_mediaType == 'youtube') {
      await _fetchYoutubeAvailableQualities();
      if (_availableQualities.length > 1) {
        _isDetectingQualities = false;
        _qualityDetectTimeoutTimer?.cancel();
        notifyListeners();
      } else {
        _scheduleYoutubeQualityProbe();
      }
    } else if (_mediaType == 'direct_url' && isHlsStream && !kIsWeb) {
      final targetUrl = _hlsMasterUrl.isNotEmpty ? _hlsMasterUrl : _mediaUrl;
      await _probeHlsManifestQualities(targetUrl);
    } else if (_mediaType == 'dailymotion') {
      final dmId = DailymotionPlayerController.extractVideoId(_mediaUrl);
      if (dmId != null) {
        _dailymotionController ??= DailymotionPlayerController();
        _setupDailymotionListeners();
        await _dailymotionController!.loadUrl(
          _mediaUrl,
          autoPlay: _isPlaying,
          startSeconds: _position,
        );
      }
    } else if (_mediaType == 'vimeo') {
      final vId = VimeoPlayerController.extractVideoId(_mediaUrl);
      if (vId != null) {
        _vimeoController ??= VimeoPlayerController();
        _setupVimeoListeners();
        await _vimeoController!.loadUrl(
          _mediaUrl,
          autoPlay: _isPlaying,
          startSeconds: _position,
        );
      }
    } else if (_mediaType == 'bstation') {
      _bstationController ??= BstationPlayerController();
      _setupBstationListeners();
      await _bstationController!.loadUrl(
        _mediaUrl,
        autoPlay: _isPlaying,
        startSeconds: _position,
      );
    } else if (_mediaType == 'google_drive') {
      _googleDriveController ??= GoogleDrivePlayerController();
      _setupGoogleDriveListeners();
      await _googleDriveController!.loadUrl(
        _mediaUrl,
        autoPlay: _isPlaying,
        startSeconds: _position,
      );
    } else if (_mediaType == 'web_browser') {
      _webBrowserController ??= WebBrowserPlayerController();
      _setupWebBrowserListeners();
      await _webBrowserController!.loadUrl(
        _mediaUrl,
        autoPlay: _isPlaying,
        startSeconds: _position,
      );
    }
  }

  @visibleForTesting
  String get activeVariantStreamUrl => _activeVariantStreamUrl;

  @visibleForTesting
  void setAvailableQualitiesForTesting(
    List<VideoQuality> qualities, {
    VideoQuality? selected,
    bool isDetecting = false,
  }) {
    _availableQualities = List<VideoQuality>.from(qualities);
    if (isHlsStream) {
      _parsedHlsQualities = List<VideoQuality>.from(qualities);
    }
    _selectedQuality =
        selected ?? (_availableQualities.isNotEmpty ? _availableQualities.first : null);
    _isDetectingQualities = isDetecting;
    _hasAppliedSavedQualityForCurrentMedia = false;
    if (!isDetecting) {
      _qualityDetectTimeoutTimer?.cancel();
    }
    notifyListeners();
  }

  /// Loads media into player
  Future<void> loadMedia(
    String type,
    String url, {
    bool autoPlay = false,
    double startSeconds = 0.0,
  }) async {
    _ytQualityPollTimer?.cancel();
    _qualityDetectTimeoutTimer?.cancel();
    _errorMessage = null;
    _isBuffering = false;
    _mediaType = type;
    _mediaUrl = url;
    final hasMedia = url.isNotEmpty && type != 'screenshare';
    if (hasMediaNotifier.value != hasMedia) {
      hasMediaNotifier.value = hasMedia;
    }
    _position = startSeconds;
    positionNotifier.value = startSeconds;
    _playbackSpeed = 1.0;
    _hlsMasterUrl = '';
    _activeVariantStreamUrl = '';
    _pendingQualitySeekSeconds = null;
    _isSwitchingQuality = false;
    _hasAppliedSavedQualityForCurrentMedia = false;
    _parsedHlsQualities = [];
    _isDetectingQualities = false;
    _availableQualities = [const VideoQuality.auto()];
    _selectedQuality = _availableQualities.first;

    if (url.isEmpty) {
      _isPlaying = false;
      notifyListeners();
      return;
    }

    if (type == 'screenshare') {
      _isPlaying = false;
      await _bstationController?.pause();
      await _dailymotionController?.pause();
      await _vimeoController?.pause();
      await _googleDriveController?.pause();
      await _webBrowserController?.pause();
      if (_ytController != null) {
        try {
          await _ytController!.pauseVideo();
        } catch (_) {}
      }
      if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.pause();
      } else if (_mkPlayer != null) {
        unawaited(_mkPlayer!.stop());
      }
      notifyListeners();
      return;
    }

    if (type == 'youtube') {
      _youtubeQuality = '';
      _availableQualities = [
        const VideoQuality.auto(
          label: 'Auto (Otomatis YouTube)',
          mode: QualityControlMode.embeddedUi,
        ),
      ];
      _selectedQuality = _availableQualities.first;
      _isDetectingQualities = true;
      _startQualityDetectTimeout(const Duration(seconds: 12));

      // Pause direct video player, Bstation, Dailymotion, Vimeo, Google Drive, and Web Browser player if active
      await _bstationController?.pause();
      await _dailymotionController?.pause();
      await _vimeoController?.pause();
      await _googleDriveController?.pause();
      await _webBrowserController?.pause();
      if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.pause();
      } else if (_mkPlayer != null) {
        unawaited(_mkPlayer!.stop());
      }

      final videoId = extractYoutubeId(url) ?? url;
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

        if (_isFullscreen) {
          _ytController!.enterFullScreen(lock: false);
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
        _scheduleYoutubeQualityProbe();
      } catch (e) {
        debugPrint('[UnifiedPlayerController] YouTube load error: $e');
        _errorMessage = 'Gagal memuat YouTube video: $e';
        _isPlaying = false;
        _isDetectingQualities = false;
      }
      notifyListeners();
      return;
    }

    if (type == 'bstation') {
      _availableQualities = [
        const VideoQuality.auto(
          label: 'Auto (Otomatis Bstation)',
          mode: QualityControlMode.webviewBridge,
        ),
      ];
      _selectedQuality = _availableQualities.first;
      _isDetectingQualities = true;
      _startQualityDetectTimeout(const Duration(seconds: 10));

      // Pause YouTube, Dailymotion, Vimeo, Google Drive, Web Browser, and direct video player if active
      if (_ytController != null) {
        try {
          await _ytController!.pauseVideo();
        } catch (_) {}
      }
      await _dailymotionController?.pause();
      await _vimeoController?.pause();
      await _googleDriveController?.pause();
      await _webBrowserController?.pause();
      if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.pause();
      } else if (_mkPlayer != null) {
        unawaited(_mkPlayer!.stop());
      }

      try {
        _bstationController ??= BstationPlayerController();
        _setupBstationListeners();
        await _bstationController!.loadUrl(
          url,
          autoPlay: autoPlay,
          startSeconds: startSeconds,
        );
        if (_bstationController!.availableQualities.isNotEmpty) {
          _availableQualities = _bstationController!.availableQualities;
          _selectedQuality =
              _bstationController!.selectedQuality ?? _availableQualities.first;
          if (_availableQualities.length > 1) {
            _isDetectingQualities = false;
            _qualityDetectTimeoutTimer?.cancel();
          }
        }
        _isPlaying = autoPlay;
        if (!_isMuted) {
          await _bstationController!.setVolume(_volume);
        }
      } catch (e) {
        debugPrint('[UnifiedPlayerController] Bstation load error: $e');
        _errorMessage = 'Gagal memuat Bstation video: $e';
        _isPlaying = false;
        _isDetectingQualities = false;
      }
      notifyListeners();
      return;
    }

    if (type == 'dailymotion') {
      _availableQualities = [
        const VideoQuality.auto(
          label: 'Auto (Otomatis Dailymotion)',
          mode: QualityControlMode.webviewBridge,
        ),
      ];
      _selectedQuality = _availableQualities.first;
      _isDetectingQualities = true;
      _startQualityDetectTimeout(const Duration(seconds: 12));

      // Pause YouTube, Bstation, Vimeo, Google Drive, Web Browser, and direct video player if active
      if (_ytController != null) {
        try {
          await _ytController!.pauseVideo();
        } catch (_) {}
      }
      await _bstationController?.pause();
      await _vimeoController?.pause();
      await _googleDriveController?.pause();
      await _webBrowserController?.pause();
      if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.pause();
      } else if (_mkPlayer != null) {
        unawaited(_mkPlayer!.stop());
      }

      try {
        _dailymotionController ??= DailymotionPlayerController();
        _setupDailymotionListeners();
        await _dailymotionController!.loadUrl(
          url,
          autoPlay: autoPlay,
          startSeconds: startSeconds,
        );
        if (_dailymotionController!.availableQualities.isNotEmpty) {
          _availableQualities = _dailymotionController!.availableQualities;
          _selectedQuality =
              _dailymotionController!.selectedQuality ?? _availableQualities.first;
          if (_availableQualities.length > 1) {
            _isDetectingQualities = false;
            _qualityDetectTimeoutTimer?.cancel();
          }
        }
        _isPlaying = autoPlay;
        if (!_isMuted) {
          await _dailymotionController!.setVolume(_volume);
        }
      } catch (e) {
        debugPrint('[UnifiedPlayerController] Dailymotion load error: $e');
        _errorMessage = 'Gagal memuat Dailymotion video: $e';
        _isPlaying = false;
        _isDetectingQualities = false;
      }
      notifyListeners();
      return;
    }

    if (type == 'vimeo') {
      _availableQualities = [
        const VideoQuality.auto(
          label: 'Auto (Otomatis Vimeo)',
          mode: QualityControlMode.webviewBridge,
        ),
      ];
      _selectedQuality = _availableQualities.first;
      _isDetectingQualities = true;
      _startQualityDetectTimeout(const Duration(seconds: 12));

      // Pause YouTube, Bstation, Dailymotion, Google Drive, Web Browser, and direct video player if active
      if (_ytController != null) {
        try {
          await _ytController!.pauseVideo();
        } catch (_) {}
      }
      await _bstationController?.pause();
      await _dailymotionController?.pause();
      await _googleDriveController?.pause();
      await _webBrowserController?.pause();
      if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.pause();
      } else if (_mkPlayer != null) {
        unawaited(_mkPlayer!.stop());
      }

      try {
        _vimeoController ??= VimeoPlayerController();
        _setupVimeoListeners();
        await _vimeoController!.loadUrl(
          url,
          autoPlay: autoPlay,
          startSeconds: startSeconds,
        );
        if (_vimeoController!.availableQualities.isNotEmpty) {
          _availableQualities = _vimeoController!.availableQualities;
          _selectedQuality =
              _vimeoController!.selectedQuality ?? _availableQualities.first;
          if (_availableQualities.length > 1) {
            _isDetectingQualities = false;
            _qualityDetectTimeoutTimer?.cancel();
          }
        }
        _isPlaying = autoPlay;
        if (!_isMuted) {
          await _vimeoController!.setVolume(_volume);
        }
      } catch (e) {
        debugPrint('[UnifiedPlayerController] Vimeo load error: $e');
        _errorMessage = 'Gagal memuat Vimeo video: $e';
        _isPlaying = false;
        _isDetectingQualities = false;
      }
      notifyListeners();
      return;
    }

    if (type == 'google_drive') {
      _availableQualities = [
        const VideoQuality.auto(
          label: 'Auto (Otomatis Google Drive)',
          mode: QualityControlMode.webviewBridge,
        ),
      ];
      _selectedQuality = _availableQualities.first;
      _isDetectingQualities = true;
      _startQualityDetectTimeout(const Duration(seconds: 10));

      // Pause YouTube, Bstation, Dailymotion, Vimeo, Web Browser, and direct video player if active
      if (_ytController != null) {
        try {
          await _ytController!.pauseVideo();
        } catch (_) {}
      }
      await _bstationController?.pause();
      await _dailymotionController?.pause();
      await _vimeoController?.pause();
      await _webBrowserController?.pause();
      if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.pause();
      } else if (_mkPlayer != null) {
        unawaited(_mkPlayer!.stop());
      }

      try {
        _googleDriveController ??= GoogleDrivePlayerController();
        _setupGoogleDriveListeners();
        await _googleDriveController!.loadUrl(
          url,
          autoPlay: autoPlay,
          startSeconds: startSeconds,
        );
        if (_googleDriveController!.availableQualities.isNotEmpty) {
          _availableQualities = _googleDriveController!.availableQualities;
          _selectedQuality =
              _googleDriveController!.selectedQuality ?? _availableQualities.first;
          if (_availableQualities.length > 1) {
            _isDetectingQualities = false;
            _qualityDetectTimeoutTimer?.cancel();
          }
        }
        _isPlaying = autoPlay;
        if (!_isMuted) {
          await _googleDriveController!.setVolume(_volume);
        }
      } catch (e) {
        debugPrint('[UnifiedPlayerController] Google Drive load error: $e');
        _errorMessage = 'Gagal memuat Google Drive video: $e';
        _isPlaying = false;
        _isDetectingQualities = false;
      }
      notifyListeners();
      return;
    }

    if (type == 'web_browser') {
      _availableQualities = [
        const VideoQuality.auto(
          label: 'Auto (Otomatis Web)',
          mode: QualityControlMode.webviewBridge,
        ),
      ];
      _selectedQuality = _availableQualities.first;
      _isDetectingQualities = true;
      _startQualityDetectTimeout(const Duration(seconds: 10));

      // Pause YouTube, Bstation, Dailymotion, Vimeo, Google Drive, and direct video player if active
      if (_ytController != null) {
        try {
          await _ytController!.pauseVideo();
        } catch (_) {}
      }
      await _bstationController?.pause();
      await _dailymotionController?.pause();
      await _vimeoController?.pause();
      await _googleDriveController?.pause();
      if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.pause();
      } else if (_mkPlayer != null) {
        unawaited(_mkPlayer!.stop());
      }

      try {
        _webBrowserController ??= WebBrowserPlayerController();
        _setupWebBrowserListeners();
        await _webBrowserController!.loadUrl(
          url,
          autoPlay: autoPlay,
          startSeconds: startSeconds,
        );
        if (_webBrowserController!.availableQualities.isNotEmpty) {
          _availableQualities = _webBrowserController!.availableQualities;
          _selectedQuality =
              _webBrowserController!.selectedQuality ?? _availableQualities.first;
          if (_availableQualities.length > 1) {
            _isDetectingQualities = false;
            _qualityDetectTimeoutTimer?.cancel();
          }
        }
        _isPlaying = autoPlay;
        if (!_isMuted) {
          await _webBrowserController!.setVolume(_volume);
        }
      } catch (e) {
        debugPrint('[UnifiedPlayerController] Web Browser load error: $e');
        _errorMessage = 'Gagal memuat video Web Browser: $e';
        _isPlaying = false;
        _isDetectingQualities = false;
      }
      notifyListeners();
      return;
    }

    // Direct URL: pause YouTube, Bstation, Dailymotion, Vimeo, Google Drive, and Web Browser player if active
    final bool isHls = !isLocalFile && !isP2PStream && HlsManifestParser.isHlsUrl(url);
    if (isHls) {
      _hlsMasterUrl = url;
      _availableQualities = [
        const VideoQuality.auto(mode: QualityControlMode.directTrack),
      ];
      _selectedQuality = _availableQualities.first;
      _isDetectingQualities = true;
      _startQualityDetectTimeout(const Duration(seconds: 8));
      if (!kIsWeb) {
        unawaited(_probeHlsManifestQualities(url));
      }
    } else {
      _availableQualities = [
        VideoQuality.fixed(label: 'Kualitas Asli (Direct)'),
      ];
      _selectedQuality = _availableQualities.first;
      _isDetectingQualities = false;
    }

    await _bstationController?.pause();
    await _dailymotionController?.pause();
    await _vimeoController?.pause();
    await _googleDriveController?.pause();
    await _webBrowserController?.pause();
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
        _bindMediaKitListeners();
        try {
          final dynamic nativePlatform = _mkPlayer!.platform;
          await nativePlatform.setProperty('tls-verify', 'no');
          await nativePlatform.setProperty(
            'demuxer-lavf-o',
            'allowed_extensions=ALL,allowed_segment_extensions=ALL',
          );
          await nativePlatform.setProperty(
            'user-agent',
            'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
          );
        } catch (_) {}
        await _mkPlayer!.setVolume(_isMuted ? 0 : _volume * 100);
        final startDur = startSeconds > 0
            ? Duration(milliseconds: (startSeconds * 1000).round())
            : null;
        if (startSeconds > 0) {
          _pendingQualitySeekSeconds = startSeconds;
        }
        await _mkPlayer!.open(Media(url, start: startDur), play: autoPlay);
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
        _isDetectingQualities = false;
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
      } else if (_mediaType == 'vimeo') {
        await _vimeoController?.play();
      } else if (_mediaType == 'google_drive') {
        await _googleDriveController?.play();
      } else if (_mediaType == 'web_browser') {
        await _webBrowserController?.play();
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
    _fullscreenTransitionTimer?.cancel();
    _fullscreenTransitionTimer = null;
    _isFullscreenTransition = false;
    _wasPlayingBeforeFullscreen = false;
    _bstationController?.setFullscreenTransition(false);
    _dailymotionController?.setFullscreenTransition(false);
    _vimeoController?.setFullscreenTransition(false);
    _googleDriveController?.setFullscreenTransition(false);
    _webBrowserController?.setFullscreenTransition(false);

    _isPlaying = false;
    notifyListeners();

    try {
      if (_mediaType == 'youtube') {
        await _ytController?.pauseVideo();
      } else if (_mediaType == 'bstation') {
        await _bstationController?.pause();
      } else if (_mediaType == 'dailymotion') {
        await _dailymotionController?.pause();
      } else if (_mediaType == 'vimeo') {
        await _vimeoController?.pause();
      } else if (_mediaType == 'google_drive') {
        await _googleDriveController?.pause();
      } else if (_mediaType == 'web_browser') {
        await _webBrowserController?.pause();
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
    positionNotifier.value = _position;
    notifyListeners();

    try {
      if (_mediaType == 'youtube') {
        await _ytController?.seekTo(seconds: seconds, allowSeekAhead: true);
      } else if (_mediaType == 'bstation') {
        await _bstationController?.seekTo(seconds);
      } else if (_mediaType == 'dailymotion') {
        await _dailymotionController?.seekTo(seconds);
      } else if (_mediaType == 'vimeo') {
        await _vimeoController?.seekTo(seconds);
      } else if (_mediaType == 'google_drive') {
        await _googleDriveController?.seekTo(seconds);
      } else if (_mediaType == 'web_browser') {
        await _webBrowserController?.seekTo(seconds);
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
      } else if (_mediaType == 'vimeo') {
        await _vimeoController?.setPlaybackSpeed(speed);
      } else if (_mediaType == 'google_drive') {
        await _googleDriveController?.setPlaybackSpeed(speed);
      } else if (_mediaType == 'web_browser') {
        await _webBrowserController?.setPlaybackSpeed(speed);
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
      } else if (_mediaType == 'vimeo') {
        await _vimeoController?.setVolume(_volume);
      } else if (_mediaType == 'google_drive') {
        await _googleDriveController?.setVolume(_volume);
      } else if (_mediaType == 'web_browser') {
        await _webBrowserController?.setVolume(_volume);
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
        } else if (_mediaType == 'vimeo') {
          await _vimeoController?.toggleMute();
        } else if (_mediaType == 'google_drive') {
          await _googleDriveController?.mute();
        } else if (_mediaType == 'web_browser') {
          await _webBrowserController?.toggleMute();
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
      } else if (_mediaType == 'vimeo') {
        await _vimeoController?.setVolume(_volume);
      } else if (_mediaType == 'google_drive') {
        await _googleDriveController?.unmute();
        await _googleDriveController?.setVolume(_volume);
      } else if (_mediaType == 'web_browser') {
        await _webBrowserController?.setVolume(_volume);
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
    _hasAppliedSavedQualityForCurrentMedia = true;
    final bool wasPlayingVariant = _activeVariantStreamUrl.isNotEmpty;
    if (_mediaType == 'direct_url') {
      if (quality.isAuto) {
        _activeVariantStreamUrl = '';
      } else if (quality.streamUrl != null && quality.streamUrl!.isNotEmpty) {
        _activeVariantStreamUrl = quality.streamUrl!;
      }
    }
    _selectedQuality = quality;
    notifyListeners();
    unawaited(_saveUserQualityPreference(quality));

    try {
      if (_mediaType == 'youtube') {
        if (_ytController != null) {
          final qCode = quality.isAuto ? 'default' : quality.id;
          final targetHeight = quality.height ?? 0;
          try {
            final res = await _ytController!.webViewController
                .runJavaScriptReturningResult('''
              (function() {
                var results = [];
                var isAuto = ${quality.isAuto ? 'true' : 'false'};
                var qCode = "$qCode";
                var targetHeight = $targetHeight;

                function applyToPlayer(p, label) {
                  if (!p) return;
                  try {
                    if (isAuto) {
                      if (typeof p.setPlaybackQualityRange === 'function') {
                        p.setPlaybackQualityRange("tiny", "highres");
                        results.push(label + ":range(tiny,highres)");
                      }
                      if (typeof p.setPlaybackQuality === 'function') {
                        p.setPlaybackQuality("default");
                        results.push(label + ":quality(default)");
                      }
                    } else {
                      if (typeof p.setPlaybackQualityRange === 'function') {
                        p.setPlaybackQualityRange(qCode, qCode);
                        results.push(label + ":range(" + qCode + ")");
                      }
                      if (typeof p.setPlaybackQuality === 'function') {
                        p.setPlaybackQuality(qCode);
                        results.push(label + ":quality(" + qCode + ")");
                      }
                    }
                  } catch (err) {
                    results.push(label + ":err(" + err + ")");
                  }
                }

                // 1. Target internal #movie_player inside same-origin YouTube embed iframe
                try {
                  var iframes = document.getElementsByTagName('iframe');
                  for (var i = 0; i < iframes.length; i++) {
                    var cw = iframes[i].contentWindow;
                    var cd = iframes[i].contentDocument || (cw && cw.document);
                    if (cw && targetHeight > 0 && !isAuto) {
                      try {
                        var now = Date.now();
                        var qPayload = JSON.stringify({
                          data: JSON.stringify({ quality: targetHeight, previousQuality: targetHeight }),
                          expiration: now + 2592000000,
                          creation: now
                        });
                        cw.localStorage.setItem('yt-player-quality', qPayload);
                        cw.sessionStorage.setItem('yt-player-quality', qPayload);
                      } catch (_) {}
                    }
                    if (cd) {
                      var mp = cd.getElementById('movie_player') || cd.querySelector('.html5-video-player');
                      if (mp) {
                        applyToPlayer(mp, 'movie_player');
                        if (typeof mp.getPlaybackQuality === 'function') {
                          results.push('mpNow:' + mp.getPlaybackQuality());
                        }
                      }
                    }
                  }
                } catch (e) {
                  results.push('iframeErr:' + e);
                }

                // 2. Also call outer YT.Player wrapper
                if (typeof player !== 'undefined' && player) {
                  applyToPlayer(player, 'outer_player');
                }
                return results.join(',');
              })();
            ''');
            debugPrint(
              '[UnifiedPlayerController] YouTube setVideoQuality($qCode) -> $res',
            );
          } catch (e) {
            debugPrint(
              '[UnifiedPlayerController] YouTube setVideoQuality JS error: $e',
            );
          }
        }
      } else if (_mediaType == 'bstation') {
        await _bstationController?.setQuality(quality.id);
      } else if (_mediaType == 'dailymotion') {
        await _dailymotionController?.setQuality(quality.id);
      } else if (_mediaType == 'vimeo') {
        await _vimeoController?.setQuality(quality.id);
      } else if (_mediaType == 'google_drive') {
        await _googleDriveController?.setQuality(quality.id);
      } else if (_mediaType == 'web_browser') {
        await _webBrowserController?.setQuality(quality.id);
      } else if (kIsWeb && _webVideoAdapter != null) {
        await _webVideoAdapter?.setQuality(quality.id);
      } else if (_mkPlayer != null) {
        if (quality.isAuto) {
          final masterTarget = _hlsMasterUrl.isNotEmpty ? _hlsMasterUrl : _mediaUrl;
          debugPrint(
            '[UnifiedPlayerController] Direct/HLS setVideoQuality(auto) -> master=$masterTarget',
          );
          if (masterTarget.isNotEmpty &&
              (wasPlayingVariant || (_hlsMasterUrl.isNotEmpty && _mediaUrl != _hlsMasterUrl))) {
            final resumePos = _position;
            final wasPlaying = _isPlaying;
            final resumeDur = resumePos > 0
                ? Duration(milliseconds: (resumePos * 1000).round())
                : null;
            _isSwitchingQuality = resumePos > 0;
            _pendingQualitySeekSeconds = resumePos > 0 ? resumePos : null;
            await _mkPlayer!.open(
              Media(masterTarget, start: resumeDur),
              play: wasPlaying,
            );
          }
          await _mkPlayer!.setVideoTrack(VideoTrack.auto());
        } else if (quality.streamUrl != null && quality.streamUrl!.isNotEmpty) {
          debugPrint(
            '[UnifiedPlayerController] Direct/HLS setVideoQuality(${quality.id}) -> variantUrl=${quality.streamUrl}',
          );
          final resumePos = _position;
          final wasPlaying = _isPlaying;
          final resumeDur = resumePos > 0
              ? Duration(milliseconds: (resumePos * 1000).round())
              : null;
          _isSwitchingQuality = resumePos > 0;
          _pendingQualitySeekSeconds = resumePos > 0 ? resumePos : null;
          await _mkPlayer!.open(
            Media(quality.streamUrl!, start: resumeDur),
            play: wasPlaying,
          );
        } else if (quality.rawTrack is VideoTrack && !wasPlayingVariant) {
          debugPrint(
            '[UnifiedPlayerController] Direct/HLS setVideoQuality(${quality.id}) -> rawTrack=${(quality.rawTrack as VideoTrack).id}',
          );
          await _mkPlayer!.setVideoTrack(quality.rawTrack as VideoTrack);
        } else {
          final validTracks = _mkPlayer!.state.tracks.video
              .where((t) => t.id != 'no' && t.id != 'auto')
              .toList();
          VideoTrack? matchedTrack;
          for (final t in validTracks) {
            if (t.id == quality.id) {
              matchedTrack = t;
              break;
            }
            final normH = VideoQuality.normalizeResolutionHeight(
              width: t.w,
              height: t.h,
            );
            if (normH != null && quality.height != null && normH == quality.height) {
              matchedTrack = t;
              break;
            }
            if (t.bitrate != null &&
                quality.bitrate != null &&
                t.bitrate! > 0 &&
                (t.bitrate! - quality.bitrate!).abs() < 50000) {
              matchedTrack = t;
              break;
            }
          }
          if (matchedTrack != null) {
            debugPrint(
              '[UnifiedPlayerController] Direct/HLS setVideoQuality(${quality.id}) -> matchedTrack=${matchedTrack.id}',
            );
            await _mkPlayer!.setVideoTrack(matchedTrack);
          } else {
            await _mkPlayer!.setVideoTrack(VideoTrack.auto());
          }
        }
      }
    } catch (e) {
      debugPrint('[UnifiedPlayerController] setVideoQuality error: $e');
    }
  }

  void _updateYoutubeQuality(String? quality) {
    debugPrint('[UnifiedPlayerController] YouTube playbackQuality changed to: $quality');
    _youtubeQuality = quality ?? '';
    notifyListeners();
    if (_availableQualities.length <= 1) {
      _fetchYoutubeAvailableQualities();
    }
  }

  Future<void> _fetchYoutubeAvailableQualities() async {
    if (_isDisposed || _mediaType != 'youtube' || _ytController == null) return;
    try {
      final raw = await _ytController!.webViewController.runJavaScriptReturningResult('''
        (function() {
          try {
            var iframes = document.getElementsByTagName('iframe');
            for (var i = 0; i < iframes.length; i++) {
              var cd = iframes[i].contentDocument || (iframes[i].contentWindow && iframes[i].contentWindow.document);
              if (cd) {
                var mp = cd.getElementById('movie_player') || cd.querySelector('.html5-video-player');
                if (mp && typeof mp.getAvailableQualityLevels === 'function') {
                  var l = mp.getAvailableQualityLevels();
                  if (l && l.length > 0) return l;
                }
              }
            }
          } catch (_) {}
          if (typeof player !== 'undefined' && player && typeof player.getAvailableQualityLevels === 'function') {
            return player.getAvailableQualityLevels();
          }
          return [];
        })();
      ''');
      List<dynamic>? levels;
      if (raw is List) {
        levels = raw;
      } else if (raw is String &&
          raw.isNotEmpty &&
          raw != 'null' &&
          raw != 'undefined') {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            levels = decoded;
          } else if (decoded is String) {
            final inner = jsonDecode(decoded);
            if (inner is List) levels = inner;
          }
        } catch (_) {
          final cleaned = raw.replaceAll(RegExp(r'[\[\]"\s]'), '');
          if (cleaned.isNotEmpty) {
            levels = cleaned.split(',');
          }
        }
      }
      if (levels != null && levels.isNotEmpty) {
        final List<VideoQuality> list = [
          const VideoQuality.auto(
            label: 'Auto (Otomatis YouTube)',
            mode: QualityControlMode.webviewBridge,
          ),
        ];
        final Set<String> seen = {'auto'};
        for (final item in levels) {
          final code = item.toString().trim();
          if (code.isEmpty || code == 'auto' || seen.contains(code)) continue;
          final q = VideoQuality.youtube(code);
          if (q.height != null && q.height! > 0) {
            seen.add(code);
            list.add(q);
          }
        }
        if (list.length > 1) {
          list.sort((a, b) {
            if (a.isAuto) return -1;
            if (b.isAuto) return 1;
            return (b.height ?? 0).compareTo(a.height ?? 0);
          });
          _isDetectingQualities = false;
          _qualityDetectTimeoutTimer?.cancel();
          _ytQualityPollTimer?.cancel();
          _availableQualities = list;
          if (_selectedQuality == null ||
              !_availableQualities.any((q) => q.id == _selectedQuality!.id)) {
            _selectedQuality = _availableQualities.first;
          }
          notifyListeners();
          _applySavedQualityPreference();
        }
      }
    } catch (_) {}
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
    if (_hasAppliedSavedQualityForCurrentMedia) return;
    if (_availableQualities.length <= 1) return;
    if (!supportsQualitySelection) return;
    _hasAppliedSavedQualityForCurrentMedia = true;

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

  void _beginFullscreenTransition() {
    _fullscreenTransitionTimer?.cancel();
    _fullscreenTransitionTimer = null;
    if (_isDisposed || !_isPlaying) {
      _isFullscreenTransition = false;
      _wasPlayingBeforeFullscreen = false;
      _bstationController?.setFullscreenTransition(false);
      _dailymotionController?.setFullscreenTransition(false);
      _vimeoController?.setFullscreenTransition(false);
      _webBrowserController?.setFullscreenTransition(false);
      return;
    }
    _isFullscreenTransition = true;
    _wasPlayingBeforeFullscreen = true;
    _bstationController?.setFullscreenTransition(true);
    _dailymotionController?.setFullscreenTransition(true);
    _vimeoController?.setFullscreenTransition(true);
    _webBrowserController?.setFullscreenTransition(true);

    _fullscreenTransitionTimer = Timer(const Duration(milliseconds: 1500), () {
      _endFullscreenTransition();
    });
  }

  void _endFullscreenTransition() {
    _fullscreenTransitionTimer?.cancel();
    _fullscreenTransitionTimer = null;
    _isFullscreenTransition = false;
    _bstationController?.setFullscreenTransition(false);
    _dailymotionController?.setFullscreenTransition(false);
    _vimeoController?.setFullscreenTransition(false);
    _webBrowserController?.setFullscreenTransition(false);

    // If it was playing before entering/exiting fullscreen, ensure playback continues seamlessly
    if (!_isDisposed && _wasPlayingBeforeFullscreen && !_isPlaying) {
      debugPrint('[UnifiedPlayerController] Auto-restoring playback after fullscreen transition');
      play();
    }
  }

  Future<void> enterFullscreen() async {
    if (_isFullscreen) return;
    _beginFullscreenTransition();
    _isFullscreen = true;
    if (_mediaType == 'youtube' && _ytController != null && !_ytController!.value.fullScreenOption.enabled) {
      _ytController!.enterFullScreen(lock: false);
    }
    notifyListeners();

    await FullscreenHelper.enterFullscreen();
  }

  Future<void> exitFullscreen() async {
    if (!_isFullscreen) return;
    _beginFullscreenTransition();
    _isFullscreen = false;
    if (_mediaType == 'youtube' && _ytController != null && _ytController!.value.fullScreenOption.enabled) {
      _ytController!.exitFullScreen(lock: false);
    }
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
    hasMediaNotifier.dispose();
    positionNotifier.dispose();
    _ytQualityPollTimer?.cancel();
    _qualityDetectTimeoutTimer?.cancel();
    _fullscreenTransitionTimer?.cancel();
    _fullscreenTransitionTimer = null;
    _isFullscreenTransition = false;
    if (_isFullscreen) {
      _isFullscreen = false;
      FullscreenHelper.exitFullscreen();
    }
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _ytController?.close();
    _bstationController?.dispose();
    _dailymotionController?.dispose();
    _vimeoController?.dispose();
    _googleDriveController?.dispose();
    _webBrowserController?.dispose();
    _webVideoAdapter?.dispose();
    _mkPlayer?.dispose();
    super.dispose();
  }
}
