import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;
import '../../models/video_quality.dart';
import 'vimeo_web_adapter.dart';

bool get isSupported => kIsWeb;

VimeoWebAdapter createVimeoWebAdapter({
  required void Function(double position) onPositionChanged,
  required void Function(double duration) onDurationChanged,
  required void Function(bool isPlaying) onPlayingChanged,
  required void Function() onPlaybackEnded,
  required void Function(String error) onError,
  void Function(List<VideoQuality> qualities)? onQualitiesChanged,
  void Function(VideoQuality quality)? onQualitySelectedChanged,
  void Function(int width, int height)? onResolutionChanged,
}) {
  return VimeoWebAdapterWeb(
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

class VimeoWebAdapterWeb implements VimeoWebAdapter {
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
      label: 'Auto (Otomatis Vimeo)',
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

  VimeoWebAdapterWeb({
    required this.onPositionChanged,
    required this.onDurationChanged,
    required this.onPlayingChanged,
    required this.onPlaybackEnded,
    required this.onError,
    this.onQualitiesChanged,
    this.onQualitySelectedChanged,
    this.onResolutionChanged,
  })  : _viewType = 'nobarin_vimeo_player_${++_idCounter}',
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
        }
      } else if (raw is Map) {
        data = Map<String, dynamic>.from(raw);
      }

      if (data == null) return;

      final eventName =
          (data['event'] ?? data['type'] ?? data['method'] ?? '').toString().toLowerCase().trim();
      if (eventName.isEmpty) return;

      final eventData = data['data'];

      switch (eventName) {
        case 'ready':
          debugPrint('[VimeoWebAdapter] Player ready, subscribing to events');
          _sendMethod('addEventListener', 'play');
          _sendMethod('addEventListener', 'pause');
          _sendMethod('addEventListener', 'timeupdate');
          _sendMethod('addEventListener', 'ended');
          _sendMethod('addEventListener', 'loaded');
          _sendMethod('addEventListener', 'qualitychange');
          _sendMethod('getQualities');
          break;

        case 'timeupdate':
          double? cur;
          double? dur;
          if (eventData is Map) {
            final s = eventData['seconds'];
            final d = eventData['duration'];
            if (s is num) cur = s.toDouble();
            if (d is num) dur = d.toDouble();
          } else {
            final s = data['seconds'] ?? data['currentTime'] ?? data['time'];
            final d = data['duration'];
            if (s is num) cur = s.toDouble();
            if (d is num) dur = d.toDouble();
          }
          if (cur != null) onPositionChanged(cur);
          if (dur != null && dur > 0) onDurationChanged(dur);
          break;

        case 'play':
        case 'playing':
          onPlayingChanged(true);
          break;

        case 'pause':
          onPlayingChanged(false);
          break;

        case 'ended':
          onPlayingChanged(false);
          onPlaybackEnded();
          break;

        case 'getqualities':
          final rawQualities = data['value'] ?? data['qualities'];
          if (rawQualities is List && rawQualities.isNotEmpty) {
            _updateQualities(rawQualities);
          }
          break;

        case 'qualitychange':
          String? q;
          if (eventData is Map) {
            q = eventData['quality']?.toString();
          } else if (data['value'] != null) {
            q = data['value']?.toString();
          }
          if (q != null && q.isNotEmpty) {
            _selectedQuality = _availableQualities.firstWhere(
              (item) => item.id == q,
              orElse: () => VideoQuality.vimeo(q!),
            );
            onQualitySelectedChanged?.call(_selectedQuality!);
          }
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
      }
    } catch (e) {
      debugPrint('[VimeoWebAdapter] Error parsing window message: $e');
    }
  }

  void _updateQualities(List<dynamic> list) {
    final List<VideoQuality> parsed = [
      const VideoQuality.auto(
        label: 'Auto (Otomatis Vimeo)',
        mode: QualityControlMode.webviewBridge,
      ),
    ];

    for (final item in list) {
      String id = '';
      String label = '';
      if (item is Map) {
        id = (item['id'] ?? item['quality'] ?? '').toString();
        label = (item['label'] ?? id).toString();
      } else if (item != null) {
        id = item.toString().trim();
        label = id;
      }
      if (id.isEmpty || id.toLowerCase() == 'auto') continue;

      if (!parsed.any((q) => q.id == id)) {
        parsed.add(VideoQuality.vimeo(id, label: label));
      }
    }

    if (parsed.length > 1) {
      _availableQualities = parsed;
      onQualitiesChanged?.call(List.unmodifiable(_availableQualities));
    }
  }

  void _sendMethod(String method, [dynamic value]) {
    try {
      final win = _iframeElement.contentWindow;
      if (win == null) return;

      final Map<String, dynamic> msg = {'method': method};
      if (value != null) {
        msg['value'] = value;
      }
      final jsonStr = jsonEncode(msg);
      win.postMessage(jsonStr.toJS, '*'.toJS);
    } catch (e) {
      debugPrint('[VimeoWebAdapter] postMessage error: $e');
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
    String? unlistedHash,
  }) async {
    _currentVideoId = videoId;
    final autoPlayParam = autoPlay ? '1' : '0';
    final startParam =
        startSeconds > 0 ? '#t=${startSeconds.toStringAsFixed(1)}s' : '';
    final hashParam = (unlistedHash != null && unlistedHash.isNotEmpty)
        ? '&h=$unlistedHash'
        : '';

    final embedUrl =
        'https://player.vimeo.com/video/$videoId?api=1&player_id=vimeo_player&autoplay=$autoPlayParam&muted=0&transparent=0&dnt=1$hashParam$startParam';

    debugPrint('[VimeoWebAdapter] Loading embed iframe: $embedUrl');
    _iframeElement.src = embedUrl;
  }

  @override
  Future<void> play() async {
    _sendMethod('play');
  }

  @override
  Future<void> pause() async {
    _sendMethod('pause');
  }

  @override
  Future<void> seekTo(double seconds) async {
    final clamped = seconds < 0 ? 0.0 : seconds;
    _sendMethod('setCurrentTime', clamped);
    _sendMethod('seekTo', clamped);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    _sendMethod('setPlaybackRate', speed);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    _isMuted = _volume == 0;
    _sendMethod('setVolume', _volume);
  }

  @override
  Future<void> setMuted(bool muted) async {
    _isMuted = muted;
    _sendMethod('setVolume', muted ? 0.0 : _volume);
  }

  @override
  Future<void> setQuality(String qualityId) async {
    debugPrint('[VimeoWebAdapter] setQuality($qualityId)');
    _selectedQuality = _availableQualities.firstWhere(
      (q) => q.id == qualityId,
      orElse: () => VideoQuality.vimeo(qualityId),
    );
    onQualitySelectedChanged?.call(_selectedQuality!);
    _sendMethod('setQuality', qualityId);
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
