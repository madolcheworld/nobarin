import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/fullscreen/fullscreen_helper.dart';
import '../../../../core/utils/time_formatter.dart';
import '../../controllers/sync_controller.dart';
import '../../controllers/unified_player_controller.dart';

class UnifiedPlayerView extends StatefulWidget {
  final UnifiedPlayerController player;
  final SyncController syncController;
  final VoidCallback onOpenMediaPicker;
  final VoidCallback? onExit;
  final String? title;
  final bool showTopBar;

  const UnifiedPlayerView({
    super.key,
    required this.player,
    required this.syncController,
    required this.onOpenMediaPicker,
    this.onExit,
    this.title,
    this.showTopBar = true,
  });

  @override
  State<UnifiedPlayerView> createState() => _UnifiedPlayerViewState();
}

class _UnifiedPlayerViewState extends State<UnifiedPlayerView> {
  bool _showControls = true;
  double? _draggingPosition;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_onPlayerChanged);
    _startHideTimerIfNeeded();
  }

  @override
  void didUpdateWidget(UnifiedPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player.removeListener(_onPlayerChanged);
      widget.player.addListener(_onPlayerChanged);
      _startHideTimerIfNeeded();
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    widget.player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  void _onPlayerChanged() {
    if (widget.player.isPlaying) {
      _startHideTimerIfNeeded();
    } else {
      _hideControlsTimer?.cancel();
      if (!_showControls && mounted) {
        setState(() => _showControls = true);
      }
    }
  }

  void _startHideTimerIfNeeded() {
    _hideControlsTimer?.cancel();
    if (widget.player.isPlaying && _draggingPosition == null) {
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && widget.player.isPlaying && _draggingPosition == null) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimerIfNeeded();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.player,
      builder: (context, _) {
        final bool isYouTube = widget.player.mediaType == 'youtube';
        final bool hasMedia = widget.player.mediaUrl.isNotEmpty;
        final bool canControl = widget.syncController.canControl;
        final bool isMobileYouTube = !kIsWeb && isYouTube;
        final String? errorMsg = widget.player.errorMessage;

        Widget playerWidget;
        if (!hasMedia) {
          playerWidget = _buildEmptyPlaceholder();
        } else if (isYouTube && widget.player.ytController != null) {
          playerWidget = YoutubePlayer(
            key: ValueKey('yt_${widget.player.mediaUrl}_${widget.player.ytController.hashCode}'),
            controller: widget.player.ytController!,
            aspectRatio: 16 / 9,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            enableFullScreenOnVerticalDrag: false,
            controlsBuilder: (context, isFullscreen) {
              if (errorMsg != null) {
                return _buildErrorOverlay(context, errorMsg, canControl: canControl);
              }
              return isMobileYouTube
                  ? _buildControlsOverlay(context, isFullscreen: isFullscreen)
                  : const SizedBox.shrink();
            },
          );
        } else if (kIsWeb && widget.player.webVideoWidget != null) {
          playerWidget = widget.player.webVideoWidget!;
        } else if (widget.player.mkVideoController != null) {
          playerWidget = Video(
            controller: widget.player.mkVideoController!,
            controls: NoVideoControls,
          );
        } else {
          playerWidget = _buildEmptyPlaceholder();
        }

        return AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: Colors.black,
            child: Stack(
              children: [
                // Video Content
                Center(child: playerWidget),

                // Non-controller lock indicator badge
                if (hasMedia && !canControl && errorMsg == null)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.accentYellow.withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 14,
                            color: AppColors.accentYellow,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Host Control Mode',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.accentYellow,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Drift / Speed adjustment indicator
                if (hasMedia && widget.player.playbackSpeed != 1.0 && errorMsg == null)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryNeon.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sync_rounded,
                              size: 13, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'Sync (${widget.player.playbackSpeed}x)',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Controls Overlay for media (on mobile YouTube, controlsBuilder renders inside OverlayPortal)
                if (hasMedia && !isMobileYouTube && errorMsg == null)
                  Positioned.fill(
                    child: _buildControlsOverlay(context, isFullscreen: false),
                  ),

                // Error message overlay if playback failed (rendered here for non-mobile-YouTube)
                if (hasMedia && !isMobileYouTube && errorMsg != null)
                  Positioned.fill(
                    child: _buildErrorOverlay(context, errorMsg, canControl: canControl),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlsOverlay(BuildContext context,
      {required bool isFullscreen}) {
    if (!_showControls) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: const SizedBox.expand(),
      );
    }

    final bool isYouTube = widget.player.mediaType == 'youtube';
    final bool canControl = widget.syncController.canControl;
    final double pos = _draggingPosition ?? widget.player.position;
    final double duration = widget.player.duration > 0
        ? widget.player.duration
        : (pos > 0 ? pos * 1.5 : 100);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Background gradient and tap catcher to toggle controls visibility
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
          ),
        ),

        // 2. Center Play / Pause button (strictly bounded to center, does not overlap top bar)
        if (canControl)
          Positioned.fill(
            child: Center(
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.hardEdge,
                child: IconButton(
                  iconSize: isFullscreen ? 56 : 46,
                  padding: const EdgeInsets.all(8),
                  icon: Icon(
                    widget.player.isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_filled_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    if (widget.player.isPlaying) {
                      widget.syncController.requestPause();
                    } else {
                      widget.syncController.requestPlay();
                      _startHideTimerIfNeeded();
                    }
                  },
                ),
              ),
            ),
          ),

        // 3. Top bar: Title + Fullscreen button + Back button
        if (isFullscreen || widget.showTopBar)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: isFullscreen,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    // Back button
                    Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white, size: 22),
                        tooltip: (kIsWeb ? FullscreenHelper.isFullscreen : isFullscreen)
                            ? 'Keluar Fullscreen'
                            : 'Kembali',
                        onPressed: () {
                          if (kIsWeb && FullscreenHelper.isFullscreen) {
                            FullscreenHelper.exitFullscreen();
                            setState(() {});
                          } else if (!kIsWeb && isFullscreen && isYouTube) {
                            widget.player.ytController?.exitFullScreen();
                          } else {
                            widget.onExit?.call();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (widget.title != null)
                      Expanded(
                        child: Text(
                          widget.title!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 4),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    else
                      const Spacer(),
                    const SizedBox(width: 4),
                    // Explicit Exit Room button
                    if (widget.onExit != null)
                      Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: IconButton(
                          icon: const Icon(Icons.exit_to_app_rounded,
                              color: Colors.white, size: 22),
                          tooltip: 'Keluar dari Room',
                          onPressed: () {
                            if (kIsWeb && FullscreenHelper.isFullscreen) {
                              FullscreenHelper.exitFullscreen();
                            } else if (!kIsWeb && isFullscreen && isYouTube) {
                              widget.player.ytController?.exitFullScreen();
                            }
                            widget.onExit?.call();
                          },
                        ),
                      ),
                    // Fullscreen toggle button
                    Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: Icon(
                          (kIsWeb ? FullscreenHelper.isFullscreen : isFullscreen)
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        tooltip:
                            (kIsWeb ? FullscreenHelper.isFullscreen : isFullscreen)
                                ? 'Keluar Fullscreen'
                                : 'Layar Penuh',
                        onPressed: () {
                          if (kIsWeb) {
                            FullscreenHelper.toggleFullscreen();
                            setState(() {});
                          } else if (isYouTube && widget.player.ytController != null) {
                            if (isFullscreen) {
                              widget.player.ytController?.exitFullScreen();
                            } else {
                              widget.player.ytController?.enterFullScreen();
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          // When top bar is suppressed (screen already has AppBar), provide fullscreen toggle at top-right
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: IconButton(
                icon: Icon(
                  (kIsWeb ? FullscreenHelper.isFullscreen : isFullscreen)
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                tooltip: (kIsWeb ? FullscreenHelper.isFullscreen : isFullscreen)
                    ? 'Keluar Fullscreen'
                    : 'Layar Penuh',
                onPressed: () {
                  if (kIsWeb) {
                    FullscreenHelper.toggleFullscreen();
                    setState(() {});
                  } else if (isYouTube && widget.player.ytController != null) {
                    if (isFullscreen) {
                      widget.player.ytController?.exitFullScreen();
                    } else {
                      widget.player.ytController?.enterFullScreen();
                    }
                  }
                },
              ),
            ),
          ),

        // 4. Bottom Timeline & Controls Bar (positioned strictly at bottom)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            top: false,
            bottom: isFullscreen,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Slider
                  if (duration > 0) ...[
                    if (canControl)
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5),
                        ),
                        child: Slider(
                          value: pos.clamp(0.0, duration),
                          min: 0.0,
                          max: duration,
                          onChanged: (val) {
                            _hideControlsTimer?.cancel();
                            setState(() {
                              _draggingPosition = val;
                            });
                          },
                          onChangeEnd: (val) {
                            _draggingPosition = null;
                            widget.syncController.requestSeek(val);
                            _startHideTimerIfNeeded();
                          },
                        ),
                      )
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: (pos / duration).clamp(0.0, 1.0),
                          backgroundColor: AppColors.border,
                          color: AppColors.primaryNeon,
                          minHeight: 3,
                        ),
                      ),
                  ] else ...[
                    const SizedBox(height: 6),
                  ],

                  const SizedBox(height: 2),

                  // Time Label & Quick Actions
                  Row(
                    children: [
                      if (duration <= 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accentRed,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle,
                                  color: Colors.white, size: 7),
                              SizedBox(width: 4),
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Text(
                          '${TimeFormatter.formatDuration(pos)} / ${TimeFormatter.formatDuration(duration)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      const Spacer(),
                      // Muted autoplay hint pill if browser started video muted
                      if (widget.player.isPlaying && widget.player.isMuted)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: () => widget.player.toggleMute(),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.accentYellow
                                    .withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.accentYellow
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.volume_off_rounded,
                                      size: 13,
                                      color: AppColors.accentYellow),
                                  SizedBox(width: 4),
                                  Text(
                                    'Bunyikan Suara',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.accentYellow,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: IconButton(
                          icon: Icon(
                            widget.player.isMuted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                          onPressed: () => widget.player.toggleMute(),
                        ),
                      ),
                      if (canControl)
                        Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          child: IconButton(
                            icon: const Icon(
                              Icons.video_collection_outlined,
                              size: 20,
                              color: Colors.white,
                            ),
                            onPressed: widget.onOpenMediaPicker,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorOverlay(BuildContext context, String errorMsg,
      {required bool canControl}) {
    return Container(
      color: Colors.black.withValues(alpha: 0.88),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.accentRed,
                size: 32,
              ),
              const SizedBox(height: 6),
              const Text(
                'Gagal Memutar Video',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                errorMsg,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: () {
                      widget.player.clearError();
                      widget.player.play();
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('Coba Lagi', style: TextStyle(fontSize: 12)),
                  ),
                  if (canControl) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryNeon,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      onPressed: widget.onOpenMediaPicker,
                      icon: const Icon(Icons.video_library_rounded, size: 14),
                      label: const Text('Pilih Video Lain', style: TextStyle(fontSize: 12)),
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

  Widget _buildEmptyPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.movie_creation_outlined,
            size: 54,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 12),
          const Text(
            'Belum ada media yang dimuat',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: widget.onOpenMediaPicker,
            icon: const Icon(Icons.add_link_rounded, size: 18),
            label: const Text('Pilih Video'),
          ),
        ],
      ),
    );
  }
}
