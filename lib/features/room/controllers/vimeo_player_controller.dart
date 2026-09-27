import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../../../core/network/app_http_client.dart';
import '../models/video_quality.dart';
import 'vimeo_web_adapter/vimeo_web_adapter.dart';

/// Controller for Vimeo video player via WebViewController & HTML5 video bridge
class VimeoPlayerController extends ChangeNotifier {
  final GlobalKey webViewKey = GlobalKey(debugLabel: 'VimeoWebView');
  WebViewController? _webViewController;
  VimeoWebAdapter? _webAdapter;
  String _url = '';
  String? _videoId;
  String? _unlistedHash;
  double _position = 0.0;
  double _duration = 0.0;
  bool _isPlaying = false;
  bool _isMuted = false;
  double _volume = 1.0;
  double _playbackSpeed = 1.0;
  bool _isDisposed = false;
  bool _isFullscreenTransition = false;

  void setFullscreenTransition(bool active) {
    _isFullscreenTransition = active;
  }

  // Video Quality state for Vimeo
  List<VideoQuality> _availableQualities = [
    const VideoQuality.auto(
      label: 'Auto (Otomatis Vimeo)',
      mode: QualityControlMode.webviewBridge,
    ),
  ];
  VideoQuality? _selectedQuality;
  int? _detectedHeight;
  int? _detectedWidth;

  VimeoPlayerController() {
    _selectedQuality = _availableQualities.first;
  }

  void Function(double position)? onPositionChanged;
  void Function(double duration)? onDurationChanged;
  void Function(bool isPlaying)? onPlayingChanged;
  void Function()? onPlaybackEnded;
  void Function(String error)? onError;
  void Function(List<VideoQuality> qualities)? onQualitiesChanged;
  void Function(VideoQuality quality)? onQualitySelectedChanged;

  WebViewController? get webViewController => _webViewController;
  VimeoWebAdapter? get webAdapter => _webAdapter;

  /// Builds the embedded Vimeo player widget on Flutter Web.
  Widget? buildWebWidget() => _webAdapter?.buildPlayerWidget();

  String get url => _url;
  String? get videoId => _videoId;
  String? get unlistedHash => _unlistedHash;
  double get position => _position;
  double get duration => _duration;
  bool get isPlaying => _isPlaying;
  bool get isMuted => _isMuted;
  double get volume => _volume;
  double get playbackSpeed => _playbackSpeed;
  List<VideoQuality> get availableQualities => List.unmodifiable(_availableQualities);
  VideoQuality? get selectedQuality => _selectedQuality;
  int? get detectedHeight => _detectedHeight;
  int? get detectedWidth => _detectedWidth;

  bool get _isSupportedMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Extracts Vimeo video ID from various URL formats
  static String? extractVideoId(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    // Pattern 1: channels, groups, or manage paths
    final channelMatch = RegExp(
      r'vimeo\.com\/(?:channels\/(?:[^\/]+)|groups\/(?:[^\/]+)\/videos|manage\/videos)\/([0-9]+)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (channelMatch != null && channelMatch.groupCount >= 1) {
      return channelMatch.group(1);
    }

    // Pattern 2: player.vimeo.com/video/{ID}
    final playerMatch = RegExp(
      r'player\.vimeo\.com\/video\/([0-9]+)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (playerMatch != null && playerMatch.groupCount >= 1) {
      return playerMatch.group(1);
    }

    // Pattern 3: vimeo.com/{ID} (with optional /hash or query)
    final standardMatch = RegExp(
      r'vimeo\.com\/([0-9]+)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (standardMatch != null && standardMatch.groupCount >= 1) {
      return standardMatch.group(1);
    }

    // Pattern 4: Direct numeric video ID string (e.g. 76979871)
    if (RegExp(r'^[0-9]{4,14}$').hasMatch(trimmed)) {
      return trimmed;
    }

    return null;
  }

  /// Extracts unlisted privacy hash from Vimeo URL if present (e.g. vimeo.com/12345/abcdef or ?h=abcdef)
  static String? extractUnlistedHash(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.queryParameters.containsKey('h')) {
      final h = uri.queryParameters['h']?.trim();
      if (h != null && h.isNotEmpty) return h;
    }

    // Path pattern: vimeo.com/{id}/{hash}
    final match = RegExp(
      r'vimeo\.com\/[0-9]+\/([a-zA-Z0-9]+)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match != null && match.groupCount >= 1) {
      final h = match.group(1);
      if (h != null && !RegExp(r'^[0-9]+$').hasMatch(h)) {
        return h;
      }
    }

