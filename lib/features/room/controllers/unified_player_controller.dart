import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../../../core/utils/fullscreen/fullscreen_helper.dart';
import '../models/video_quality.dart';
import 'web_video_adapter/web_video_adapter.dart';

/// Metadata for Twitch streams, VODs, or clips
class TwitchMedia {
  final String type; // 'channel', 'video', 'clip'
  final String id;

  const TwitchMedia({required this.type, required this.id});

  bool get isChannel => type == 'channel';
  bool get isVideo => type == 'video';
  bool get isClip => type == 'clip';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TwitchMedia &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          id == other.id;

  @override
  int get hashCode => type.hashCode ^ id.hashCode;

  @override
  String toString() => 'TwitchMedia(type: $type, id: $id)';
}

/// Normalized result of detecting media platform, URLs, and IDs
class DetectedMedia {
  final String mediaType; // 'youtube', 'twitch', 'vimeo', 'google_drive', 'dailymotion', 'bstation', 'direct_url'
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

  bool get isYouTube => mediaType == 'youtube';
  bool get isTwitch => mediaType == 'twitch';
  bool get isVimeo => mediaType == 'vimeo';
  bool get isGoogleDrive => mediaType == 'google_drive';
  bool get isDailymotion => mediaType == 'dailymotion';
  bool get isBstation => mediaType == 'bstation';
  bool get isDirectUrl => mediaType == 'direct_url';
}

class UnifiedPlayerController extends ChangeNotifier {
  String _mediaType = 'direct_url'; // 'direct_url', 'youtube', 'twitch', 'vimeo'
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
  String? _detectedYtQuality;

  // HTML5 Web Video Player (Web direct URL)
  WebVideoAdapter? _webVideoAdapter;

  // MediaKit Player & VideoController (Native desktop / mobile direct URL)
  Player? _mkPlayer;
  VideoController? _mkVideoController;
  final List<StreamSubscription> _subscriptions = [];

  // YouTube Player (Universal iframe)
  YoutubePlayerController? _ytController;
  final List<StreamSubscription> _ytSubscriptions = [];

  // Callbacks for Twitch / Vimeo Embed Player
  void Function(String action, dynamic argument)? onEmbedPlayerCommand;

  // Callbacks for SyncController
  void Function(double positionSeconds)? onPositionChanged;
  void Function(String state)? onPlaybackStateChanged;
  void Function()? onPlaybackEnded;

  /// Called by embed player widget (Twitch/Vimeo) to update state
  void updateEmbedPlaybackState({
    required bool isPlaying,
    double? position,
    double? duration,
    String? error,
  }) {
    if (_isDisposed) return;
    if (error != null) {
      _errorMessage = error;
      _isPlaying = false;
      notifyListeners();
      return;
    }
    _isPlaying = isPlaying;
    if (position != null) {
      _position = position;
      onPositionChanged?.call(_position);
    }
    if (duration != null && duration > 0 && duration != _duration) {
      _duration = duration;
    }
    notifyListeners();
    onPlaybackStateChanged?.call(isPlaying ? 'playing' : 'paused');
  }

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
  Widget? get webVideoWidget => _webVideoAdapter?.buildVideoWidget();

  List<VideoQuality> get availableQualities =>
      List.unmodifiable(_availableQualities);
  VideoQuality? get selectedQuality => _selectedQuality;
  bool get hasMultipleQualities => _availableQualities.length > 1;

  bool get supportsQualitySelection {
    return _mediaType == 'direct_url' ||
        _mediaType == 'youtube' ||
        _mediaType == 'vimeo' ||
        _mediaType == 'dailymotion';
  }

