import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/video_title_resolver.dart';
import '../../chat/controllers/chat_controller.dart';
import '../../room/controllers/queue_controller.dart';
import '../../room/controllers/sync_controller.dart';

/// Mode operasional untuk In-App Web Browser (Auto-Detect Video & Stream Sniffer)
enum WebBrowserMode {
  /// Default: menampilkan tombol Tonton Sekarang & Tambah Antrean
  general,

  /// Khusus untuk Antrean: hanya aksi "+ Tambahkan ke Antrean"
  queueOnly,

  /// Khusus untuk Buka / Buat Room: tombol "Pilih Video Ini & Buat Room"
  createRoom,

  /// Khusus untuk Ganti Video: tombol "Pilih & Putar Video Ini"
  watchNow,
}

/// Representasi kandidat sumber video/stream yang terdeteksi dari halaman web.
class DetectedWebVideoCandidate {
  final String id;
  final String mediaType; // 'web_browser', 'direct_url', 'youtube', 'bstation', 'dailymotion', 'google_drive'
  final String url;
  final String label;
  final String badge; // e.g. 'Web Player', 'HLS .m3u8', 'MP4 Stream', 'Iframe Embed'
  final int? width;
  final int? height;
  final double? duration;
  final bool isPlaying;
  final bool isIframeEmbed;

  const DetectedWebVideoCandidate({
    required this.id,
    required this.mediaType,
    required this.url,
    required this.label,
    required this.badge,
    this.width,
    this.height,
    this.duration,
    this.isPlaying = false,
    this.isIframeEmbed = false,
  });

  String? get resolutionLabel {
    if (height != null && height! > 0) {
      return '${height}p';
    }
    return null;
  }
}

/// Universal In-App Web Browser dengan Multi-Layer Video & Stream Sniffer.
/// Mendeteksi otomatis ketika pengguna sedang memutar atau melakukan streaming video
/// di situs web mana pun (HTML5 <video>, HLS .m3u8, DASH .mpd, MP4, maupun Embed Iframe).
class WebBrowserSheet extends StatefulWidget {
  final SyncController? syncController;
  final QueueController? queueController;
  final ChatController? chatController;
  final void Function(String type, String url, String title)? onVideoSelected;
  final WebBrowserMode mode;
  final String? initialUrl;

  const WebBrowserSheet({
    super.key,
    this.syncController,
    this.queueController,
    this.chatController,
    this.onVideoSelected,
    this.mode = WebBrowserMode.general,
    this.initialUrl,
  });

  /// Menampilkan [WebBrowserSheet] sebagai modal bottom sheet tinggi penuh.
  static Future<Map<String, String>?> show(
    BuildContext context, {
    SyncController? syncController,
    QueueController? queueController,
    ChatController? chatController,
    void Function(String type, String url, String title)? onVideoSelected,
    WebBrowserMode mode = WebBrowserMode.general,
    String? initialUrl,
  }) {
    return showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      enableDrag: false,
      builder: (ctx) => WebBrowserSheet(
        syncController: syncController,
        queueController: queueController,
        chatController: chatController,
        onVideoSelected: onVideoSelected,
        mode: mode,
        initialUrl: initialUrl,
      ),
    );
  }

  @override
  State<WebBrowserSheet> createState() => _WebBrowserSheetState();
}

class _WebBrowserSheetState extends State<WebBrowserSheet> {
  static const String _defaultHomeUrl = 'https://www.google.com';

  WebViewController? _webViewController;
  WebViewController? _extractorWebViewController;
  final TextEditingController _omniboxController = TextEditingController();
  final TextEditingController _fallbackUrlController = TextEditingController();
  final FocusNode _omniboxFocusNode = FocusNode();

  bool _isLoading = true;
  double _loadProgress = 0.0;
  String _currentUrl = _defaultHomeUrl;
  String _detectedTitle = '';
  String? _detectedThumbnail;
  bool _isVideoActivelyPlaying = false;
  bool _isBannerMinimized = false;
  String? _dismissedPageUrl;
  bool _canPop = false;

  final List<DetectedWebVideoCandidate> _candidates = [];
  Set<String>? _resolvedIframeUrlsField;
  Set<String> get _resolvedIframeUrls =>
      _resolvedIframeUrlsField ??= <String>{};
  String? _selectedCandidateId;
  String? _detectedIframeSrc;

  static const String _mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  bool get _isSupportedMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  DetectedWebVideoCandidate? get _activeCandidate {
    if (_candidates.isEmpty) return null;
    if (_selectedCandidateId != null) {
      for (final c in _candidates) {
        if (c.id == _selectedCandidateId) return c;
      }
    }
    return _candidates.first;
  }

