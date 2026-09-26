import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../../../core/network/app_http_client.dart';
import '../models/video_quality.dart';
import '../services/hls_manifest_parser.dart';
import 'dailymotion_web_adapter/dailymotion_web_adapter.dart';

/// Controller for Dailymotion video player via WebViewController & HTML5 video bridge
class DailymotionPlayerController extends ChangeNotifier {
  final GlobalKey webViewKey = GlobalKey(debugLabel: 'DailymotionWebView');
  WebViewController? _webViewController;
  DailymotionWebAdapter? _webAdapter;
  String _url = '';
  String? _videoId;
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

  // Video Quality state for Dailymotion (populated dynamically from Metadata API / Player)
  List<VideoQuality> _availableQualities = [
    const VideoQuality.auto(
      label: 'Auto (Otomatis Dailymotion)',
      mode: QualityControlMode.webviewBridge,
    ),
  ];
  VideoQuality? _selectedQuality;
  int? _detectedHeight;
  int? _detectedWidth;

  DailymotionPlayerController() {
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
  DailymotionWebAdapter? get webAdapter => _webAdapter;

  /// Builds the embedded Dailymotion player widget on Flutter Web.
  Widget? buildWebWidget() => _webAdapter?.buildPlayerWidget();

  String get url => _url;
  String? get videoId => _videoId;
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

  /// Extracts Dailymotion video ID from various URL formats
  static String? extractVideoId(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final regex = RegExp(
      r'(?:dailymotion\.com/(?:video/|embed/video/)|dai\.ly/|player\.html\?video=)([a-zA-Z0-9]+)',
      caseSensitive: false,
    );
    final match = regex.firstMatch(trimmed);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }

    // Direct video ID string (e.g. x7tgad0, x84sh87)
    if (RegExp(r'^[a-zA-Z0-9]{4,12}$').hasMatch(trimmed)) {
      return trimmed;
    }

    return null;
  }

  /// Extracts quality keys (e.g. ['1080', '720', '480']) from Dailymotion player metadata JSON.
  static List<String> extractQualitiesFromMetadataJson(
    Map<String, dynamic> meta,
  ) {
    final List<String> result = [];
    final qualitiesObj = meta['qualities'];
    if (qualitiesObj is Map) {
      for (final key in qualitiesObj.keys) {
        final kStr = key.toString().trim();
        if (kStr != 'auto' && RegExp(r'^\d+$').hasMatch(kStr)) {
          final entries = qualitiesObj[key];
          if (entries is List && entries.isNotEmpty) {
            result.add(kStr);
          }
        }
      }
    }
    if (result.isEmpty) {
      final streamFormats = meta['stream_formats'];
      if (streamFormats is Map) {
        for (final key in streamFormats.keys) {
          final kStr = key.toString().trim();
          if (kStr != 'auto' && RegExp(r'^\d+$').hasMatch(kStr)) {
            result.add(kStr);
          }
        }
      }
    }
    return result;
  }