  String get currentQualityLabel {
    if (_selectedQuality != null && !_selectedQuality!.isAuto) {
      return _selectedQuality!.shortLabel;
    }
    if (_mediaType == 'youtube' && _detectedYtQuality != null) {
      return 'Auto (${_mapYtQualityLabel(_detectedYtQuality!)})';
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

  static String _mapYtQualityLabel(String qId) {
    switch (qId) {
      case 'hd1080':
        return '1080p';
      case 'hd720':
        return '720p';
      case 'large':
        return '480p';
      case 'medium':
        return '360p';
      case 'small':
        return '240p';
      case 'tiny':
        return '144p';
      case 'highres':
        return '4K';
      default:
        return qId;
    }
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

  /// Extracts Twitch media information (channel, video, or clip) from URL
  static TwitchMedia? extractTwitchMedia(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    try {
      // 1. Clips: clips.twitch.tv/{clipId} or twitch.tv/{channel}/clip/{clipId}
      final clipMatch1 = RegExp(r'clips\.twitch\.tv\/([a-zA-Z0-9_-]+)', caseSensitive: false).firstMatch(trimmed);
      if (clipMatch1 != null) {
        return TwitchMedia(type: 'clip', id: clipMatch1.group(1)!);
      }
      final clipMatch2 = RegExp(r'twitch\.tv\/[a-zA-Z0-9_]+\/clip\/([a-zA-Z0-9_-]+)', caseSensitive: false).firstMatch(trimmed);
      if (clipMatch2 != null) {
        return TwitchMedia(type: 'clip', id: clipMatch2.group(1)!);
      }

      // 2. Videos / VODs: twitch.tv/videos/{videoId}
      final videoMatch = RegExp(r'twitch\.tv\/videos\/(\d+)', caseSensitive: false).firstMatch(trimmed);
      if (videoMatch != null) {
        return TwitchMedia(type: 'video', id: videoMatch.group(1)!);
      }

      // 3. Channels: twitch.tv/{channel}
      final channelMatch = RegExp(r'(?:https?:\/\/)?(?:www\.|m\.)?twitch\.tv\/([a-zA-Z0-9_]{3,25})(?:\/|\?|$)', caseSensitive: false).firstMatch(trimmed);
      if (channelMatch != null) {
        final channel = channelMatch.group(1)!.toLowerCase();
        const reserved = {
          'directory', 'videos', 'p', 'downloads', 'jobs', 'turbo',
          'settings', 'friends', 'messages', 'search', 'subscriptions',
          'wallet', 'drops', 'inventory', 'popout'
        };
        if (!reserved.contains(channel)) {
          return TwitchMedia(type: 'channel', id: channel);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Extracts Vimeo video ID from URL or raw digits
  static String? extractVimeoVideoId(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    if (RegExp(r'^\d{5,12}$').hasMatch(trimmed)) {
      return trimmed;
    }

    try {
      final regExp = RegExp(
        r'(?:vimeo\.com\/(?:channels\/(?:\w+\/)?|groups\/[^\/]*\/videos\/|video\/|)|player\.vimeo\.com\/video\/)(\d+)',
        caseSensitive: false,
      );
      final match = regExp.firstMatch(trimmed);
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// Extracts Google Drive file ID from URL or raw ID
  static String? extractGoogleDriveFileId(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final pathMatch = RegExp(
      r'(?:drive|docs)\.google\.com\/file\/d\/([a-zA-Z0-9_-]{20,})',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (pathMatch != null) return pathMatch.group(1);

    final paramMatch = RegExp(
      r'(?:drive|docs)\.google\.com\/(?:open|uc)\?(?:[^\s&]+&)*id=([a-zA-Z0-9_-]{20,})',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (paramMatch != null) return paramMatch.group(1);

    if (RegExp(r'^[a-zA-Z0-9_-]{25,60}$').hasMatch(trimmed)) {
      return trimmed;
    }

    return null;
  }

  /// Extracts Dailymotion video ID from URL or raw ID
  static String? extractDailymotionVideoId(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    if (RegExp(r'^[xk][a-zA-Z0-9]{4,8}$', caseSensitive: false).hasMatch(trimmed)) {
      return trimmed;
    }

    try {
      final regExp = RegExp(
        r'(?:dailymotion\.com\/(?:video\/|embed\/video\/)|dai\.ly\/)([a-zA-Z0-9]+)',
        caseSensitive: false,
      );
      final match = regExp.firstMatch(trimmed);
      final id = match?.group(1);
      return id?.split('_').first;
    } catch (_) {
      return null;
    }
  }

  /// Extracts Bstation / Bilibili video ID from URL or raw ID
  static String? extractBstationVideoId(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    if (RegExp(r'^BV[a-zA-Z0-9]{10}$', caseSensitive: false).hasMatch(trimmed)) {
      return trimmed;
    }
    if (RegExp(r'^\d+(?:\/\d+)?$').hasMatch(trimmed)) {
      return trimmed;
    }

    try {
      final playMatch = RegExp(
        r'bilibili\.tv\/(?:id|en|th|vi|ms)\/play\/([0-9]+(?:\/[0-9]+)?)',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (playMatch != null) return playMatch.group(1);

      final tvMatch = RegExp(
        r'bilibili\.tv\/(?:id|en|th|vi|ms)\/video\/([0-9]+)',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (tvMatch != null) return tvMatch.group(1);

      final comMatch = RegExp(
        r'bilibili\.com\/video\/(BV[a-zA-Z0-9]+|av[0-9]+)',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (comMatch != null) return comMatch.group(1);

      final shortMatch = RegExp(
        r'b23\.tv\/([a-zA-Z0-9]+)',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (shortMatch != null) return shortMatch.group(1);
    } catch (_) {}

    return null;
  }

  /// Centralized detection of platform, ID, title, and thumbnail from any URL or ID
  static DetectedMedia? detectMediaFromUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final ytId = extractYouTubeVideoId(trimmed);
    if (ytId != null) {
      return DetectedMedia(
        mediaType: 'youtube',
        mediaUrl: 'https://www.youtube.com/watch?v=$ytId',
        mediaId: ytId,
        title: 'Video YouTube ($ytId)',
        thumbnailUrl: 'https://img.youtube.com/vi/$ytId/hqdefault.jpg',
      );
    }

    final twitch = extractTwitchMedia(trimmed);
    if (twitch != null) {
      return DetectedMedia(
        mediaType: 'twitch',
        mediaUrl: trimmed.startsWith('http') ? trimmed : 'https://www.twitch.tv/${twitch.id}',
        mediaId: twitch.id,
        title: 'Twitch ${twitch.type.toUpperCase()}: ${twitch.id}',
      );
    }

    final vimeoId = extractVimeoVideoId(trimmed);
    if (vimeoId != null) {
      return DetectedMedia(
        mediaType: 'vimeo',
        mediaUrl: 'https://vimeo.com/$vimeoId',
        mediaId: vimeoId,
        title: 'Vimeo Video ($vimeoId)',
        thumbnailUrl: 'https://vumbnail.com/$vimeoId.jpg',
      );
    }

    final driveId = extractGoogleDriveFileId(trimmed);
    if (driveId != null) {
      return DetectedMedia(
        mediaType: 'google_drive',
        mediaUrl: trimmed.startsWith('http') ? trimmed : 'https://drive.google.com/file/d/$driveId/view?usp=sharing',
        mediaId: driveId,
        title: 'Google Drive Video ($driveId)',
        thumbnailUrl: 'https://drive.google.com/thumbnail?id=$driveId&sz=w640',
      );
    }

    final dmId = extractDailymotionVideoId(trimmed);
    if (dmId != null) {
      return DetectedMedia(
        mediaType: 'dailymotion',
        mediaUrl: 'https://www.dailymotion.com/video/$dmId',
        mediaId: dmId,
        title: 'Dailymotion Video ($dmId)',
        thumbnailUrl: 'https://www.dailymotion.com/thumbnail/video/$dmId',
      );
    }

    final bstationId = extractBstationVideoId(trimmed);
    if (bstationId != null) {
      final bstationUrl = bstationId.startsWith('BV') || bstationId.startsWith('bv')
          ? 'https://www.bilibili.com/video/$bstationId'
          : 'https://www.bilibili.tv/id/play/$bstationId';
      return DetectedMedia(
        mediaType: 'bstation',
        mediaUrl: trimmed.startsWith('http') ? trimmed : bstationUrl,
        mediaId: bstationId,
        title: 'Bstation Video ($bstationId)',
      );
    }

    if (trimmed.startsWith('p2p://')) {
      final uri = Uri.tryParse(trimmed);
      final title = uri?.queryParameters['title'] ?? 'Video Lokal P2P';
      return DetectedMedia(
        mediaType: 'direct_url',
        mediaUrl: trimmed,
        title: title,
      );
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

  /// Loads media into player
  Future<void> loadMedia(
    String type,
    String url, {
    bool autoPlay = false,
    double startSeconds = 0.0,
  }) async {
    _errorMessage = null;

    // Smart-detect media type if user entered a YouTube, Twitch, Vimeo, Google Drive, Dailymotion, Bstation, or direct media URL
    var effectiveType = type;
    final isYtUrl = extractYouTubeVideoId(url) != null;
    final isTwitchUrl = extractTwitchMedia(url) != null;
    final isVimeoUrl = extractVimeoVideoId(url) != null;
    final isDriveUrl = extractGoogleDriveFileId(url) != null;
    final isDailymotionUrl = extractDailymotionVideoId(url) != null;
    final isBstationUrl = extractBstationVideoId(url) != null;

    if (isYtUrl) {
      effectiveType = 'youtube';
    } else if (isTwitchUrl) {
      effectiveType = 'twitch';
    } else if (isVimeoUrl) {
      effectiveType = 'vimeo';
    } else if (isDriveUrl) {
      effectiveType = 'google_drive';
    } else if (isDailymotionUrl) {
      effectiveType = 'dailymotion';
    } else if (isBstationUrl) {
      effectiveType = 'bstation';
    } else if (effectiveType == 'direct_url' ||
        effectiveType == 'local_p2p' ||
        url.startsWith('p2p://') ||
        url.endsWith('.mp4') ||
        url.endsWith('.m3u8') ||
        url.endsWith('.webm') ||
        url.endsWith('.mkv') ||
        url.endsWith('.mov') ||
        url.endsWith('.avi')) {
      effectiveType = 'direct_url';
    }

    _mediaType = effectiveType;
    _mediaUrl = url;
    _position = startSeconds;
    _playbackSpeed = 1.0;

    // Pause any active players not matching current type
    if (effectiveType != 'youtube') {
      _ytController?.pauseVideo();
    }
    if (effectiveType != 'direct_url') {
      if (kIsWeb) {
        await _webVideoAdapter?.pause();
      } else {
        await _mkPlayer?.pause();
      }
    }

    if (effectiveType == 'vimeo') {
      _availableQualities = const [
        VideoQuality.auto(label: 'Auto (Rekomendasi)'),
        VideoQuality(id: '1080p', label: '1080p Full HD', height: 1080),
        VideoQuality(id: '720p', label: '720p HD', height: 720),
        VideoQuality(id: '540p', label: '540p', height: 540),
        VideoQuality(id: '360p', label: '360p Hemat Kuota', height: 360),
        VideoQuality(id: '240p', label: '240p', height: 240),
      ];
      _selectedQuality = _availableQualities.first;
      _isPlaying = autoPlay;
      notifyListeners();
      return;
    }

    if (effectiveType == 'dailymotion') {
      _availableQualities = const [
        VideoQuality.auto(label: 'Auto (Rekomendasi)'),
        VideoQuality(id: '1080', label: '1080p Full HD', height: 1080),
        VideoQuality(id: '720', label: '720p HD', height: 720),
        VideoQuality(id: '480', label: '480p SD', height: 480),
        VideoQuality(id: '380', label: '380p', height: 380),
        VideoQuality(id: '240', label: '240p Hemat Kuota', height: 240),
      ];
      _selectedQuality = _availableQualities.first;
      _isPlaying = autoPlay;
      notifyListeners();
      return;
    }

    if (effectiveType == 'twitch' ||
        effectiveType == 'google_drive' ||
        effectiveType == 'bstation' ||
        effectiveType == 'bilibili') {
      _availableQualities = [
        VideoQuality.auto(label: 'Auto (Kontrol Bawaan Player)'),
      ];
      _selectedQuality = _availableQualities.first;
      _isPlaying = autoPlay;
      notifyListeners();
      return;
    }

    if (effectiveType == 'youtube') {
      _availableQualities = const [
        VideoQuality.auto(label: 'Auto (Rekomendasi)'),
        VideoQuality(id: 'hd1080', label: '1080p Full HD', height: 1080),
        VideoQuality(id: 'hd720', label: '720p HD', height: 720),
        VideoQuality(id: 'large', label: '480p SD', height: 480),
        VideoQuality(id: 'medium', label: '360p Hemat Kuota', height: 360),
        VideoQuality(id: 'small', label: '240p', height: 240),
        VideoQuality(id: 'tiny', label: '144p', height: 144),
      ];
      _selectedQuality = _availableQualities.first;
      _detectedYtQuality = null;

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
          showVideoAnnotations: false,
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

        if (value.playbackQuality != null && value.playbackQuality!.isNotEmpty) {
          if (_detectedYtQuality != value.playbackQuality) {
            _detectedYtQuality = value.playbackQuality;
            notifyListeners();
          }
        }

        if (ytState == PlayerState.ended) {
          onPlaybackEnded?.call();
        }

        // Synchronize fullscreen state from YouTube player
        final bool isYtFullscreen = value.fullScreenOption.enabled;
        if (isYtFullscreen != _isFullscreen) {
          _isFullscreen = isYtFullscreen;
          notifyListeners();
          if (isYtFullscreen) {
            FullscreenHelper.enterFullscreen();
          } else {
            FullscreenHelper.exitFullscreen();
          }
        }
      }));
    } else {
      // Direct URL
      _ytController?.pauseVideo();
      _availableQualities = [VideoQuality.auto()];
      _selectedQuality = _availableQualities.first;

      if (url.startsWith('p2p://')) {
        _isPlaying = autoPlay;
        notifyListeners();
        return;
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
        final state = _ytController?.value.playerState;
        final videoId = _ytController?.key ?? extractYouTubeVideoId(_mediaUrl);
        if (videoId != null &&
            (state == PlayerState.cued ||
                state == PlayerState.unStarted ||
                state == PlayerState.unknown ||
                state == PlayerState.paused)) {
          await _ytController?.loadVideoById(
            videoId: videoId,
            startSeconds: _position > 0 ? _position : null,
          );
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
      } else if (_mediaType == 'twitch' ||
          _mediaType == 'vimeo' ||
          _mediaType == 'google_drive' ||
          _mediaType == 'dailymotion' ||
          _mediaType == 'bstation' ||
          _mediaType == 'bilibili') {
        onEmbedPlayerCommand?.call('play', null);
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
      } else if (_mediaType == 'twitch' ||
          _mediaType == 'vimeo' ||
          _mediaType == 'google_drive' ||
          _mediaType == 'dailymotion' ||
          _mediaType == 'bstation' ||
          _mediaType == 'bilibili') {
        onEmbedPlayerCommand?.call('pause', null);
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
      } else if (_mediaType == 'twitch' ||
          _mediaType == 'vimeo' ||
          _mediaType == 'google_drive' ||
          _mediaType == 'dailymotion' ||
          _mediaType == 'bstation' ||
          _mediaType == 'bilibili') {
        onEmbedPlayerCommand?.call('seek', seconds);
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
      } else if (_mediaType == 'twitch' ||
          _mediaType == 'vimeo' ||
          _mediaType == 'google_drive' ||
          _mediaType == 'dailymotion' ||
          _mediaType == 'bstation' ||
          _mediaType == 'bilibili') {
        onEmbedPlayerCommand?.call('setRate', speed);
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
      } else if (_mediaType == 'twitch' ||
          _mediaType == 'vimeo' ||
          _mediaType == 'google_drive' ||
          _mediaType == 'dailymotion' ||
          _mediaType == 'bstation' ||
          _mediaType == 'bilibili') {
        onEmbedPlayerCommand?.call('setVolume', _volume);
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
        } else if (_mediaType == 'twitch' ||
            _mediaType == 'vimeo' ||
            _mediaType == 'google_drive' ||
            _mediaType == 'dailymotion' ||
            _mediaType == 'bstation' ||
            _mediaType == 'bilibili') {
          onEmbedPlayerCommand?.call('setMuted', true);
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
      if (_mediaType == 'direct_url') {
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
      } else if (_mediaType == 'youtube') {
        final qId = quality.isAuto ? 'default' : quality.id;
        try {
          await _ytController?.webViewController.runJavaScript(
            'try { player.setPlaybackQuality("$qId"); } catch(e){}',
          );
        } catch (e) {
          debugPrint('[UnifiedPlayerController] YouTube setQuality error: $e');
        }
      } else if (_mediaType == 'vimeo' || _mediaType == 'dailymotion') {
        onEmbedPlayerCommand?.call('setQuality', quality.id);
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

    if (_mediaType == 'youtube' && _ytController != null) {
      if (!_ytController!.value.fullScreenOption.enabled) {
        _ytController!.enterFullScreen();
      }
    }
  }

  Future<void> exitFullscreen() async {
    _isFullscreen = false;
    notifyListeners();

    await FullscreenHelper.exitFullscreen();

    if (_mediaType == 'youtube' && _ytController != null) {
      if (_ytController!.value.fullScreenOption.enabled) {
        _ytController!.exitFullScreen();
      }
    }
  }

  Future<void> toggleFullscreen() async {
    final bool ytFullscreen =
        _ytController?.value.fullScreenOption.enabled == true;
    if (_isFullscreen || ytFullscreen) {
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
    for (final sub in _ytSubscriptions) {
      sub.cancel();
    }
    _webVideoAdapter?.dispose();
    _mkPlayer?.dispose();
    _ytController?.close();
    super.dispose();
  }
}
