import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;
import '../../models/video_quality.dart';
import 'dailymotion_web_adapter.dart';

bool get isSupported => kIsWeb;

DailymotionWebAdapter createDailymotionWebAdapter({
  required void Function(double position) onPositionChanged,
  required void Function(double duration) onDurationChanged,
  required void Function(bool isPlaying) onPlayingChanged,
  required void Function() onPlaybackEnded,
  required void Function(String error) onError,
  void Function(List<VideoQuality> qualities)? onQualitiesChanged,
  void Function(VideoQuality quality)? onQualitySelectedChanged,
  void Function(int width, int height)? onResolutionChanged,
}) {
  return DailymotionWebAdapterWeb(
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

class DailymotionWebAdapterWeb implements DailymotionWebAdapter {
  static int _idCounter = 0;
  final String _viewType;
  final web.HTMLIFrameElement _iframeElement;
  final List<StreamSubscription> _subscriptions = [];

  final void Function(double position) onPositionChanged;
  final void Function(double duration) onDurationChanged;
  final void Function(bool isPlaying) onPlayingChanged;
  final void Function() onPlaybackEnded;
  final void Function(String error) onError;
  final void Function(List<VideoQuality> qualities)? onQualitiesChanged;
  final void Function(VideoQuality quality)? onQualitySelectedChanged;
  final void Function(int width, int height)? onResolutionChanged;

  String _currentVideoId = '';
  bool _isMuted = false;
  double _volume = 1.0;
  double _playbackSpeed = 1.0;

  List<VideoQuality> _availableQualities = [
    const VideoQuality.auto(
      label: 'Auto (Otomatis Dailymotion)',
      mode: QualityControlMode.webviewBridge,
    ),
  ];
  VideoQuality? _selectedQuality;

  @override
  List<VideoQuality> get availableQualities => List.unmodifiable(_availableQualities);

  @override
  VideoQuality? get selectedQuality => _selectedQuality;

  @override
  bool get isMuted => _isMuted;

  @override
  String get currentVideoId => _currentVideoId;

  @override
  double get volume => _volume;

  @override
  double get playbackSpeed => _playbackSpeed;

  DailymotionWebAdapterWeb({
    required this.onPositionChanged,
    required this.onDurationChanged,
    required this.onPlayingChanged,
    required this.onPlaybackEnded,
    required this.onError,
    this.onQualitiesChanged,
    this.onQualitySelectedChanged,
    this.onResolutionChanged,
  })  : _viewType = 'nobarin_dailymotion_player_${++_idCounter}',
        _iframeElement = web.HTMLIFrameElement() {
    _selectedQuality = _availableQualities.first;

    _iframeElement
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none'
      ..style.backgroundColor = 'black'
      ..allow =
          'autoplay; fullscreen; picture-in-picture; encrypted-media; accelerometer; gyroscope'
      ..setAttribute('allowfullscreen', 'true')
      ..setAttribute('webkitallowfullscreen', 'true')
      ..setAttribute('mozallowfullscreen', 'true');

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _iframeElement,
    );

    _subscriptions.add(
      web.window.onMessage.listen((web.MessageEvent event) {
        _handleWindowMessage(event);
      }),
    );
  }

  void _handleWindowMessage(web.MessageEvent event) {
    try {
      final raw = event.data?.dartify();
      if (raw == null) return;

      Map<String, dynamic>? data;
      if (raw is String) {
        final trimmed = raw.trim();
        if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
          try {
            final dec = jsonDecode(trimmed);
            if (dec is Map) {
              data = Map<String, dynamic>.from(dec);
            }
          } catch (_) {}
        } else if (trimmed.contains('=')) {
          try {
            data = Uri.splitQueryString(trimmed);
          } catch (_) {}
        }
      } else if (raw is Map) {
        data = Map<String, dynamic>.from(raw);
      }

      if (data == null) return;

      final eventName =
          (data['event'] ?? data['type'] ?? '').toString().toLowerCase().trim();
      if (eventName.isEmpty) return;

      switch (eventName) {
        case 'timeupdate':
        case 'time':
          final rawTime = data['time'] ?? data['currentTime'] ?? data['position'];
          if (rawTime != null) {
            final cur = (rawTime is num)
                ? rawTime.toDouble()
                : double.tryParse(rawTime.toString()) ?? 0.0;
            onPositionChanged(cur);
          }
          final rawDur = data['duration'];
          if (rawDur != null) {
            final dur = (rawDur is num)
                ? rawDur.toDouble()
                : double.tryParse(rawDur.toString()) ?? 0.0;
            if (dur > 0) {
              onDurationChanged(dur);
            }
          }
          break;

        case 'durationchange':
          final rawDur = data['duration'];
          if (rawDur != null) {
            final dur = (rawDur is num)
                ? rawDur.toDouble()
                : double.tryParse(rawDur.toString()) ?? 0.0;
            if (dur > 0) {
              onDurationChanged(dur);
            }
          }
          break;

        case 'play':
        case 'playing':
          onPlayingChanged(true);
          break;

        case 'pause':
          onPlayingChanged(false);
          break;

        case 'ended':
        case 'video_end':
          onPlayingChanged(false);
          onPlaybackEnded();
          break;

        case 'resolution':
          final rawH = data['height'];
          final rawW = data['width'];
          final h = (rawH is num) ? rawH.toInt() : int.tryParse(rawH?.toString() ?? '');
          final w = (rawW is num) ? rawW.toInt() : int.tryParse(rawW?.toString() ?? '');
          if (h != null && w != null && h > 0 && w > 0) {
            onResolutionChanged?.call(w, h);
          }
          break;

        case 'qualities':
          final rawList = data['qualities'];
          if (rawList is List && rawList.isNotEmpty) {
            _updateQualities(rawList);
          } else if (rawList is String && rawList.isNotEmpty) {
            final split = rawList.split(',').map((e) => e.trim()).toList();
            _updateQualities(split);
          }
          break;

        case 'qualitychange':
          final curQ = data['quality']?.toString().trim();
          if (curQ != null && curQ.isNotEmpty) {
            _selectedQuality = _availableQualities.firstWhere(
              (q) => q.id == curQ,
              orElse: () => VideoQuality.dailymotion(curQ),
            );
            onQualitySelectedChanged?.call(_selectedQuality!);
          }
          break;

        case 'error':
          final errMsg =
              data['error']?.toString() ?? data['message']?.toString() ?? 'Error pemutaran Dailymotion';
          onError(errMsg);
          break;
      }
    } catch (e) {
      debugPrint('[DailymotionWebAdapter] Error parsing message: $e');
    }
  }

  void _updateQualities(List<dynamic> list) {
    final List<VideoQuality> qualities = [
      const VideoQuality.auto(
        label: 'Auto (Otomatis Dailymotion)',
        mode: QualityControlMode.webviewBridge,
      ),
    ];
    final Set<String> seen = {'auto'};

    for (final item in list) {
      final str = (item is Map
              ? (item['id'] ?? item['quality'])?.toString()
              : item.toString())
          ?.trim()
          .toLowerCase() ??
          '';
      if (str.isEmpty || seen.contains(str) || str == 'auto') continue;
      seen.add(str);
      qualities.add(VideoQuality.dailymotion(str));
    }

    qualities.sort((a, b) {
      if (a.isAuto) return -1;
      if (b.isAuto) return 1;
      return (b.height ?? 0).compareTo(a.height ?? 0);
    });

    _availableQualities = qualities;
    debugPrint(
      '[DailymotionWebAdapter] Detected qualities: ${_availableQualities.map((q) => q.id).join(', ')}',
    );
    onQualitiesChanged?.call(_availableQualities);
  }

  void _postMessage(String command, [dynamic param]) {
    try {
      final win = _iframeElement.contentWindow;
      if (win == null) return;

      // 1. Query-string postMessage format
      final strMsg = param != null ? '$command=$param' : command;
      win.postMessage(strMsg.toJS, '*'.toJS);

      // 2. JSON postMessage format
      final jsonMap = <String, dynamic>{
        'command': command,
        if (param != null) 'parameters': [param],
      };
      if (param != null && (command == 'quality' || command == 'setQuality')) {
        jsonMap['value'] = param;
      }
      win.postMessage(jsonEncode(jsonMap).toJS, '*'.toJS);
    } catch (e) {
      debugPrint('[DailymotionWebAdapter] postMessage error: $e');
    }
  }

  @override
  Widget buildPlayerWidget() {
    return HtmlElementView(
      key: ValueKey(_viewType),
      viewType: _viewType,
    );
  }

  @override
  Future<void> load(
    String videoId, {
    bool autoPlay = false,
    double startSeconds = 0.0,
  }) async {
    _currentVideoId = videoId;
    final startParam =
        startSeconds > 0 ? '&startTime=${startSeconds.round()}' : '';
    final autoPlayParam = autoPlay ? '1' : '0';

    final embedUrl =
        'https://geo.dailymotion.com/player.html?video=$videoId&autoplay=$autoPlayParam&mute=0&api=postMessage&apimode=json$startParam';

    debugPrint('[DailymotionWebAdapter] Loading embed iframe: $embedUrl');
    _iframeElement.src = embedUrl;
  }

  @override
  Future<void> play() async {
    _postMessage('play');
  }

  @override
  Future<void> pause() async {
    _postMessage('pause');
  }

  @override
  Future<void> seekTo(double seconds) async {
    final clamped = seconds < 0 ? 0.0 : seconds;
    _postMessage('seek', clamped);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    _postMessage('playback_speed', speed);
    _postMessage('setPlaybackSpeed', speed);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    _isMuted = _volume == 0;
    _postMessage('volume', _volume);
  }

  @override
  Future<void> setMuted(bool muted) async {
    _isMuted = muted;
    _postMessage('muted', muted ? 1 : 0);
  }

  @override
  Future<void> setQuality(String qualityId) async {
    debugPrint('[DailymotionWebAdapter] setQuality($qualityId)');
    _selectedQuality = _availableQualities.firstWhere(
      (q) => q.id == qualityId,
      orElse: () => VideoQuality.dailymotion(qualityId),
    );
    onQualitySelectedChanged?.call(_selectedQuality!);

    _postMessage('quality', qualityId);
    _postMessage('setQuality', qualityId);
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _iframeElement.src = 'about:blank';
  }
}