  Future<void> _fetchDailymotionMetadataQualities(String? vId) async {
    if (vId == null || vId.isEmpty || _isDisposed) {
      debugPrint('[DailymotionPlayer] _fetchDailymotionMetadataQualities skipped: vId=$vId');
      return;
    }
    try {
      final metaUri = Uri.parse(
        'https://www.dailymotion.com/player/metadata/video/$vId',
      );
      debugPrint('[DailymotionPlayer] Fetching metadata qualities from $metaUri');
      final resp = await AppHttpClient.get(
        metaUri,
        timeout: const Duration(seconds: 12),
        maxRetries: 1,
      );
      debugPrint('[DailymotionPlayer] Metadata response status=${resp.statusCode} len=${resp.body.length}');
      if (_isDisposed || _videoId != vId) return;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) {
          final keys = extractQualitiesFromMetadataJson(decoded);
          debugPrint('[DailymotionPlayer] Extracted metadata keys: $keys');
          if (keys.isNotEmpty) {
            _updateQualitiesFromBridge(keys);
            return;
          }
          // Fallback: if Dailymotion metadata only lists 'auto' with a master .m3u8 URL,
          // fetch and parse the HLS master manifest to get the exact resolution tiers!
          final qualitiesObj = decoded['qualities'];
          if (qualitiesObj is Map && qualitiesObj['auto'] is List) {
            final autoList = qualitiesObj['auto'] as List;
            for (final item in autoList) {
              if (item is Map && item['url'] is String) {
                final manifestUrl = item['url'] as String;
                final hlsQualities =
                    await HlsManifestParser.fetchAndParseQualities(manifestUrl);
                if (_isDisposed || _videoId != vId) return;
                final variantItems = hlsQualities
                    .where((q) => !q.isAuto && q.height != null && q.height! > 0)
                    .map((q) => <String, dynamic>{
                          'id': q.height.toString(),
                          'quality': q.height.toString(),
                          if (q.streamUrl != null) 'streamUrl': q.streamUrl,
                        })
                    .toList();
                if (variantItems.isNotEmpty) {
                  _updateQualitiesFromBridge(variantItems);
                  return;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[DailymotionPlayer] Metadata quality fetch failed: $e');
    }
  }

  /// Loads Dailymotion media URL and sets up webview & player hooks
  Future<void> loadUrl(
    String url, {
    bool autoPlay = false,
    double startSeconds = 0.0,
  }) async {
    _url = url;
    _videoId = extractVideoId(url);
    debugPrint('[DailymotionPlayer] loadUrl(url=$url, videoId=$_videoId)');
    _position = startSeconds;
    _isPlaying = autoPlay;
    _availableQualities = [
      const VideoQuality.auto(
        label: 'Auto (Otomatis Dailymotion)',
        mode: QualityControlMode.webviewBridge,
      ),
    ];
    _selectedQuality = _availableQualities.first;
    _detectedHeight = null;
    _detectedWidth = null;
    notifyListeners();
    onQualitiesChanged?.call(_availableQualities);

    unawaited(_fetchDailymotionMetadataQualities(_videoId));

    if (kIsWeb) {
      if (_videoId == null || _videoId!.isEmpty) {
        onError?.call('ID Video Dailymotion tidak valid.');
        return;
      }
      _webAdapter ??= DailymotionWebAdapter.create(
        onPositionChanged: (pos) {
          if ((pos - _position).abs() >= 0.3) {
            _position = pos;
            notifyListeners();
            onPositionChanged?.call(_position);
          }
        },
        onDurationChanged: (dur) {
          if (dur > 0 && dur != _duration) {
            _duration = dur;
            notifyListeners();
            onDurationChanged?.call(_duration);
          }
        },
        onPlayingChanged: (playing) {
          if (_isPlaying != playing) {
            _isPlaying = playing;
            notifyListeners();
            onPlayingChanged?.call(playing);
          }
        },
        onPlaybackEnded: () {
          _isPlaying = false;
          notifyListeners();
          onPlaybackEnded?.call();
        },
        onError: (err) {
          onError?.call(err);
        },
        onQualitiesChanged: (qualities) {
          _updateQualitiesFromBridge(
            qualities.map((q) => q.id).toList(),
          );
        },
        onQualitySelectedChanged: (quality) {
          _selectedQuality = quality;
          notifyListeners();
          onQualitySelectedChanged?.call(quality);
        },
        onResolutionChanged: (w, h) {
          final normH = VideoQuality.normalizeResolutionHeight(
                width: w,
                height: h,
              ) ??
              h;
          if (normH > 0 && normH != _detectedHeight) {
            _detectedHeight = normH;
            _detectedWidth = w;
            debugPrint(
              '[DailymotionPlayerWeb] Resolution changed: ${w}x$h (norm=${normH}p)',
            );
            notifyListeners();
          }
        },
      );

      await _webAdapter?.load(
        _videoId!,
        autoPlay: autoPlay,
        startSeconds: startSeconds,
      );
      notifyListeners();
      return;
    }

    if (!_isSupportedMobilePlatform) {
      onError?.call('Dailymotion player hanya didukung pada platform Android, iOS, dan Web.');
      return;
    }

    try {
      final targetUri = _resolveTargetUri(url, autoPlay: autoPlay, startSeconds: startSeconds);

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
            'NobarDailymotionPlayer',
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
      onError?.call('Gagal menginisialisasi pemutar Dailymotion: $e');
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

  /// Converts raw URL or video ID to Dailymotion player embed URI
  Uri _resolveTargetUri(
    String rawUrl, {
    required bool autoPlay,
    required double startSeconds,
    String? quality,
  }) {
    final vId = _videoId ?? extractVideoId(rawUrl);
    if (vId != null && vId.isNotEmpty) {
      final startTimeParam = startSeconds > 0 ? '&startTime=${startSeconds.round()}' : '';
      final qualityParam =
          (quality != null && quality.isNotEmpty && quality != 'auto')
              ? '&quality=$quality'
              : '';
      return Uri.parse(
        'https://geo.dailymotion.com/player.html?video=$vId&autoplay=${autoPlay ? 1 : 0}&mute=0&api=postMessage$startTimeParam$qualityParam',
      );
    }
    return Uri.parse(rawUrl.trim());
  }

  /// Injects CSS and JavaScript to optimize player layout and hook into video events
  Future<void> _injectPlayerOptimizations({
    required bool autoPlay,
    required double startSeconds,
  }) async {
    if (_webViewController == null || _isDisposed) return;

    final script = '''
      (function() {
        // 1. Clean UI and ensure full-screen responsive presentation
        var existingStyle = document.getElementById('nobar-dailymotion-style');
        if (!existingStyle) {
          var style = document.createElement('style');
          style.id = 'nobar-dailymotion-style';
          style.textContent = `
            header, nav, footer, .dmp_Header, .dmp_EndScreen, .dmp_AdBreakBanner {
              display: none !important;
            }
            html, body {
              background-color: #000 !important;
              margin: 0 !important;
              padding: 0 !important;
              overflow: hidden !important;
              width: 100% !important;
              height: 100% !important;
            }
            #player, .player-container, .dmp_Container {
              width: 100vw !important;
              height: 100vh !important;
              position: fixed !important;
              top: 0 !important;
              left: 0 !important;
              z-index: 99999 !important;
            }
            video {
              width: 100% !important;
              height: 100% !important;
              object-fit: contain !important;
            }
          `;
          document.head.appendChild(style);
        }

        // 2. Attach video bridge
        function setupVideoBridge() {
          var video = document.querySelector('video');
          if (!video) return;

          if (!video.__nobarAttached) {
            video.__nobarAttached = true;

            ${startSeconds > 0 ? "video.currentTime = $startSeconds;" : ""}
            video.volume = $_volume;
            video.muted = ${_isMuted ? "true" : "false"};
            ${autoPlay ? "video.play().catch(function(){});" : ""}

            video.addEventListener('timeupdate', function() {
              if (window.NobarDailymotionPlayer) {
                window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                  event: 'timeupdate',
                  currentTime: video.currentTime,
                  duration: video.duration || 0
                }));
              }
            });

            video.addEventListener('play', function() {
              if (window.NobarDailymotionPlayer) {
                window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                  event: 'play'
                }));
              }
            });

            video.addEventListener('pause', function() {
              if (window.NobarDailymotionPlayer) {
                window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                  event: 'pause'
                }));
              }
            });

            video.addEventListener('ended', function() {
              if (window.NobarDailymotionPlayer) {
                window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                  event: 'ended'
                }));
              }
            });

            video.addEventListener('durationchange', function() {
              if (window.NobarDailymotionPlayer) {
                window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                  event: 'durationchange',
                  duration: video.duration || 0
                }));
              }
            });

            // 3. Poll Dailymotion Player qualities (Network hook + Metadata API + SDK Promise + DOM)
            function reportMetaObjectQualities(meta) {
              if (!meta || typeof meta !== 'object') return;
              var qKeys = [];
              if (meta.qualities && typeof meta.qualities === 'object') {
                qKeys = Object.keys(meta.qualities).filter(function(k) {
                  return k !== 'auto' && /^\\d+\$/.test(k) && Array.isArray(meta.qualities[k]) && meta.qualities[k].length > 0;
                });
              }
              if (qKeys.length === 0 && meta.stream_formats && typeof meta.stream_formats === 'object') {
                qKeys = Object.keys(meta.stream_formats).filter(function(k) {
                  return k !== 'auto' && /^\\d+\$/.test(k);
                });
              }
              if (qKeys.length > 0 && window.NobarDailymotionPlayer) {
                window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                  event: 'qualities',
                  qualities: qKeys
                }));
              }
            }

            if (!window.__nobarDmHookInstalled) {
              window.__nobarDmHookInstalled = true;
              try {
                if (window.Hls && window.Hls.prototype && typeof window.Hls.prototype.loadSource === 'function') {
                  var origLoadSource = window.Hls.prototype.loadSource;
                  window.Hls.prototype.loadSource = function() {
                    window.__nobarHlsInstance = this;
                    return origLoadSource.apply(this, arguments);
                  };
                }
                var origFetch = window.fetch;
                if (typeof origFetch === 'function') {
                  window.fetch = function() {
                    var p = origFetch.apply(this, arguments);
                    try {
                      var reqUrl = arguments[0] ? String(arguments[0].url || arguments[0]) : '';
                      if (reqUrl.indexOf('/player/metadata/video/') !== -1) {
                        p.then(function(resp) {
                          try {
                            resp.clone().json().then(function(meta) {
                              reportMetaObjectQualities(meta);
                            }).catch(function(){});
                          } catch (_) {}
                        }).catch(function(){});
                      }
                    } catch (_) {}
                    return p;
                  };
                }
              } catch (_) {}
            }

            function pollDailymotionQualities() {
              try {
                if (!window.__nobarHlsInstance && window.Hls && window.Hls.prototype && !window.Hls.prototype.__nobarHooked) {
                  window.Hls.prototype.__nobarHooked = true;
                  var origLS = window.Hls.prototype.loadSource;
                  window.Hls.prototype.loadSource = function() {
                    window.__nobarHlsInstance = this;
                    return origLS.apply(this, arguments);
                  };
                }
                if (window.__nobarHlsInstance && Array.isArray(window.__nobarHlsInstance.levels) && window.__nobarHlsInstance.levels.length > 0) {
                  var hlsList = [];
                  window.__nobarHlsInstance.levels.forEach(function(lv) {
                    var h = lv && (lv.height || lv.width);
                    if (h && h > 0) hlsList.push(String(lv.height || h));
                  });
                  if (hlsList.length > 0 && window.NobarDailymotionPlayer) {
                    window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                      event: 'qualities',
                      qualities: hlsList
                    }));
                  }
                }
                var vId = '${_videoId ?? ""}';
                if (vId && !window.__nobarDmMetaFetched) {
                  window.__nobarDmMetaFetched = true;
                  fetch('https://www.dailymotion.com/player/metadata/video/' + vId)
                    .then(function(r) { return r.json(); })
                    .then(function(meta) {
                      reportMetaObjectQualities(meta);
                    })
                    .catch(function() {});
                }

                if (window.player && typeof window.player.getQualities === 'function') {
                  var list = window.player.getQualities();
                  if (Array.isArray(list) && list.length > 0) {
                    window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                      event: 'qualities',
                      qualities: list
                    }));
                    return;
                  }
                }
                if (window.player && typeof window.player.getState === 'function') {
                  Promise.resolve(window.player.getState()).then(function(state) {
                    if (!state) return;
                    var qList = state.playerQualitiesList || state.qualities;
                    if (Array.isArray(qList) && qList.length > 0 && window.NobarDailymotionPlayer) {
                      window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                        event: 'qualities',
                        qualities: qList
                      }));
                    }
                  }).catch(function() {});
                }

                // DOM fallback
                var domItems = document.querySelectorAll('.dmp_QualityItem, [class*="quality-item"], [data-quality]');
                if (domItems.length > 0) {
                  var domQuals = [];
                  domItems.forEach(function(el) {
                    var raw = (el.getAttribute('data-quality') || el.textContent || '').trim();
                    var m = raw.match(/(\\d{3,4})/);
                    if (m) domQuals.push(m[1]);
                  });
                  if (domQuals.length > 0 && window.NobarDailymotionPlayer) {
                    window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                      event: 'qualities',
                      qualities: domQuals
                    }));
                  }
                }
              } catch(e) {}
            }
            // 4. Track video resolution
            function reportDailymotionResolution() {
              if (video && video.videoHeight > 0) {
                if (video.__nobarLastH !== video.videoHeight || video.__nobarLastW !== video.videoWidth) {
                  video.__nobarLastH = video.videoHeight;
                  video.__nobarLastW = video.videoWidth;
                  if (window.NobarDailymotionPlayer) {
                    window.NobarDailymotionPlayer.postMessage(JSON.stringify({
                      event: 'resolution',
                      height: video.videoHeight,
                      width: video.videoWidth
                    }));
                  }
                }
              }
            }
            video.addEventListener('loadedmetadata', function() {
              reportDailymotionResolution();
              pollDailymotionQualities();
            });
            video.addEventListener('resize', reportDailymotionResolution);
            setInterval(reportDailymotionResolution, 1000);
            setInterval(pollDailymotionQualities, 2500);
            reportDailymotionResolution();
            pollDailymotionQualities();
          }
        }

        setInterval(setupVideoBridge, 600);
        setupVideoBridge();
      })();
    ''';

    try {
      await _webViewController!.runJavaScript(script);
    } catch (_) {}
  }

  void _handlePlayerBridgeMessage(String rawJson) {
    if (_isDisposed) return;
    try {
      final data = jsonDecode(rawJson);
      if (data is Map<String, dynamic>) {
        final event = data['event'] as String? ?? '';
        switch (event) {
          case 'timeupdate':
            final cur = (data['currentTime'] as num?)?.toDouble() ?? 0.0;
            final dur = (data['duration'] as num?)?.toDouble() ?? 0.0;
            if ((cur - _position).abs() >= 0.3) {
              _position = cur;
              notifyListeners();
              onPositionChanged?.call(_position);
            }
            if (dur > 0 && dur != _duration) {
              _duration = dur;
              notifyListeners();
              onDurationChanged?.call(_duration);
            }
            break;
          case 'durationchange':
            final dur = (data['duration'] as num?)?.toDouble() ?? 0.0;
            if (dur > 0 && dur != _duration) {
              _duration = dur;
              notifyListeners();
              onDurationChanged?.call(_duration);
            }
            break;
          case 'resolution':
            final rawH = (data['height'] as num?)?.toInt();
            final rawW = (data['width'] as num?)?.toInt();
            final normH = VideoQuality.normalizeResolutionHeight(
                  width: rawW,
                  height: rawH,
                ) ??
                rawH;
            if (normH != null && normH > 0 && normH != _detectedHeight) {
              _detectedHeight = normH;
              _detectedWidth = rawW;
              debugPrint(
                '[DailymotionPlayer] Resolution changed: ${rawW}x$rawH (norm=${normH}p)',
              );
              notifyListeners();
            }
            break;
          case 'qualities':
            final rawList = data['qualities'];
            if (rawList is List && rawList.isNotEmpty) {
              _updateQualitiesFromBridge(rawList);
            }
            break;
          case 'qualitychange':
            final curQ = data['quality']?.toString();
            if (curQ != null) {
              _selectedQuality = _availableQualities.firstWhere(
                (q) => q.id == curQ,
                orElse: () => VideoQuality.dailymotion(curQ),
              );
              notifyListeners();
              onQualitySelectedChanged?.call(_selectedQuality!);
            }
            break;
          case 'play':
            if (!_isPlaying) {
              _isPlaying = true;
              notifyListeners();
              onPlayingChanged?.call(true);
            }
            break;
          case 'pause':
            if (_isFullscreenTransition && _isPlaying) {
              debugPrint('[DailymotionPlayer] Spurious OS pause ignored during fullscreen transition. Resuming...');
              play();
              break;
            }
            if (_isPlaying) {
              _isPlaying = false;
              notifyListeners();
              onPlayingChanged?.call(false);
            }
            break;
          case 'ended':
            _isPlaying = false;
            notifyListeners();
            onPlaybackEnded?.call();
            break;
        }
      }
    } catch (_) {}
  }

  void _updateQualitiesFromBridge(List<dynamic> list) {
    final Map<String, String> existingStreamUrls = {
      for (final q in _availableQualities)
        if (!q.isAuto && q.streamUrl != null && q.streamUrl!.isNotEmpty)
          q.id: q.streamUrl!,
    };

    final List<VideoQuality> qualities = [
      const VideoQuality.auto(
        label: 'Auto (Otomatis Dailymotion)',
        mode: QualityControlMode.webviewBridge,
      ),
    ];
    final Set<String> seen = {'auto'};

    for (final item in list) {
      if (item is Map) {
        final id = item['id']?.toString() ?? item['quality']?.toString() ?? '';
        final str = id.trim().toLowerCase();
        if (str.isEmpty || seen.contains(str) || str == 'auto') continue;
        seen.add(str);
        final rawStreamUrl =
            item['streamUrl']?.toString() ?? item['url']?.toString();
        final normKey = str.replaceAll(RegExp(r'[^0-9]'), '');
        final streamUrl = (rawStreamUrl != null && rawStreamUrl.isNotEmpty)
            ? rawStreamUrl
            : existingStreamUrls[normKey.isNotEmpty ? normKey : str];
        qualities.add(VideoQuality.dailymotion(str, streamUrl: streamUrl));
      } else {
        final str = item.toString().trim().toLowerCase();
        if (str.isEmpty || seen.contains(str) || str == 'auto') continue;
        seen.add(str);
        final normKey = str.replaceAll(RegExp(r'[^0-9]'), '');
        final streamUrl =
            existingStreamUrls[normKey.isNotEmpty ? normKey : str];
        qualities.add(VideoQuality.dailymotion(str, streamUrl: streamUrl));
      }
    }

    // Sort descending by height
    qualities.sort((a, b) {
      if (a.isAuto) return -1;
      if (b.isAuto) return 1;
      return (b.height ?? 0).compareTo(a.height ?? 0);
    });

    final oldSig = _availableQualities
        .map((q) => '${q.id}:${q.streamUrl ?? ''}')
        .join('|');
    final newSig =
        qualities.map((q) => '${q.id}:${q.streamUrl ?? ''}')
        .join('|');
    if (oldSig == newSig) return;

    _availableQualities = qualities;
    debugPrint(
      '[DailymotionPlayer] Detected qualities: ${_availableQualities.map((q) => q.id).join(', ')}',
    );
    notifyListeners();
    onQualitiesChanged?.call(_availableQualities);
  }

  @visibleForTesting
  void handleBridgeMessageForTesting(String rawJson) => _handlePlayerBridgeMessage(rawJson);

  /// Sets video quality for Dailymotion player
  Future<void> setQuality(String qualityId) async {
    debugPrint('[DailymotionPlayer] setQuality($qualityId)');
    _selectedQuality = _availableQualities.firstWhere(
      (q) => q.id == qualityId,
      orElse: () => VideoQuality.dailymotion(qualityId),
    );
    notifyListeners();
    onQualitySelectedChanged?.call(_selectedQuality!);

    if (kIsWeb) {
      await _webAdapter?.setQuality(qualityId);
      return;
    }

    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript('''
          (function(targetId) {
            try {
              var targetNum = parseInt(targetId, 10);

              // 1. Try Hls.js instance if captured
              if (window.__nobarHlsInstance && Array.isArray(window.__nobarHlsInstance.levels)) {
                if (targetId === 'auto') {
                  window.__nobarHlsInstance.currentLevel = -1;
                  window.__nobarHlsInstance.nextLevel = -1;
                  window.__nobarHlsInstance.loadLevel = -1;
                  return;
                }
                var levels = window.__nobarHlsInstance.levels;
                for (var l = 0; l < levels.length; l++) {
                  if (levels[l].height === targetNum || String(levels[l].height) === targetId) {
                    window.__nobarHlsInstance.currentLevel = l;
                    window.__nobarHlsInstance.nextLevel = l;
                    window.__nobarHlsInstance.loadLevel = l;
                    return;
                  }
                }
              }

              // 2. Persist Dailymotion quality preference in localStorage
              try {
                localStorage.setItem('dmp_quality', targetId === 'auto' ? 'auto' : String(targetId));
              } catch (_) {}

              // 3. Try Dailymotion Player API
              if (window.player) {
                if (typeof window.player.setQuality === 'function') {
                  window.player.setQuality(targetId);
                  return;
                }
                if (typeof window.player.setPlaybackQuality === 'function') {
                  window.player.setPlaybackQuality(targetId);
                  return;
                }
              }

              // 4. Send Dailymotion postMessage API formats (both query-string and JSON)
              window.postMessage('quality=' + targetId, '*');
              window.postMessage(JSON.stringify({ command: 'quality', parameters: [targetId] }), '*');
              window.postMessage(JSON.stringify({ command: 'setQuality', value: targetId }), '*');

              // 5. Try clicking quality buttons in player DOM (opening Settings menu first if needed)
              var selectors = [
                '.dmp_QualityItem',
                '[class*="quality-item"]',
                '[class*="quality_item"]',
                '[data-quality]',
                '[role="menuitemradio"]'
              ];
              function clickMatchingQualityItem() {
                var items = document.querySelectorAll(selectors.join(','));
                for (var i = 0; i < items.length; i++) {
                  var el = items[i];
                  var val = (el.getAttribute('data-quality') || el.textContent || '').toLowerCase().trim();
                  if (val === targetId ||
                      (targetId !== 'auto' && val.indexOf(targetId) !== -1) ||
                      (targetId === 'auto' && (val.indexOf('auto') !== -1 || val.indexOf('otomatis') !== -1))) {
                    el.click();
                    return true;
                  }
                }
                return false;
              }

              if (clickMatchingQualityItem()) return;

              var settingsBtn = document.querySelector(
                '.dmp_SettingsButton, [class*="SettingsButton"], [aria-label*="Setting"], [aria-label*="Quality"], button[title*="Setting"]'
              );
              if (settingsBtn) {
                settingsBtn.click();
                setTimeout(function() {
                  // Open Quality submenu if present
                  var menuRows = document.querySelectorAll('[class*="MenuItem"], [role="menuitem"]');
                  for (var r = 0; r < menuRows.length; r++) {
                    var txt = (menuRows[r].textContent || '').toLowerCase();
                    if (txt.indexOf('quality') !== -1 || txt.indexOf('kualitas') !== -1) {
                      menuRows[r].click();
                      break;
                    }
                  }
                  setTimeout(function() {
                    if (!clickMatchingQualityItem()) {
                      // 6. Fallback: reload Dailymotion embed player with &quality= parameter at current position
                      var video = document.querySelector('video');
                      var curSec = video ? Math.round(video.currentTime || 0) : 0;
                      var urlObj = new URL(window.location.href);
                      if (targetId === 'auto') {
                        urlObj.searchParams.delete('quality');
                      } else {
                        urlObj.searchParams.set('quality', targetId);
                      }
                      if (curSec > 0) {
                        urlObj.searchParams.set('startTime', String(curSec));
                      }
                      urlObj.searchParams.set('autoplay', '1');
                      window.location.replace(urlObj.toString());
                    }
                  }, 100);
                }, 80);
                return;
              }

              // 6. Direct URL reload fallback if no settings button or Hls.js hook handled it
              if (window.location.hostname.indexOf('dailymotion.com') !== -1) {
                var video = document.querySelector('video');
                var curSec = video ? Math.round(video.currentTime || 0) : 0;
                var urlObj = new URL(window.location.href);
                if (targetId === 'auto') {
                  urlObj.searchParams.delete('quality');
                } else {
                  urlObj.searchParams.set('quality', targetId);
                }
                if (curSec > 0) {
                  urlObj.searchParams.set('startTime', String(curSec));
                }
                urlObj.searchParams.set('autoplay', '1');
                window.location.replace(urlObj.toString());
              }
            } catch(e) {}
          })('$qualityId');
        ''');
      } catch (_) {}
    }
  }

  Future<void> play() async {
    _isPlaying = true;
    notifyListeners();

    if (kIsWeb) {
      await _webAdapter?.play();
      return;
    }

    if (_webViewController != null) {
      final platform = _webViewController!.platform;
      if (platform is AndroidWebViewController) {
        try {
          await platform.setMediaPlaybackRequiresUserGesture(false);
        } catch (_) {}
      }
      try {
        await _webViewController!.runJavaScript('''
          (function() {
            var videos = document.querySelectorAll('video');
            if (videos.length > 0) {
              videos.forEach(function(v) {
                var p = v.play();
                if (p !== undefined) {
                  p.catch(function(e) {
                    console.log('[Nobarin Dailymotion] play error:', e);
                    try {
                      if (window.player && typeof window.player.play === 'function') {
                        window.player.play();
                      }
                    } catch (_) {}
                  });
                }
              });
            } else {
              try {
                if (window.player && typeof window.player.play === 'function') {
                  window.player.play();
                }
              } catch (_) {}
            }
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
            var videos = document.querySelectorAll('video');
            videos.forEach(function(v) {
              v.pause();
            });
            try {
              if (window.player && typeof window.player.pause === 'function') {
                window.player.pause();
              }
            } catch (_) {}
          })();
        ''');
      } catch (_) {}
    }
  }

  Future<void> seekTo(double seconds) async {
    _position = seconds < 0 ? 0 : seconds;
    notifyListeners();

    if (kIsWeb) {
      await _webAdapter?.seekTo(seconds);
      return;
    }

    if (_webViewController != null) {
      try {
        await _webViewController!.runJavaScript(
          "var v = document.querySelector('video'); if (v) v.currentTime = $seconds;",
        );
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
        await _webViewController!.runJavaScript(
          "var v = document.querySelector('video'); if (v) v.playbackRate = $speed;",
        );
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
        await _webViewController!.runJavaScript(
          "var v = document.querySelector('video'); if (v) { v.volume = $_volume; v.muted = ($_volume === 0); }",
        );
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
        await _webViewController!.runJavaScript(
          "var v = document.querySelector('video'); if (v) v.muted = !v.muted;",
        );
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    pause();
    if (kIsWeb) {
      _webAdapter?.dispose();
      _webAdapter = null;
    }
    _webViewController = null;
    super.dispose();
  }
}