  @override
  void initState() {
    super.initState();
    final startUrl = (widget.initialUrl != null &&
            widget.initialUrl!.trim().isNotEmpty)
        ? _normalizeInputToUrl(widget.initialUrl!)
        : _defaultHomeUrl;
    _currentUrl = startUrl;
    _omniboxController.text = startUrl;

    if (_isSupportedMobilePlatform) {
      _initWebViewController(startUrl);
    } else {
      _isLoading = false;
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    _resolvedIframeUrls.clear();
    _pruneAdCandidates();
    _injectVideoSniffer();
    if (_detectedIframeSrc != null && _detectedIframeSrc!.isNotEmpty) {
      _resolveIframeStreamBackground(_detectedIframeSrc!, _currentUrl);
    }
  }

  @override
  void dispose() {
    _omniboxController.dispose();
    _fallbackUrlController.dispose();
    _omniboxFocusNode.dispose();
    super.dispose();
  }

  String _normalizeInputToUrl(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return _defaultHomeUrl;
    if (trimmed.startsWith('webbrowser://')) {
      return 'https://${trimmed.substring('webbrowser://'.length)}';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    // Check if it looks like a domain/URL (no spaces and has a dot)
    final hasSpace = trimmed.contains(' ');
    final hasDot = trimmed.contains('.');
    if (!hasSpace && hasDot) {
      return 'https://$trimmed';
    }
    // Otherwise treat as a search query
    return 'https://www.google.com/search?q=${Uri.encodeQueryComponent(trimmed)}';
  }

  void _initWebViewController(String startUrl) {
    try {
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
          '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (progress) {
              if (mounted) {
                setState(() {
                  _loadProgress = progress / 100.0;
                  _isLoading = progress < 100;
                });
              }
              if (progress >= 40) {
                _injectVideoSniffer();
              }
            },
            onPageStarted: (url) {
              _onPageNavigated(url, isNewPageStart: true);
              _injectVideoSniffer();
            },
            onPageFinished: (url) {
              _onPageNavigated(url, isNewPageStart: false);
              _injectVideoSniffer();
            },
            onUrlChange: (change) {
              if (change.url != null) {
                _onPageNavigated(change.url!, isNewPageStart: false);
                _injectVideoSniffer();
              }
            },
            onNavigationRequest: (request) {
              final uri = Uri.tryParse(request.url);
              if (uri == null ||
                  (uri.scheme != 'http' && uri.scheme != 'https')) {
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        )
        ..addJavaScriptChannel(
          'NobarinVideoSniffer',
          onMessageReceived: (message) {
            _handleSnifferMessage(message.message);
          },
        );

      final platform = controller.platform;
      if (platform is AndroidWebViewController) {
        platform.setMediaPlaybackRequiresUserGesture(false);
      }

      controller.loadRequest(Uri.parse(startUrl));
      _webViewController = controller;
    } catch (_) {
      _isLoading = false;
    }
  }

  void _onPageNavigated(String url, {required bool isNewPageStart}) {
    if (url.isEmpty) return;
    final previousHost = Uri.tryParse(_currentUrl)?.host ?? '';
    final previousPath = Uri.tryParse(_currentUrl)?.path ?? '';
    final newUri = Uri.tryParse(url);
    final newHost = newUri?.host ?? '';
    final newPath = newUri?.path ?? '';

    _currentUrl = url;
    if (!_omniboxFocusNode.hasFocus) {
      _omniboxController.text = url;
    }

    // Reset candidates if user navigated to a different page
    if (isNewPageStart && (previousHost != newHost || previousPath != newPath)) {
      if (_dismissedPageUrl != null && _dismissedPageUrl != url) {
        _dismissedPageUrl = null;
      }
      if (mounted) {
        setState(() {
          _candidates.clear();
          _resolvedIframeUrls.clear();
          _selectedCandidateId = null;
          _detectedIframeSrc = null;
          _isVideoActivelyPlaying = false;
        });
      }
    }

    // Also check if URL itself is a direct video file or known video platform
    _checkUrlDirectOrKnownPlatform(url);
  }

  void _checkUrlDirectOrKnownPlatform(String url) {
    final lower = url.toLowerCase();
    // Skip search engine results pages
    if (lower.contains('google.com/search') ||
        lower.contains('bing.com/search') ||
        lower.contains('duckduckgo.com')) {
      return;
    }

    // Direct stream URLs navigated to directly
    if (RegExp(r'\.(m3u8|mpd|mp4|webm|mkv|m4v)(\?|$)', caseSensitive: false)
        .hasMatch(lower)) {
      final isHls = lower.contains('.m3u8');
      _upsertCandidate(
        DetectedWebVideoCandidate(
          id: 'direct:$url',
          mediaType: 'direct_url',
          url: url,
          label: isHls
              ? 'Stream HLS Langsung (.m3u8)'
              : 'File Video Langsung',
          badge: isHls ? 'HLS .m3u8' : 'Direct Video',
          isPlaying: true,
        ),
        preferSelect: true,
      );
    }
  }

  /// Menyuntikkan Multi-Layer Video & Stream Sniffer ke halaman aktif:
  /// 1. HTML5 <video> & Shadow DOM Capture-Phase Hook (play, playing, loadedmetadata, timeupdate)
  /// 2. Network Stream Interceptor (window.fetch, XMLHttpRequest, PerformanceObserver) untuk .m3u8 / .mpd / .mp4
  /// 3. Cross-Origin Video <iframe allowfullscreen> Detector
  Future<void> _injectVideoSniffer() async {
    if (_webViewController == null) return;

    const script = r'''
      (function() {
        if (!window.NobarinVideoSniffer) return;

        function cleanPageTitle(raw) {
          if (!raw) return '';
          var s = String(raw).trim();
          s = s.replace(/^Media\s+player\s+/i, '');
          s = s.replace(/^(?:Lk21|Layarkaca21|Nontondrama|Idlix|Dutamovie21|Rebahin)\s+/i, '');
          s = s.replace(/^Nonton\s+(?:Film\s+|Series\s+|Movie\s+|Drama\s+)?/i, '');
          s = s.replace(/\s*(?:Sub(?:title)?\s+Indo(?:nesia)?|Serial\s+Terlengkap|Streaming\s+Film|di\s+Lk21).*$/i, '');
          s = s.replace(/\s*[-|–—]\s*(Watch|Nonton|Streaming|Online|Free|Sub Indo|HD).*$/i, '');
          return s.trim();
        }

        function getBestTitle() {
          var mainPlayer = document.querySelector('#main-player[title], iframe[name*="player" i][title]');
          if (mainPlayer && mainPlayer.getAttribute('title') && mainPlayer.getAttribute('title').trim().length > 3) {
            return cleanPageTitle(mainPlayer.getAttribute('title'));
          }
          var h1 = document.querySelector('h1');
          if (h1 && h1.textContent && h1.textContent.trim().length > 2 && h1.textContent.trim().length < 140) {
            return cleanPageTitle(h1.textContent);
          }
          var og = document.querySelector('meta[property="og:title"]');
          if (og && og.content && og.content.trim()) {
            return cleanPageTitle(og.content);
          }
          var tw = document.querySelector('meta[name="twitter:title"]');
          if (tw && tw.content && tw.content.trim()) {
            return cleanPageTitle(tw.content);
          }
          return cleanPageTitle(document.title || '');
        }

        function getBestThumbnail(videoEl) {
          if (videoEl && videoEl.poster && videoEl.poster.indexOf('http') === 0) {
            return videoEl.poster;
          }
          var ogImg = document.querySelector('meta[property="og:image"]');
          if (ogImg && ogImg.content && ogImg.content.indexOf('http') === 0) {
            return ogImg.content;
          }
          return '';
        }

        function isAdVideoElement(v) {
          if (!v) return false;
          var idCls = ((v.id || '') + ' ' + (v.className || '') + ' ' + (v.getAttribute('name') || '')).toLowerCase();
          if (/\b(videoad|advideo|ad-video|ad_video|preroll|midroll|ima-ad|vjs-ad|jw-ad)\b/i.test(idCls)) {
            return true;
          }
          if (v.closest && v.closest('#adContainer, #adsContainer, .ad-container, .ads-container, .ima-ad-container, [id*="adContainer" i], [id*="videoAd" i]')) {
            return true;
          }
          return false;
        }

        function isAdResourceUrl(u) {
          if (!u || typeof u !== 'string') return false;
          window.__nobarinAdUrls = window.__nobarinAdUrls || {};
          if (window.__nobarinAdUrls[u]) return true;
          try {
            var adVids = document.querySelectorAll('#videoAd, #adContainer video, .ad-container video, [id*="videoAd" i]');
            for (var i = 0; i < adVids.length; i++) {
              var aSrc = adVids[i].currentSrc || adVids[i].src || '';
              if (aSrc) {
                window.__nobarinAdUrls[aSrc] = true;
                if (aSrc === u) return true;
              }
            }
          } catch (_) {}
          return false;
        }

        function isStreamUrl(u) {
          if (!u || typeof u !== 'string') return false;
          if (isAdResourceUrl(u)) return false;
          var lower = u.toLowerCase();
          if (lower.indexOf('blob:') === 0 || lower.indexOf('data:') === 0) return false;
          // Ignore tiny segment chunks (.ts, .m4s, .aac) and ad trackers
          if (/\.(ts|m4s|vtt|srt|jpg|jpeg|png|gif|svg|webp|css|js|woff|ttf)(\?|$)/i.test(lower)) return false;
          if (lower.indexOf('doubleclick.net') !== -1 ||
              lower.indexOf('googlesyndication.com') !== -1 ||
              lower.indexOf('google-analytics') !== -1 ||
              lower.indexOf('videoad') !== -1 ||
              lower.indexOf('/preroll') !== -1) {
            return false;
          }
          return /\.(m3u8|mpd|mp4|webm|m4v|mkv|mov)(\?|#|$)/i.test(lower) ||
                 lower.indexOf('mime=video') !== -1 ||
                 lower.indexOf('content-type=video') !== -1 ||
                 lower.indexOf('/manifest.m3u8') !== -1 ||
                 lower.indexOf('/master.m3u8') !== -1 ||
                 lower.indexOf('/index.m3u8') !== -1 ||
                 lower.indexOf('/playlist.m3u8') !== -1;
        }

        function reportStreamUrl(streamUrl, sourceTag) {
          try {
            if (!isStreamUrl(streamUrl)) return;
            var absUrl = streamUrl;
            try {
              absUrl = new URL(streamUrl, window.location.href).href;
            } catch (_) {}
            if (isAdResourceUrl(absUrl)) return;

            window.__nobarinCapturedStreams = window.__nobarinCapturedStreams || {};
            if (window.__nobarinCapturedStreams[absUrl]) return;
            window.__nobarinCapturedStreams[absUrl] = true;

            var lower = absUrl.toLowerCase();
            var streamType = 'MP4 Stream';
            if (lower.indexOf('.m3u8') !== -1) streamType = 'HLS .m3u8';
            else if (lower.indexOf('.mpd') !== -1) streamType = 'DASH .mpd';
            else if (lower.indexOf('.webm') !== -1) streamType = 'WebM Stream';

            window.NobarinVideoSniffer.postMessage(JSON.stringify({
              type: 'network_stream',
              pageUrl: window.location.href,
              streamUrl: absUrl,
              streamBadge: streamType,
              sourceTag: sourceTag || 'network',
              title: getBestTitle(),
              thumbnail: getBestThumbnail(null)
            }));
          } catch (_) {}
        }

        function collectAllVideos(root) {
          var list = [];
          try {
            var vids = (root || document).querySelectorAll('video');
            for (var i = 0; i < vids.length; i++) list.push(vids[i]);
            var all = (root || document).querySelectorAll('*');
            for (var j = 0; j < all.length; j++) {
              if (all[j].shadowRoot) {
                var sub = collectAllVideos(all[j].shadowRoot);
                for (var k = 0; k < sub.length; k++) list.push(sub[k]);
              }
            }
          } catch (_) {}
          return list;
        }

        function inspectVideos(triggerEvent) {
          try {
            var videos = collectAllVideos(document);
            var bestVideo = null;
            var bestScore = -1;

            for (var i = 0; i < videos.length; i++) {
              var v = videos[i];
              var src = v.currentSrc || v.src || '';
              if (!src) {
                var sourceEl = v.querySelector('source[src]');
                if (sourceEl) src = sourceEl.src || '';
              }

              // Always skip pre-roll / overlay ad video elements (#videoAd, #adContainer, etc.)
              if (isAdVideoElement(v)) {
                if (src) {
                  window.__nobarinAdUrls = window.__nobarinAdUrls || {};
                  window.__nobarinAdUrls[src] = true;
                }
                continue;
              }

              var dur = (v.duration && isFinite(v.duration)) ? v.duration : 0;
              var w = v.videoWidth || (v.getBoundingClientRect ? v.getBoundingClientRect().width : 0) || 0;
              var h = v.videoHeight || (v.getBoundingClientRect ? v.getBoundingClientRect().height : 0) || 0;
              var isPlaying = !v.paused && !v.ended && v.readyState >= 2;

              // Filter out tiny ad/tracker videos (< 20 sec when an iframe player exists on the page)
              var hasMainIframe = !!document.querySelector('iframe#main-player, .main-player iframe, iframe[allowfullscreen]');
              if (dur > 0 && dur <= 20 && hasMainIframe) {
                if (src) {
                  window.__nobarinAdUrls = window.__nobarinAdUrls || {};
                  window.__nobarinAdUrls[src] = true;
                }
                continue;
              }
              if (dur > 0 && dur < 5 && !isPlaying && videos.length > 1) continue;
              if (!src && !isPlaying && v.readyState < 1) continue;

              if (src && isStreamUrl(src)) {
                reportStreamUrl(src, 'video_src');
              }

              var score = 0;
              if (isPlaying) score += 100;
              if (src) score += 30;
              if (dur > 15) score += 40;
              if (w * h >= 40000) score += 25;

              if (score > bestScore) {
                bestScore = score;
                bestVideo = v;
              }
            }

            if (bestVideo) {
              var bSrc = bestVideo.currentSrc || bestVideo.src || '';
              if (!bSrc) {
                var sEl = bestVideo.querySelector('source[src]');
                if (sEl) bSrc = sEl.src || '';
              }
              var bPlaying = !bestVideo.paused && !bestVideo.ended && bestVideo.readyState >= 1;
              var bDur = (bestVideo.duration && isFinite(bestVideo.duration)) ? bestVideo.duration : 0;

              window.NobarinVideoSniffer.postMessage(JSON.stringify({
                type: 'html5_video',
                trigger: triggerEvent || 'poll',
                pageUrl: window.location.href,
                videoSrc: bSrc,
                isBlob: bSrc.indexOf('blob:') === 0,
                isPlaying: bPlaying,
                duration: bDur,
                width: bestVideo.videoWidth || 0,
                height: bestVideo.videoHeight || 0,
                title: getBestTitle(),
                thumbnail: getBestThumbnail(bestVideo)
              }));
            }

            // Scan for prominent video player iframes (#main-player, allowfullscreen, etc.)
            var iframes = document.querySelectorAll('iframe[src]');
            for (var f = 0; f < iframes.length; f++) {
              var ifr = iframes[f];
              var iSrc = ifr.src || '';
              if (!iSrc || iSrc.indexOf('http') !== 0) continue;
              var lowerSrc = iSrc.toLowerCase();
              if (lowerSrc.indexOf('doubleclick') !== -1 ||
                  lowerSrc.indexOf('googlesyndication') !== -1 ||
                  lowerSrc.indexOf('facebook.com/plugins') !== -1 ||
                  lowerSrc.indexOf('recaptcha') !== -1 ||
                  lowerSrc.indexOf('accounts.google.com') !== -1) {
                continue;
              }
              var rect = ifr.getBoundingClientRect ? ifr.getBoundingClientRect() : { width: 0, height: 0 };
              var hasFs = ifr.hasAttribute('allowfullscreen') ||
                          (ifr.getAttribute('allow') || '').indexOf('fullscreen') !== -1 ||
                          (ifr.getAttribute('allow') || '').indexOf('autoplay') !== -1;
              var isNamedPlayer = (ifr.id || '').toLowerCase().indexOf('player') !== -1 ||
                                  (ifr.name || '').toLowerCase().indexOf('player') !== -1;
              var looksLikePlayer = /embed|player|video|stream|watch|play|iframe/i.test(lowerSrc) || isNamedPlayer;
              if (((rect.width >= 200 && rect.height >= 120) || isNamedPlayer) && (hasFs || looksLikePlayer)) {
                window.NobarinVideoSniffer.postMessage(JSON.stringify({
                  type: 'iframe_player',
                  pageUrl: window.location.href,
                  iframeSrc: iSrc,
                  width: Math.round(rect.width),
                  height: Math.round(rect.height),
                  title: getBestTitle(),
                  thumbnail: getBestThumbnail(null)
                }));
                break;
              }
            }

            // Scan PerformanceEntries for any .m3u8 / .mp4 loaded by the browser
            if (window.performance && typeof window.performance.getEntriesByType === 'function') {
              var resources = window.performance.getEntriesByType('resource');
              for (var r = 0; r < resources.length; r++) {
                var rName = resources[r].name;
                if (isStreamUrl(rName)) {
                  reportStreamUrl(rName, 'performance_resource');
                }
              }
            }
          } catch (_) {}
        }

        window.__nobarinInspectVideos = inspectVideos;

        if (!window.__nobarinSnifferInstalled) {
          window.__nobarinSnifferInstalled = true;

          // 1. Capture-phase media events on document (catches all <video> play/playing/loadedmetadata immediately)
          var mediaEvents = ['play', 'playing', 'loadedmetadata', 'canplay'];
          for (var eIdx = 0; eIdx < mediaEvents.length; eIdx++) {
            (function(evName) {
              document.addEventListener(evName, function(ev) {
                if (ev && ev.target && ev.target.tagName === 'VIDEO') {
                  var v = ev.target;
                  if (isAdVideoElement(v)) {
                    var adSrc = v.currentSrc || v.src || '';
                    if (adSrc) {
                      window.__nobarinAdUrls = window.__nobarinAdUrls || {};
                      window.__nobarinAdUrls[adSrc] = true;
                    }
                    return;
                  }
                  var src = v.currentSrc || v.src || '';
                  if (src && isStreamUrl(src)) {
                    reportStreamUrl(src, 'event_' + evName);
                  }
                  if (window.__nobarinInspectVideos) {
                    window.__nobarinInspectVideos(evName);
                  }
                }
              }, true);
            })(mediaEvents[eIdx]);
          }

          // Throttled timeupdate listener in capture phase
          var lastTimeUpdateReport = 0;
          document.addEventListener('timeupdate', function(ev) {
            var now = Date.now();
            if (now - lastTimeUpdateReport > 1500) {
              lastTimeUpdateReport = now;
              if (window.__nobarinInspectVideos) {
                window.__nobarinInspectVideos('timeupdate');
              }
            }
          }, true);

          // 2. Hook window.fetch to catch HLS (.m3u8) / DASH (.mpd) / MP4 requests
          try {
            var origFetch = window.fetch;
            if (typeof origFetch === 'function') {
              window.fetch = function() {
                try {
                  var req = arguments[0];
                  var url = (typeof req === 'string') ? req : (req && req.url ? req.url : '');
                  if (url && isStreamUrl(url)) {
                    reportStreamUrl(url, 'fetch');
                  }
                } catch (_) {}
                return origFetch.apply(this, arguments);
              };
            }
          } catch (_) {}

          // 3. Hook XMLHttpRequest.open to catch HLS.js / Shaka / JWPlayer XHR manifests
          try {
            var origOpen = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method, url) {
              try {
                var u = String(url || '');
                if (u && isStreamUrl(u)) {
                  reportStreamUrl(u, 'xhr');
                }
              } catch (_) {}
              return origOpen.apply(this, arguments);
            };
          } catch (_) {}

          // 4. PerformanceObserver for real-time network resource streaming
          try {
            if (typeof PerformanceObserver === 'function') {
              var perfObs = new PerformanceObserver(function(list) {
                var entries = list.getEntries();
                for (var i = 0; i < entries.length; i++) {
                  if (isStreamUrl(entries[i].name)) {
                    reportStreamUrl(entries[i].name, 'perf_observer');
                  }
                }
              });
              perfObs.observe({ entryTypes: ['resource'] });
            }
          } catch (_) {}

          // 5. Hook HTMLMediaElement.prototype.play so programmatic video.play() is always caught
          try {
            var origPlay = HTMLMediaElement.prototype.play;
            HTMLMediaElement.prototype.play = function() {
              try {
                setTimeout(function() {
                  if (window.__nobarinInspectVideos) {
                    window.__nobarinInspectVideos('prototype_play');
                  }
                }, 150);
              } catch (_) {}
              return origPlay.apply(this, arguments);
            };
          } catch (_) {}

          setInterval(function() {
            if (window.__nobarinInspectVideos) {
              window.__nobarinInspectVideos('interval');
            }
          }, 1500);
        }

        inspectVideos('init');
      })();
    ''';

    try {
      await _webViewController!.runJavaScript(script);
    } catch (_) {}
  }

  bool _isLikelyAdStream(String url, double? duration) {
    final lower = url.toLowerCase();
    if (lower.contains('stopjudi') ||
        lower.contains('donasi.') ||
        lower.contains('videoad') ||
        lower.contains('/preroll') ||
        lower.contains('doubleclick') ||
        lower.contains('googlesyndication')) {
      return true;
    }
    if (duration != null &&
        duration > 0 &&
        duration <= 20 &&
        _detectedIframeSrc != null) {
      return true;
    }
    return false;
  }

  void _pruneAdCandidates() {
    final beforeLen = _candidates.length;
    _candidates.removeWhere((c) => _isLikelyAdStream(c.url, c.duration));
    if (_candidates.length != beforeLen) {
      if (_selectedCandidateId != null &&
          !_candidates.any((c) => c.id == _selectedCandidateId)) {
        _selectedCandidateId =
            _candidates.isNotEmpty ? _candidates.first.id : null;
      }
    }
  }

  void _handleSnifferMessage(String messageText) {
    if (!mounted) return;
    try {
      final decoded = jsonDecode(messageText);
      if (decoded is! Map<String, dynamic>) return;

      final msgType = decoded['type'] as String? ?? '';
      final pageUrl = decoded['pageUrl'] as String? ?? _currentUrl;
      if (pageUrl == _dismissedPageUrl) return;

      _pruneAdCandidates();

      final rawTitle = decoded['title'] as String? ?? '';
      final cleanTitle = VideoTitleResolver.cleanTitle(rawTitle);
      final thumbnail = decoded['thumbnail'] as String? ?? '';

      if (cleanTitle.isNotEmpty && _detectedTitle != cleanTitle) {
        _detectedTitle = cleanTitle;
      } else if (_detectedTitle.isEmpty) {
        final host = Uri.tryParse(pageUrl)?.host.replaceFirst('www.', '') ?? 'Web';
        _detectedTitle = 'Video Web ($host)';
        _resolveTitleBackground(pageUrl);
      }

      if (thumbnail.isNotEmpty) {
        _detectedThumbnail = thumbnail;
      }

      if (msgType == 'network_stream') {
        final streamUrl = decoded['streamUrl'] as String? ?? '';
        final streamBadge = decoded['streamBadge'] as String? ?? 'Direct Stream';
        if (streamUrl.isNotEmpty && !_isLikelyAdStream(streamUrl, null)) {
          // Add direct stream candidate
          _upsertCandidate(
            DetectedWebVideoCandidate(
              id: 'stream:$streamUrl',
              mediaType: 'direct_url',
              url: streamUrl,
              label: 'Stream Langsung ($streamBadge)',
              badge: streamBadge,
              isPlaying: true,
            ),
            preferSelect: true,
          );
          // Also ensure the Web Player page candidate exists as an option
          _upsertCandidate(
            DetectedWebVideoCandidate(
              id: 'webpage:$pageUrl',
              mediaType: 'web_browser',
              url: pageUrl,
              label: 'Web Player Halaman',
              badge: 'Web Player',
              isPlaying: _isVideoActivelyPlaying,
            ),
            preferSelect: false,
          );
        }
      } else if (msgType == 'html5_video') {
        final videoSrc = decoded['videoSrc'] as String? ?? '';
        final isBlob = decoded['isBlob'] == true;
        final isPlaying = decoded['isPlaying'] == true;
        final duration = (decoded['duration'] as num?)?.toDouble();
        final width = (decoded['width'] as num?)?.toInt();
        final height = (decoded['height'] as num?)?.toInt();

        if (_isLikelyAdStream(videoSrc, duration)) {
          return;
        }

        if (isPlaying && !_isVideoActivelyPlaying) {
          _isVideoActivelyPlaying = true;
          // Auto-unminimize banner when user starts playing a video
          _isBannerMinimized = false;
        } else if (isPlaying) {
          _isVideoActivelyPlaying = true;
        }

        // If the <video> has a direct HTTP(S) playable URL (not blob:), offer Direct Stream too
        if (videoSrc.isNotEmpty &&
            !isBlob &&
            (videoSrc.startsWith('http://') || videoSrc.startsWith('https://'))) {
          final isHls = videoSrc.toLowerCase().contains('.m3u8');
          _upsertCandidate(
            DetectedWebVideoCandidate(
              id: 'stream:$videoSrc',
              mediaType: 'direct_url',
              url: videoSrc,
              label: isHls
                  ? 'Stream HLS Langsung (.m3u8)'
                  : 'Stream Video Langsung',
              badge: isHls ? 'HLS .m3u8' : 'Direct Stream',
              width: width,
              height: height,
              duration: duration,
              isPlaying: isPlaying,
            ),
            preferSelect: true,
          );
        }

        // Always register/update the Web Player Bridge candidate for the current page
        _upsertCandidate(
          DetectedWebVideoCandidate(
            id: 'webpage:$pageUrl',
            mediaType: _resolvePlatformMediaType(pageUrl),
            url: pageUrl,
            label: 'Web Player (Sinkron Halaman)',
            badge: isBlob ? 'MSE Web Player' : 'Web Player',
            width: width,
            height: height,
            duration: duration,
            isPlaying: isPlaying,
          ),
          preferSelect: _candidates.isEmpty,
        );
      } else if (msgType == 'iframe_player') {
        final iframeSrc = decoded['iframeSrc'] as String? ?? '';
        final width = (decoded['width'] as num?)?.toInt();
        final height = (decoded['height'] as num?)?.toInt();
        if (iframeSrc.isNotEmpty) {
          _detectedIframeSrc = iframeSrc;
          _pruneAdCandidates();
          // Register page Web Player candidate
          _upsertCandidate(
            DetectedWebVideoCandidate(
              id: 'webpage:$pageUrl',
              mediaType: _resolvePlatformMediaType(pageUrl),
              url: pageUrl,
              label: 'Web Player Halaman',
              badge: 'Web Player',
              width: width,
              height: height,
            ),
            preferSelect: _candidates.isEmpty,
          );
          // Also register the embedded iframe URL directly as a candidate
          _upsertCandidate(
            DetectedWebVideoCandidate(
              id: 'iframe:$iframeSrc',
              mediaType: _resolvePlatformMediaType(iframeSrc),
              url: iframeSrc,
              label: 'Player Embed (Iframe)',
              badge: 'Embed Player',
              width: width,
              height: height,
              isIframeEmbed: true,
            ),
            preferSelect: false,
          );
          // Attempt deep cross-origin stream extraction (e.g. videonode/playcdn .m3u8)
          _resolveIframeStreamBackground(iframeSrc, pageUrl);
        }
      }
    } catch (_) {}
  }

  /// Mengekstrak stream langsung (.m3u8 / .mp4) dari dalam cross-origin player `<iframe>`
  /// (termasuk arsitektur multi-hop seperti videonode -> playcdn -> HLS .m3u8).
  Future<void> _resolveIframeStreamBackground(
    String iframeSrc,
    String pageUrl,
  ) async {
    if (kIsWeb || _resolvedIframeUrls.contains(iframeSrc)) return;
    _resolvedIframeUrls.add(iframeSrc);

    try {
      // 1. Check multi-hop iframe gateway pattern: https://<domain>/iframe3/<host>/<id>
      final gatewayMatch = RegExp(
        r'^(https?://[^/]+)/iframe\d*/([^/?#]+)/([^/?#]+)',
        caseSensitive: false,
      ).firstMatch(iframeSrc);

      if (gatewayMatch != null) {
        final gatewayOrigin = gatewayMatch.group(1)!;
        final serverHost = gatewayMatch.group(2)!;
        final videoId = gatewayMatch.group(3)!;

        try {
          final apiResp = await http
              .post(
                Uri.parse('$gatewayOrigin/api.php'),
                headers: {
                  'User-Agent': _mobileUserAgent,
                  'Content-Type': 'application/x-www-form-urlencoded',
                  'Referer': iframeSrc,
                  'Origin': gatewayOrigin,
                },
                body: 'host=$serverHost&id=$videoId',
              )
              .timeout(const Duration(seconds: 5));

          if (apiResp.statusCode == 200) {
            final apiData = jsonDecode(apiResp.body);
            if (apiData is Map && apiData['embedUrl'] is String) {
              final embedUrl = apiData['embedUrl'] as String;
              await _extractStreamFromEmbedUrl(embedUrl, iframeSrc, pageUrl);
              if (_candidates.any((c) => c.mediaType == 'direct_url')) {
                return;
              }
            }
          }
        } catch (_) {}

        // Fallback: if Dart HTTP client was blocked by Cloudflare (e.g. 403),
        // execute the gateway resolution inside Chromium WebView!
        await _resolveIframeViaHeadlessWebView(iframeSrc, pageUrl);
        return;
      }

      // 2. Direct embed URL inspection
      await _extractStreamFromEmbedUrl(iframeSrc, pageUrl, pageUrl);
      if (!_candidates.any((c) => c.mediaType == 'direct_url')) {
        await _resolveIframeViaHeadlessWebView(iframeSrc, pageUrl);
      }
    } catch (_) {}
  }

  void _ensureExtractorWebViewController() {
    if (!_isSupportedMobilePlatform || _extractorWebViewController != null) {
      return;
    }
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(_mobileUserAgent)
        ..addJavaScriptChannel(
          'NobarinStreamExtractor',
          onMessageReceived: (msg) {
            _handleExtractorMessage(msg.message);
          },
        );
      _extractorWebViewController = controller;
      if (mounted) {
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _resolveIframeViaHeadlessWebView(
    String iframeSrc,
    String pageUrl,
  ) async {
    if (!_isSupportedMobilePlatform) return;
    _ensureExtractorWebViewController();
    final extractor = _extractorWebViewController;
    if (extractor == null) return;

    final gatewayMatch = RegExp(
      r'^(https?://[^/]+)/iframe\d*/([^/?#]+)/([^/?#]+)',
      caseSensitive: false,
    ).firstMatch(iframeSrc);

    if (gatewayMatch != null) {
      final serverHost = gatewayMatch.group(2)!;
      final videoId = gatewayMatch.group(3)!;
      final safePageUrl = pageUrl.replaceAll("'", r"\'");
      final safeIframeSrc = iframeSrc.replaceAll("'", r"\'");
      final html = '''
<!DOCTYPE html><html><head><script>
(function() {
  fetch('/api.php', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: 'host=${Uri.encodeQueryComponent(serverHost)}&id=${Uri.encodeQueryComponent(videoId)}'
  })
  .then(function(r) { return r.json(); })
  .then(function(d) {
    if (d && d.embedUrl && window.NobarinStreamExtractor) {
      window.NobarinStreamExtractor.postMessage(JSON.stringify({
        step: 'embedUrl',
        embedUrl: d.embedUrl,
        referer: '$safeIframeSrc',
        pageUrl: '$safePageUrl'
      }));
    }
  })
  .catch(function() {});
})();
</script></head><body></body></html>
''';
      await extractor.loadHtmlString(html, baseUrl: iframeSrc);
    } else {
      await _resolveEmbedViaHeadlessWebView(iframeSrc, pageUrl);
    }
  }

  Future<void> _resolveEmbedViaHeadlessWebView(
    String embedUrl,
    String pageUrl,
  ) async {
    final extractor = _extractorWebViewController;
    if (extractor == null) return;
    final embedUri = Uri.tryParse(embedUrl);
    if (embedUri == null) return;
    final segments = embedUri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return;
    final slug = segments.last;
    final safePageUrl = pageUrl.replaceAll("'", r"\'");

    final html = '''
<!DOCTYPE html><html><head><script>
(function() {
  fetch('/verify/${Uri.encodeComponent(slug)}')
  .then(function(r) { return r.json(); })
  .then(function(d) {
    if (d && d.fileUrl && window.NobarinStreamExtractor) {
      window.NobarinStreamExtractor.postMessage(JSON.stringify({
        step: 'streamUrl',
        fileUrl: d.fileUrl,
        title: d.title || '',
        poster: d.poster || '',
        pageUrl: '$safePageUrl'
      }));
    }
  })
  .catch(function() {});
})();
</script></head><body></body></html>
''';
    await extractor.loadHtmlString(html, baseUrl: embedUrl);
  }

  Future<void> _handleExtractorMessage(String rawJson) async {
    if (!mounted) return;
    try {
      final data = jsonDecode(rawJson);
      if (data is! Map<String, dynamic>) return;
      final step = data['step'] as String? ?? '';
      final pageUrl = data['pageUrl'] as String? ?? _currentUrl;

      if (step == 'embedUrl') {
        final embedUrl = (data['embedUrl'] as String?)?.trim() ?? '';
        final referer = (data['referer'] as String?)?.trim() ?? pageUrl;
        if (embedUrl.isNotEmpty) {
          await _extractStreamFromEmbedUrl(embedUrl, referer, pageUrl);
          if (!_candidates.any((c) => c.mediaType == 'direct_url')) {
            await _resolveEmbedViaHeadlessWebView(embedUrl, pageUrl);
          }
        }
      } else if (step == 'streamUrl') {
        final fileUrl = (data['fileUrl'] as String?)?.trim() ?? '';
        final title = (data['title'] as String?)?.trim() ?? '';
        final poster = (data['poster'] as String?)?.trim() ?? '';
        if (fileUrl.isNotEmpty) {
          if (title.isNotEmpty) {
            _detectedTitle = VideoTitleResolver.cleanTitle(title);
          }
          if (poster.isNotEmpty && poster.startsWith('http')) {
            _detectedThumbnail = poster;
          }
          final isHls = fileUrl.toLowerCase().contains('.m3u8');
          _upsertCandidate(
            DetectedWebVideoCandidate(
              id: 'stream:$fileUrl',
              mediaType: 'direct_url',
              url: fileUrl,
              label: isHls
                  ? 'Stream HLS Langsung (.m3u8)'
                  : 'Stream Video Langsung',
              badge: isHls ? 'HLS .m3u8' : 'Direct Stream',
              isPlaying: true,
            ),
            preferSelect: true,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _extractStreamFromEmbedUrl(
    String embedUrl,
    String refererUrl,
    String pageUrl,
  ) async {
    final embedUri = Uri.tryParse(embedUrl);
    if (embedUri == null) return;
    final embedOrigin = '${embedUri.scheme}://${embedUri.host}';
    final segments = embedUri.pathSegments.where((s) => s.isNotEmpty).toList();

    // Check /verify/<slug> endpoint (used by playcdn / p2p HLS servers)
    if (segments.isNotEmpty) {
      final slug = segments.last;
      try {
        final verifyResp = await http
            .get(
              Uri.parse('$embedOrigin/verify/${Uri.encodeComponent(slug)}'),
              headers: {
                'User-Agent': _mobileUserAgent,
                'Referer': embedUrl,
                'Origin': embedOrigin,
              },
            )
            .timeout(const Duration(seconds: 6));

        if (verifyResp.statusCode == 200) {
          final verifyJson = jsonDecode(verifyResp.body);
          if (verifyJson is Map && verifyJson['fileUrl'] is String) {
            final fileUrl = (verifyJson['fileUrl'] as String).trim();
            final title = (verifyJson['title'] as String?)?.trim() ?? '';
            final poster = (verifyJson['poster'] as String?)?.trim() ?? '';

            final currentPath = Uri.tryParse(_currentUrl)?.path ?? '';
            final targetPath = Uri.tryParse(pageUrl)?.path ?? '';
            if (fileUrl.isNotEmpty &&
                mounted &&
                (currentPath == targetPath || _currentUrl == pageUrl)) {
              if (title.isNotEmpty) {
                _detectedTitle = VideoTitleResolver.cleanTitle(title);
              }
              if (poster.isNotEmpty && poster.startsWith('http')) {
                _detectedThumbnail = poster;
              }
              final isHls = fileUrl.toLowerCase().contains('.m3u8');
              _upsertCandidate(
                DetectedWebVideoCandidate(
                  id: 'stream:$fileUrl',
                  mediaType: 'direct_url',
                  url: fileUrl,
                  label: isHls
                      ? 'Stream HLS Langsung (.m3u8)'
                      : 'Stream Video Langsung',
                  badge: isHls ? 'HLS .m3u8' : 'Direct Stream',
                  isPlaying: true,
                ),
                preferSelect: true,
              );
              return;
            }
          }
        }
      } catch (_) {}
    }

    // Fallback: scan HTML of embedUrl for direct .m3u8 or .mp4 stream URLs
    try {
      final htmlResp = await http
          .get(
            embedUri,
            headers: {
              'User-Agent': _mobileUserAgent,
              'Referer': refererUrl,
            },
          )
          .timeout(const Duration(seconds: 6));

      final currentPath = Uri.tryParse(_currentUrl)?.path ?? '';
      final targetPath = Uri.tryParse(pageUrl)?.path ?? '';
      if (htmlResp.statusCode == 200 &&
          mounted &&
          (currentPath == targetPath || _currentUrl == pageUrl)) {
        final body = htmlResp.body.replaceAll(r'\/', '/');
        final streamMatch = RegExp(
          r'https?://[^\s"<>\\]+\.(?:m3u8|mpd|mp4)(?:\?[^\s"<>\\]*)?',
          caseSensitive: false,
        ).firstMatch(body);

        if (streamMatch != null) {
          final streamUrl = streamMatch.group(0)!;
          if (!streamUrl.toLowerCase().contains('videoad')) {
            final isHls = streamUrl.toLowerCase().contains('.m3u8');
            _upsertCandidate(
              DetectedWebVideoCandidate(
                id: 'stream:$streamUrl',
                mediaType: 'direct_url',
                url: streamUrl,
                label: isHls
                    ? 'Stream HLS Langsung (.m3u8)'
                    : 'Stream Video Langsung',
                badge: isHls ? 'HLS .m3u8' : 'Direct Stream',
                isPlaying: true,
              ),
              preferSelect: true,
            );
          }
        }
      }
    } catch (_) {}
  }

  /// Jika halaman atau embed merupakan platform yang sudah punya engine khusus di Nobarin,
  /// gunakan tipe platform tersebut; selain itu gunakan `'web_browser'`.
  String _resolvePlatformMediaType(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('youtube.com/watch') ||
        lower.contains('youtu.be/') ||
        lower.contains('youtube.com/embed/')) {
      return 'youtube';
    }
    if (lower.contains('bilibili.tv') ||
        lower.contains('bilibili.com') ||
        lower.contains('b23.tv')) {
      return 'bstation';
    }
    if (lower.contains('dailymotion.com/video') ||
        lower.contains('dai.ly/') ||
        lower.contains('dailymotion.com/embed')) {
      return 'dailymotion';
    }
    if (lower.contains('drive.google.com/file') ||
        lower.contains('docs.google.com/file')) {
      return 'google_drive';
    }
    return 'web_browser';
  }

  void _upsertCandidate(
    DetectedWebVideoCandidate candidate, {
    required bool preferSelect,
  }) {
    if (!mounted) return;
    setState(() {
      final existingIdx = _candidates.indexWhere((c) => c.id == candidate.id);
      if (existingIdx != -1) {
        _candidates[existingIdx] = candidate;
      } else {
        // Put direct streams at the top when preferred, otherwise append
        if (preferSelect) {
          _candidates.insert(0, candidate);
        } else {
          _candidates.add(candidate);
        }
      }
      if (_selectedCandidateId == null || preferSelect) {
        _selectedCandidateId = candidate.id;
      }
    });
  }

  Future<void> _resolveTitleBackground(String url) async {
    try {
      final resolved = await VideoTitleResolver.resolveTitle(
        url,
        mediaType: 'web_browser',
      );
      final clean = VideoTitleResolver.cleanTitle(resolved);
      if (clean.isNotEmpty && mounted && _currentUrl == url) {
        setState(() {
          _detectedTitle = clean;
        });
      }
    } catch (_) {}
  }

  Future<void> _pauseWebViewMedia() async {
    if (_webViewController == null) return;
    try {
      await _webViewController!.runJavaScript(
        "document.querySelectorAll('video').forEach(function(v){ v.pause(); });",
      );
    } catch (_) {}
  }

  void _handleOmniboxSubmitted(String rawValue) {
    final targetUrl = _normalizeInputToUrl(rawValue);
    _omniboxFocusNode.unfocus();
    setState(() {
      _currentUrl = targetUrl;
      _omniboxController.text = targetUrl;
      _dismissedPageUrl = null;
      _candidates.clear();
      _resolvedIframeUrls.clear();
      _selectedCandidateId = null;
      _detectedIframeSrc = null;
      _isVideoActivelyPlaying = false;
    });
    _webViewController?.loadRequest(Uri.parse(targetUrl));
  }

  /// Mengizinkan pengguna memilih halaman saat ini secara manual meskipun video berada di dalam player khusus.
  void _selectCurrentPageManually() {
    if (_currentUrl.isEmpty) return;
    final host = Uri.tryParse(_currentUrl)?.host.replaceFirst('www.', '') ?? 'Web';
    if (_detectedTitle.isEmpty) {
      _detectedTitle = 'Video Web ($host)';
      _resolveTitleBackground(_currentUrl);
    }
    _upsertCandidate(
      DetectedWebVideoCandidate(
        id: 'webpage:$_currentUrl',
        mediaType: _resolvePlatformMediaType(_currentUrl),
        url: _currentUrl,
        label: 'Web Player Halaman Ini',
        badge: 'Web Player',
        isPlaying: true,
      ),
      preferSelect: true,
    );
    setState(() {
      _dismissedPageUrl = null;
      _isBannerMinimized = false;
    });
  }

  void _applyWatchNow() async {
    final candidate = _activeCandidate;
    if (candidate == null) return;

    final syncCtrl = widget.syncController;
    final onVideoSelectedCallback = widget.onVideoSelected;
    if (onVideoSelectedCallback == null &&
        syncCtrl != null &&
        !syncCtrl.canControl) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hanya Host atau Co-Host yang dapat mengganti video di room ini.',
          ),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    final title = _detectedTitle.isNotEmpty ? _detectedTitle : 'Video Web Browser';
    final mediaType = candidate.mediaType;
    final mediaUrl = candidate.url;

    await _pauseWebViewMedia();

    final chatCtrl = widget.chatController;

    _canPop = true;
    if (mounted) {
      Navigator.of(context).pop({
        'type': mediaType,
        'url': mediaUrl,
        'title': title,
      });
    }

    if (onVideoSelectedCallback != null) {
      onVideoSelectedCallback(mediaType, mediaUrl, title);
    } else if (syncCtrl != null) {
      syncCtrl.requestChangeMedia(mediaType, mediaUrl);
      chatCtrl?.sendSystemMessage(
        '${syncCtrl.currentUser.username} memutar video dari Web Browser: "$title"',
      );
    }
  }

  void _applyAddToQueue() {
    final candidate = _activeCandidate;
    if (candidate == null || widget.queueController == null) return;

    final title = _detectedTitle.isNotEmpty ? _detectedTitle : 'Video Web Browser';

    widget.queueController!.addToQueue(
      mediaType: candidate.mediaType,
      mediaUrl: candidate.url,
      title: title,
      thumbnailUrl: _detectedThumbnail,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.playlist_add_check_rounded, color: Colors.black),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '"$title" ditambahkan ke antrean!',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.webBrowserTeal,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _handleManualFallbackSubmit() async {
    final rawUrl = _fallbackUrlController.text.trim();
    if (rawUrl.isEmpty) return;

    final url = _normalizeInputToUrl(rawUrl);
    final mediaType = RegExp(
      r'\.(m3u8|mpd|mp4|webm|mkv|m4v)(\?|$)',
      caseSensitive: false,
    ).hasMatch(url)
        ? 'direct_url'
        : _resolvePlatformMediaType(url);

    final resolved = await VideoTitleResolver.resolveTitle(
      url,
      mediaType: mediaType,
    );
    final clean = VideoTitleResolver.cleanTitle(resolved);
    final title = clean.isNotEmpty ? clean : 'Video Web Browser';

    _upsertCandidate(
      DetectedWebVideoCandidate(
        id: 'manual:$url',
        mediaType: mediaType,
        url: url,
        label: mediaType == 'direct_url' ? 'Stream Langsung' : 'Web Player',
        badge: mediaType == 'direct_url' ? 'Direct Stream' : 'Web Browser',
      ),
      preferSelect: true,
    );
    setState(() {
      _detectedTitle = title;
    });

    _applyWatchNow();
  }

  void _handleManualFallbackQueue() async {
    final rawUrl = _fallbackUrlController.text.trim();
    if (rawUrl.isEmpty) return;

    final url = _normalizeInputToUrl(rawUrl);
    final mediaType = RegExp(
      r'\.(m3u8|mpd|mp4|webm|mkv|m4v)(\?|$)',
      caseSensitive: false,
    ).hasMatch(url)
        ? 'direct_url'
        : _resolvePlatformMediaType(url);

    final resolved = await VideoTitleResolver.resolveTitle(
      url,
      mediaType: mediaType,
    );
    final clean = VideoTitleResolver.cleanTitle(resolved);
    final title = clean.isNotEmpty ? clean : 'Video Web Browser';

    _upsertCandidate(
      DetectedWebVideoCandidate(
        id: 'manual:$url',
        mediaType: mediaType,
        url: url,
        label: mediaType == 'direct_url' ? 'Stream Langsung' : 'Web Player',
        badge: mediaType == 'direct_url' ? 'Direct Stream' : 'Web Browser',
      ),
      preferSelect: true,
    );
    setState(() {
      _detectedTitle = title;
    });

    _applyAddToQueue();
  }

  String _formatDuration(double? seconds) {
    if (seconds == null || seconds <= 0 || !seconds.isFinite) return '';
    final total = seconds.round();
    final hrs = total ~/ 3600;
    final mins = (total % 3600) ~/ 60;
    final secs = total % 60;
    if (hrs > 0) {
      return '$hrs:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSupportedMobilePlatform || _canPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_webViewController != null &&
            await _webViewController!.canGoBack()) {
          await _webViewController!.goBack();
          return;
        }
        if (context.mounted) {
          _pauseWebViewMedia();
          _canPop = true;
          Navigator.of(context).pop();
        }
      },
      child: Container(
        height: MediaQuery.of(context).size.height * 0.94,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Column(
            children: [
              // Top Header + Omnibox Search/URL Bar
              _buildTopBar(context),

              // Progress bar
              if (_isLoading && _loadProgress > 0 && _loadProgress < 1)
                LinearProgressIndicator(
                  value: _loadProgress,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.webBrowserTeal,
                  ),
                  minHeight: 2.5,
                ),

              // Browser Body or Desktop/Web Fallback
              Expanded(
                child: _isSupportedMobilePlatform && _webViewController != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          WebViewWidget(
                            controller: _webViewController!,
                            gestureRecognizers: {
                              Factory<OneSequenceGestureRecognizer>(
                                () => EagerGestureRecognizer(),
                              ),
                            },
                          ),
                          if (_extractorWebViewController != null)
                            Positioned(
                              left: 0,
                              bottom: 0,
                              width: 1,
                              height: 1,
                              child: IgnorePointer(
                                child: Opacity(
                                  opacity: 0.01,
                                  child: WebViewWidget(
                                    controller: _extractorWebViewController!,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      )
                    : _buildUnsupportedPlatformFallback(),
              ),

              // Docked Detection Banner
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: _activeCandidate != null
                    ? _buildDetectionBanner(context)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final String modeTitle;
    switch (widget.mode) {
      case WebBrowserMode.createRoom:
        modeTitle = 'Web Browser • Buat Room';
        break;
      case WebBrowserMode.queueOnly:
        modeTitle = 'Web Browser • Tambah Antrean';
        break;
      case WebBrowserMode.watchNow:
        modeTitle = 'Web Browser • Ganti Video';
        break;
      case WebBrowserMode.general:
        modeTitle = 'Web Browser (Auto-Detect Video)';
        break;
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Row 1: Title, Status Indicator & Navigation Controls
          Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.textPrimary,
                  size: 21,
                ),
                tooltip: 'Tutup',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() => _canPop = true);
                  _pauseWebViewMedia();
                  Navigator.of(context).pop();
                },
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.webBrowserTeal.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.travel_explore_rounded,
                  color: AppColors.webBrowserTeal,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      modeTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      _candidates.isNotEmpty
                          ? '${_candidates.length} sumber video terdeteksi di halaman ini'
                          : 'Putar video di web untuk mendeteksi stream otomatis',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: _candidates.isNotEmpty
                            ? AppColors.accentGreen
                            : AppColors.textSecondary,
                        fontWeight: _candidates.isNotEmpty
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isSupportedMobilePlatform && _webViewController != null) ...[
                // Manual Trigger Button if user wants to pick current page right away
                IconButton(
                  icon: Icon(
                    Icons.radar_rounded,
                    color: _candidates.isNotEmpty
                        ? AppColors.accentGreen
                        : AppColors.webBrowserTeal,
                    size: 19,
                  ),
                  tooltip: 'Pindai / Gunakan Halaman Ini',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _resolvedIframeUrls.clear();
                    _injectVideoSniffer();
                    _selectCurrentPageManually();
                  },
                ),
                IconButton(
                  icon: const Icon(
                    Icons.home_rounded,
                    color: AppColors.textSecondary,
                    size: 19,
                  ),
                  tooltip: 'Beranda Google',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _handleOmniboxSubmitted(_defaultHomeUrl),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppColors.textSecondary,
                    size: 16,
                  ),
                  tooltip: 'Kembali',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    if (await _webViewController!.canGoBack()) {
                      _webViewController!.goBack();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                  tooltip: 'Muat Ulang',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() {
                      _candidates.clear();
                      _resolvedIframeUrls.clear();
                      _selectedCandidateId = null;
                      _detectedIframeSrc = null;
                      _isVideoActivelyPlaying = false;
                    });
                    _webViewController!.reload();
                  },
                ),
              ],
            ],
          ),

          // Row 2: Omnibox Search / URL Input Bar
          if (_isSupportedMobilePlatform) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 38,
              child: TextField(
                controller: _omniboxController,
                focusNode: _omniboxFocusNode,
                textInputAction: TextInputAction.go,
                onSubmitted: _handleOmniboxSubmitted,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                ),
                decoration: InputDecoration(
                  hintText: 'Cari di Google atau ketik alamat situs web...',
                  hintStyle: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 0,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.webBrowserTeal,
                    size: 17,
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_omniboxController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(
                            Icons.clear_rounded,
                            color: AppColors.textMuted,
                            size: 16,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            _omniboxController.clear();
                            _omniboxFocusNode.requestFocus();
                            setState(() {});
                          },
                        ),
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_forward_rounded,
                          color: AppColors.webBrowserTeal,
                          size: 17,
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            _handleOmniboxSubmitted(_omniboxController.text),
                      ),
                    ],
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.webBrowserTeal,
                      width: 1.3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetectionBanner(BuildContext context) {
    final candidate = _activeCandidate;
    if (candidate == null) return const SizedBox.shrink();

    if (_isBannerMinimized) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          border: Border(
            top: BorderSide(
              color: AppColors.webBrowserTeal.withValues(alpha: 0.75),
              width: 1.5,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.webBrowserTeal.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.sensors_rounded,
                  color: AppColors.webBrowserTeal,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _detectedTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _isBannerMinimized = false),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.webBrowserTeal.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.webBrowserTeal.withValues(alpha: 0.65),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Pilih Stream',
                        style: TextStyle(
                          color: AppColors.webBrowserTeal,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 3),
                      Icon(
                        Icons.keyboard_arrow_up_rounded,
                        color: AppColors.webBrowserTeal,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                onPressed: () {
                  setState(() {
                    _dismissedPageUrl = _currentUrl;
                    _candidates.clear();
                    _selectedCandidateId = null;
                  });
                },
                visualDensity: VisualDensity.compact,
                tooltip: 'Abaikan',
              ),
            ],
          ),
        ),
      );
    }