    return null;
  }

  Future<void> _fetchVimeoMetadata(String? vId) async {
    if (vId == null || vId.isEmpty || _isDisposed) return;
    try {
      final oEmbedUri = Uri.parse(
        'https://vimeo.com/api/oembed.json?url=https://vimeo.com/$vId',
      );
      final resp = await AppHttpClient.get(
        oEmbedUri,
        timeout: const Duration(seconds: 8),
        maxRetries: 1,
      );
      if (_isDisposed || _videoId != vId) return;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) {
          final dur = decoded['duration'];
          if (dur is num && dur > 0 && _duration == 0) {
            _duration = dur.toDouble();
            onDurationChanged?.call(_duration);
            notifyListeners();
          }
          final w = decoded['width'];
          final h = decoded['height'];
          if (w is num && h is num && w > 0 && h > 0) {
            _detectedWidth = w.toInt();
            _detectedHeight = h.toInt();
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('[VimeoPlayer] Error fetching oEmbed metadata: $e');
    }
  }

  /// Loads Vimeo video by URL or Video ID
  Future<void> loadUrl(
    String rawUrl, {
    bool autoPlay = false,
    double startSeconds = 0.0,
  }) async {
    _url = rawUrl;
    _videoId = extractVideoId(rawUrl);
    _unlistedHash = extractUnlistedHash(rawUrl);
    _position = startSeconds;
    _duration = 0.0;
    _isPlaying = autoPlay;
    _detectedHeight = null;
    _detectedWidth = null;

    debugPrint(
      '[VimeoPlayer] loadUrl(url=$rawUrl, videoId=$_videoId, hash=$_unlistedHash)',
    );

    // Initial default quality
    _availableQualities = [
      const VideoQuality.auto(
        label: 'Auto (Otomatis Vimeo)',
        mode: QualityControlMode.webviewBridge,
      ),
    ];
    _selectedQuality = _availableQualities.first;
    notifyListeners();

    _fetchVimeoMetadata(_videoId);

    // Web platform handling via VimeoWebAdapter
    if (kIsWeb) {
      _webAdapter ??= VimeoWebAdapter.create(
        onPositionChanged: (pos) {
          if (_isDisposed) return;
          _position = pos;
          onPositionChanged?.call(pos);
          notifyListeners();
        },
        onDurationChanged: (dur) {
          if (_isDisposed) return;
          if (dur > 0 && dur != _duration) {
            _duration = dur;
            onDurationChanged?.call(dur);
            notifyListeners();
          }
        },
        onPlayingChanged: (playing) {
          if (_isDisposed) return;
          if (!playing && _isFullscreenTransition && _isPlaying) {
            debugPrint('[VimeoPlayer] Spurious pause ignored during fullscreen transition');
            _webAdapter?.play();
            return;
          }
          if (_isPlaying != playing) {
            _isPlaying = playing;
            onPlayingChanged?.call(playing);
            notifyListeners();
          }
        },
        onPlaybackEnded: () {
          if (_isDisposed) return;
          _isPlaying = false;
          onPlaybackEnded?.call();
          notifyListeners();
        },
        onError: (err) {
          if (_isDisposed) return;
          onError?.call(err);
        },
        onQualitiesChanged: (qualities) {
          if (_isDisposed) return;
          _availableQualities = qualities;
          if (_webAdapter?.selectedQuality != null) {
            _selectedQuality = _webAdapter!.selectedQuality;
          }
          onQualitiesChanged?.call(qualities);
          notifyListeners();
        },
        onQualitySelectedChanged: (quality) {
          if (_isDisposed) return;
          _selectedQuality = quality;
          onQualitySelectedChanged?.call(quality);
          notifyListeners();
        },
        onResolutionChanged: (w, h) {
          if (_isDisposed) return;
          _detectedWidth = w;
          _detectedHeight = h;
          notifyListeners();
        },
      );

      final vId = _videoId ?? rawUrl.trim();
      await _webAdapter?.load(
        vId,
        autoPlay: autoPlay,
        startSeconds: startSeconds,
        unlistedHash: _unlistedHash,
      );
      notifyListeners();
      return;
    }

    if (!_isSupportedMobilePlatform) {
      return;
    }

    final targetUri = _resolveTargetUri(
      rawUrl,
      autoPlay: autoPlay,
      startSeconds: startSeconds,
    );

    try {
      if (_webViewController == null) {
        late final PlatformWebViewControllerCreationParams params;
        if (WebViewPlatform.instance is WebKitWebViewPlatform) {
          params = WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          );
        } else if (WebViewPlatform.instance is AndroidWebViewPlatform) {
          params = AndroidWebViewControllerCreationParams();
        } else {
          params = const PlatformWebViewControllerCreationParams();
        }

        final controller = WebViewController.fromPlatformCreationParams(params)
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setUserAgent(
            'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          )
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageFinished: (finishedUrl) {
                _injectPlayerOptimizations(
                  autoPlay: autoPlay,
                  startSeconds: startSeconds,
                );
              },
              onNavigationRequest: (request) {
                final uri = Uri.tryParse(request.url);
                if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
                  return NavigationDecision.prevent;
                }
                return NavigationDecision.navigate;
              },
              onWebResourceError: (error) {
                onError?.call(error.description);
              },
            ),
          )
          ..addJavaScriptChannel(
            'NobarVimeoPlayer',
            onMessageReceived: (message) {
              _handlePlayerBridgeMessage(message.message);
            },
          );

        final platform = controller.platform;
        if (platform is AndroidWebViewController) {
          await platform.setMediaPlaybackRequiresUserGesture(false);
        }

        await controller.loadRequest(targetUri);
        _webViewController = controller;
      } else {
        final platform = _webViewController!.platform;
        if (platform is AndroidWebViewController) {
          await platform.setMediaPlaybackRequiresUserGesture(false);
        }
        await _webViewController!.loadRequest(targetUri);
      }
      notifyListeners();
    } catch (e) {
      onError?.call('Gagal menginisialisasi pemutar Vimeo: $e');
    }
  }

  @visibleForTesting
  Uri resolveTargetUriForTesting(
    String rawUrl, {
    bool autoPlay = false,
    double startSeconds = 0.0,
    String? quality,
  }) =>
      _resolveTargetUri(
        rawUrl,
        autoPlay: autoPlay,
        startSeconds: startSeconds,
        quality: quality,
      );

  /// Converts raw URL or video ID to Vimeo player embed URI
  Uri _resolveTargetUri(
    String rawUrl, {
    required bool autoPlay,
    required double startSeconds,
    String? quality,
  }) {
    final vId = _videoId ?? extractVideoId(rawUrl);
    if (vId != null && vId.isNotEmpty) {
      final autoPlayParam = autoPlay ? '1' : '0';
      final startTimeParam =
          startSeconds > 0 ? '#t=${startSeconds.toStringAsFixed(1)}s' : '';
      final hashParam = (_unlistedHash != null && _unlistedHash!.isNotEmpty)
          ? '&h=$_unlistedHash'
          : '';
      final qualityParam =
          (quality != null && quality.isNotEmpty && quality != 'auto')
              ? '&quality=$quality'
              : '';
      return Uri.parse(
        'https://player.vimeo.com/video/$vId?api=1&player_id=vimeo_player&autoplay=$autoPlayParam&muted=0&transparent=0&dnt=1$hashParam$qualityParam$startTimeParam',
      );
    }
    return Uri.parse(rawUrl.trim());
  }

  /// Injects CSS and JavaScript to optimize player layout and hook into Vimeo events
  Future<void> _injectPlayerOptimizations({
    required bool autoPlay,
    required double startSeconds,
  }) async {
    if (_webViewController == null || _isDisposed) return;

    final script = '''
      (function() {
        // 1. Clean UI and ensure full-screen responsive presentation
        var existingStyle = document.getElementById('nobar-vimeo-style');
        if (!existingStyle) {
          var style = document.createElement('style');
          style.id = 'nobar-vimeo-style';
          style.textContent = `
            html, body {
              background-color: #000 !important;
              margin: 0 !important;
              padding: 0 !important;
              overflow: hidden !important;
              width: 100% !important;
              height: 100% !important;
            }
            .vp-video-wrapper, .player, #player, .video-wrapper, iframe {
              width: 100vw !important;
              height: 100vh !important;
              position: fixed !important;
              top: 0 !important;
              left: 0 !important;
            }
            video {
              width: 100% !important;
              height: 100% !important;
              object-fit: contain !important;
            }
          `;
          document.head.appendChild(style);
        }

        // 2. Setup PostMessage listener for Vimeo events
        function postBridge(data) {
          if (window.NobarVimeoPlayer && window.NobarVimeoPlayer.postMessage) {
            window.NobarVimeoPlayer.postMessage(JSON.stringify(data));
          }
        }

        window.addEventListener('message', function(e) {
          try {
            var raw = e.data;
            if (typeof raw === 'string' && (raw.startsWith('{') || raw.startsWith('['))) {
              raw = JSON.parse(raw);
            }
            if (raw && typeof raw === 'object') {
              var eventName = raw.event || raw.type || raw.method;
              if (eventName) {
                postBridge({
                  event: eventName,
                  data: raw.data || raw.value || raw
                });
              }
            }
          } catch(err) {}
        });

        // 3. Fallback video element hook
        function setupVideoElementBridge() {
          var video = document.querySelector('video');
          if (!video) return;
          if (video.__nobarAttached) return;
          video.__nobarAttached = true;

          ${startSeconds > 0 ? "video.currentTime = $startSeconds;" : ""}
          video.volume = $_volume;
          video.muted = ${_isMuted ? "true" : "false"};
          video.playbackRate = $_playbackSpeed;

          video.addEventListener('timeupdate', function() {
            postBridge({
              event: 'timeupdate',
              currentTime: video.currentTime,
              duration: video.duration || 0
            });
          });

          video.addEventListener('play', function() {
            postBridge({ event: 'play' });
          });

          video.addEventListener('pause', function() {
            postBridge({ event: 'pause' });
          });

          video.addEventListener('ended', function() {
            postBridge({ event: 'ended' });
          });

          video.addEventListener('loadedmetadata', function() {
            postBridge({
              event: 'resolution',
              width: video.videoWidth || 0,
              height: video.videoHeight || 0,
              duration: video.duration || 0
            });
          });

          ${autoPlay ? "video.play().catch(function(){});" : ""}
        }

        setupVideoElementBridge();
        setInterval(setupVideoElementBridge, 1000);
      })();
    ''';

    try {
      await _webViewController!.runJavaScript(script);
    } catch (e) {
      debugPrint('[VimeoPlayer] Error injecting optimizations: $e');
    }
  }

  void _handlePlayerBridgeMessage(String rawMessage) {
    if (_isDisposed) return;
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is! Map<String, dynamic>) return;

      final event = (decoded['event'] ?? decoded['type'] ?? '').toString().toLowerCase().trim();
      final data = decoded['data'];

      switch (event) {
        case 'timeupdate':
          double? cur;
          double? dur;
          if (data is Map) {
            final s = data['seconds'];
            final d = data['duration'];
            if (s is num) cur = s.toDouble();
            if (d is num) dur = d.toDouble();
          } else {
            final s = decoded['currentTime'] ?? decoded['time'] ?? decoded['seconds'];
            final d = decoded['duration'];
            if (s is num) cur = s.toDouble();
            if (d is num) dur = d.toDouble();
          }
          if (cur != null) {
            _position = cur;
            onPositionChanged?.call(cur);
          }
          if (dur != null && dur > 0 && dur != _duration) {
            _duration = dur;
            onDurationChanged?.call(dur);
          }
          notifyListeners();
          break;

        case 'play':
        case 'playing':
          if (_isPlaying != true) {
            _isPlaying = true;
            onPlayingChanged?.call(true);
            notifyListeners();
          }
          break;

        case 'pause':
          if (_isFullscreenTransition && _isPlaying) {
            debugPrint('[VimeoPlayer] Ignore spurious pause during fullscreen transition');
            play();
            return;
          }
          if (_isPlaying != false) {
            _isPlaying = false;
            onPlayingChanged?.call(false);
            notifyListeners();
          }
          break;

        case 'ended':
          _isPlaying = false;
          onPlayingChanged?.call(false);
          onPlaybackEnded?.call();
          notifyListeners();
          break;

        case 'resolution':
          final w = decoded['width'] ?? (data is Map ? data['width'] : null);
          final h = decoded['height'] ?? (data is Map ? data['height'] : null);
          if (w is num && h is num && w > 0 && h > 0) {
            _detectedWidth = w.toInt();
            _detectedHeight = h.toInt();
            notifyListeners();
          }
          break;

        case 'qualities':
          final rawQualities = decoded['qualities'] ?? (data is Map ? data['qualities'] : null);
          if (rawQualities is List) {
            _updateQualitiesFromBridge(rawQualities);
          }
          break;

        case 'qualitychange':
          final q = (data is Map ? data['quality'] : null) ?? decoded['quality'];
          if (q != null && q.toString().isNotEmpty) {
            final qStr = q.toString().trim();
            _selectedQuality = _availableQualities.firstWhere(
              (item) => item.id == qStr,
              orElse: () => VideoQuality.vimeo(qStr),
            );
            onQualitySelectedChanged?.call(_selectedQuality!);
            notifyListeners();
          }
          break;
      }
    } catch (e) {
      debugPrint('[VimeoPlayer] Bridge message error: $e');
    }
  }

  void _updateQualitiesFromBridge(List<dynamic> rawList) {
    final List<VideoQuality> parsed = [
      const VideoQuality.auto(
        label: 'Auto (Otomatis Vimeo)',
        mode: QualityControlMode.webviewBridge,
      ),
    ];

    for (final item in rawList) {
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

    // Sort descending by height, keeping Auto first
    parsed.sort((a, b) {
      if (a.isAuto) return -1;
      if (b.isAuto) return 1;
      return (b.height ?? 0).compareTo(a.height ?? 0);
    });

    if (parsed.length > 1) {
      _availableQualities = parsed;
      onQualitiesChanged?.call(List.unmodifiable(_availableQualities));
      notifyListeners();
    }
  }

  @visibleForTesting
  void handleBridgeMessageForTesting(String message) {
    _handlePlayerBridgeMessage(message);
  }

  Future<void> play() async {
    _isPlaying = true;
    notifyListeners();
    if (kIsWeb) {
      await _webAdapter?.play();
      return;
    }
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript('''
          (function() {
            var video = document.querySelector('video');
            if (video) video.play().catch(function(){});
            window.postMessage({method: 'play'}, '*');
          })();
        ''');
      } catch (_) {}
    }
  }

  Future<void> pause() async {
    _isPlaying = false;
    notifyListeners();
    if (kIsWeb) {
      await _webAdapter?.pause();
      return;
    }
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript('''
          (function() {
            var video = document.querySelector('video');
            if (video) video.pause();
            window.postMessage({method: 'pause'}, '*');
          })();
        ''');
      } catch (_) {}
    }
  }

  Future<void> seekTo(double seconds) async {
    final clamped = seconds < 0 ? 0.0 : seconds;
    _position = clamped;
    notifyListeners();
    if (kIsWeb) {
      await _webAdapter?.seekTo(clamped);
      return;
    }
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript('''
          (function() {
            var video = document.querySelector('video');
            if (video) video.currentTime = $clamped;
            window.postMessage({method: 'setCurrentTime', value: $clamped}, '*');
          })();
        ''');
      } catch (_) {}
    }
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    _isMuted = _volume == 0;
    notifyListeners();
    if (kIsWeb) {
      await _webAdapter?.setVolume(_volume);
      return;
    }
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript('''
          (function() {
            var video = document.querySelector('video');
            if (video) video.volume = $_volume;
            window.postMessage({method: 'setVolume', value: $_volume}, '*');
          })();
        ''');
      } catch (_) {}
    }
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    notifyListeners();
    if (kIsWeb) {
      await _webAdapter?.setMuted(_isMuted);
      return;
    }
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript('''
          (function() {
            var video = document.querySelector('video');
            if (video) video.muted = ${_isMuted ? "true" : "false"};
          })();
        ''');
      } catch (_) {}
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    notifyListeners();
    if (kIsWeb) {
      await _webAdapter?.setPlaybackSpeed(speed);
      return;
    }
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript('''
          (function() {
            var video = document.querySelector('video');
            if (video) video.playbackRate = $speed;
            window.postMessage({method: 'setPlaybackRate', value: $speed}, '*');
          })();
        ''');
      } catch (_) {}
    }
  }

  Future<void> setQuality(String qualityId) async {
    _selectedQuality = _availableQualities.firstWhere(
      (q) => q.id == qualityId,
      orElse: () => VideoQuality.vimeo(qualityId),
    );
    notifyListeners();
    if (kIsWeb) {
      await _webAdapter?.setQuality(qualityId);
      return;
    }
    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript('''
          (function() {
            window.postMessage({method: 'setQuality', value: '$qualityId'}, '*');
          })();
        ''');
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _webAdapter?.dispose();
    _webAdapter = null;
    _webViewController = null;
    super.dispose();
  }
}