    final durationText = _formatDuration(candidate.duration);
    final resText = candidate.resolutionLabel;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.surfaceHighlight,
            AppColors.surfaceElevated,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          top: BorderSide(
            color: AppColors.webBrowserTeal.withValues(alpha: 0.85),
            width: 2.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.75),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
          BoxShadow(
            color: AppColors.webBrowserTeal.withValues(alpha: 0.2),
            blurRadius: 14,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Video Thumbnail or Radar Icon
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.webBrowserTeal.withValues(alpha: 0.6),
                      width: 1.2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.5),
                    child: _detectedThumbnail != null &&
                            _detectedThumbnail!.isNotEmpty
                        ? Image.network(
                            _detectedThumbnail!,
                            width: 82,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              width: 82,
                              height: 50,
                              color: AppColors.webBrowserTeal
                                  .withValues(alpha: 0.18),
                              child: const Icon(
                                Icons.travel_explore_rounded,
                                color: AppColors.webBrowserTeal,
                                size: 24,
                              ),
                            ),
                          )
                        : Container(
                            width: 82,
                            height: 50,
                            color: AppColors.webBrowserTeal
                                .withValues(alpha: 0.18),
                            child: const Icon(
                              Icons.travel_explore_rounded,
                              color: AppColors.webBrowserTeal,
                              size: 24,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),

                // Video Title & Badges
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accentGreen
                                  .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: AppColors.accentGreen
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isVideoActivelyPlaying
                                      ? Icons.sensors_rounded
                                      : Icons.check_circle_rounded,
                                  color: AppColors.accentGreen,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isVideoActivelyPlaying
                                      ? 'SEDANG MEMUTAR'
                                      : 'VIDEO TERDETEKSI',
                                  style: const TextStyle(
                                    color: AppColors.accentGreen,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.webBrowserTeal
                                  .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              candidate.badge,
                              style: const TextStyle(
                                color: AppColors.webBrowserTeal,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (resText != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryNeon
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                resText,
                                style: const TextStyle(
                                  color: AppColors.primaryNeonLight,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (durationText.isNotEmpty)
                            Text(
                              durationText,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _detectedTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.22,
                        ),
                      ),
                    ],
                  ),
                ),

                // Minimize & Dismiss
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textSecondary,
                        size: 22,
                      ),
                      onPressed: () {
                        setState(() => _isBannerMinimized = true);
                      },
                      tooltip: 'Kecilkan',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _dismissedPageUrl = _currentUrl;
                          _candidates.clear();
                          _selectedCandidateId = null;
                        });
                      },
                      tooltip: 'Abaikan',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),

            // Candidate Selector Chips (if multiple streams/modes detected or iframe available)
            if (_candidates.length > 1 || _detectedIframeSrc != null) ...[
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final item in _candidates) ...[
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          selected: item.id == candidate.id,
                          onSelected: (_) {
                            setState(() => _selectedCandidateId = item.id);
                          },
                          label: Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: item.id == candidate.id
                                  ? Colors.black
                                  : AppColors.textSecondary,
                            ),
                          ),
                          selectedColor: AppColors.webBrowserTeal,
                          backgroundColor: AppColors.surface,
                          side: BorderSide(
                            color: item.id == candidate.id
                                ? AppColors.webBrowserTeal
                                : AppColors.border,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                    if (_detectedIframeSrc != null &&
                        _detectedIframeSrc != _currentUrl)
                      ActionChip(
                        avatar: const Icon(
                          Icons.open_in_full_rounded,
                          size: 13,
                          color: AppColors.secondaryNeon,
                        ),
                        label: const Text(
                          'Masuk ke Iframe Player',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.secondaryNeon,
                          ),
                        ),
                        backgroundColor: AppColors.surface,
                        side: BorderSide(
                          color: AppColors.secondaryNeon.withValues(alpha: 0.5),
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          final target = _detectedIframeSrc!;
                          _handleOmniboxSubmitted(target);
                        },
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Action Buttons per Mode
            if (widget.mode == WebBrowserMode.queueOnly) ...[
              Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ElevatedButton.icon(
                  onPressed: _applyAddToQueue,
                  icon: const Icon(
                    Icons.playlist_add_rounded,
                    size: 22,
                    color: Colors.white,
                  ),
                  label: const Text(
                    '+ Pilih & Tambah ke Antrean',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ] else if (widget.mode == WebBrowserMode.createRoom) ...[
              Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ElevatedButton.icon(
                  onPressed: _applyWatchNow,
                  icon: const Icon(
                    Icons.check_circle_rounded,
                    size: 21,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Pilih Video Ini & Buat Room',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ] else if (widget.mode == WebBrowserMode.watchNow) ...[
              Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ElevatedButton.icon(
                  onPressed: _applyWatchNow,
                  icon: const Icon(
                    Icons.play_circle_fill_rounded,
                    size: 22,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Pilih & Putar Video Ini',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _applyWatchNow,
                        icon: const Icon(
                          Icons.play_arrow_rounded,
                          size: 21,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Pilih & Tonton Sekarang',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.queueController != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton.icon(
                          onPressed: _applyAddToQueue,
                          icon: const Icon(
                            Icons.playlist_add_rounded,
                            size: 19,
                          ),
                          label: const Text(
                            '+ Antrean',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.webBrowserTeal,
                            side: const BorderSide(
                              color: AppColors.webBrowserTeal,
                              width: 1.4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUnsupportedPlatformFallback() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.webBrowserTeal.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.travel_explore_rounded,
                  color: AppColors.webBrowserTeal,
                  size: 48,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Web Browser & Video Sniffer',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Peramban web in-app dengan deteksi stream otomatis tersedia penuh di Android & iOS. Pada perangkat ini, tempelkan URL halaman web atau tautan stream (.m3u8 / .mp4) secara langsung:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _fallbackUrlController,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: 'https://contoh-situs.com/watch/... atau .m3u8',
                  prefixIcon: const Icon(
                    Icons.link_rounded,
                    color: AppColors.webBrowserTeal,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (widget.mode == WebBrowserMode.queueOnly)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _handleManualFallbackQueue,
                    icon: const Icon(Icons.playlist_add_rounded, size: 20),
                    label: const Text(
                      '+ Tambahkan ke Antrean',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.primaryNeonDark,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                )
              else if (widget.mode == WebBrowserMode.createRoom)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _handleManualFallbackSubmit,
                    icon: const Icon(Icons.meeting_room_rounded, size: 20),
                    label: const Text(
                      'Buka Room dengan Video Ini',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.primaryNeonDark,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        onPressed: _handleManualFallbackSubmit,
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: Text(
                          widget.mode == WebBrowserMode.watchNow
                              ? 'Putar Sekarang di Room'
                              : 'Tonton Video Ini',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: AppColors.primaryNeonDark,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    if (widget.queueController != null &&
                        widget.mode != WebBrowserMode.watchNow) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: OutlinedButton.icon(
                          onPressed: _handleManualFallbackQueue,
                          icon: const Icon(
                            Icons.playlist_add_rounded,
                            size: 18,
                          ),
                          label: const Text(
                            '+ Antrean',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            foregroundColor: AppColors.webBrowserTeal,
                            side: const BorderSide(
                              color: AppColors.webBrowserTeal,
                              width: 1.4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
