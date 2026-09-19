import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/p2p_file_stream_service.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../core/utils/fullscreen/fullscreen_helper.dart';
import '../../../../core/utils/time_formatter.dart';
import '../../controllers/sync_controller.dart';
import '../../controllers/unified_player_controller.dart';
import 'bstation_player_widget.dart';
import 'dailymotion_player_widget.dart';
import 'video_quality_sheet.dart';

class UnifiedPlayerView extends StatefulWidget {
  final UnifiedPlayerController player;
  final SyncController syncController;
  final VoidCallback onOpenMediaPicker;
  final VoidCallback? onExit;
  final String? title;
  final bool showTopBar;
  final bool isPipMode;

  const UnifiedPlayerView({
    super.key,
    required this.player,
    required this.syncController,
    required this.onOpenMediaPicker,
    this.onExit,
    this.title,
    this.showTopBar = true,
    this.isPipMode = false,
  });

  @override
  State<UnifiedPlayerView> createState() => _UnifiedPlayerViewState();
}

class _UnifiedPlayerViewState extends State<UnifiedPlayerView> {
  final ValueNotifier<bool> _showControlsNotifier = ValueNotifier<bool>(true);
  bool get _showControls => _showControlsNotifier.value;
  set _showControls(bool val) => _showControlsNotifier.value = val;

  final ValueNotifier<double?> _draggingPositionNotifier = ValueNotifier<double?>(null);
  double? get _draggingPosition => _draggingPositionNotifier.value;
  set _draggingPosition(double? val) => _draggingPositionNotifier.value = val;

  final ValueNotifier<bool> _leftDoubleTapNotifier = ValueNotifier<bool>(false);
  bool get _leftDoubleTapActive => _leftDoubleTapNotifier.value;
  set _leftDoubleTapActive(bool val) => _leftDoubleTapNotifier.value = val;

  final ValueNotifier<bool> _rightDoubleTapNotifier = ValueNotifier<bool>(false);
  bool get _rightDoubleTapActive => _rightDoubleTapNotifier.value;
  set _rightDoubleTapActive(bool val) => _rightDoubleTapNotifier.value = val;

  Timer? _hideControlsTimer;
  bool _lastIsPlaying = false;
  Timer? _doubleTapTimer;

  @override
  void initState() {
    super.initState();
    _lastIsPlaying = widget.player.isPlaying;
    widget.player.addListener(_onPlayerChanged);
    widget.syncController.addListener(_onSyncChanged);
    if (widget.player.isPlaying) {
      _startHideTimerIfNeeded();
    }
  }

  void _onSyncChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(UnifiedPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player.removeListener(_onPlayerChanged);
      _lastIsPlaying = widget.player.isPlaying;
      widget.player.addListener(_onPlayerChanged);
      if (widget.player.isPlaying) {
        _startHideTimerIfNeeded();
      }
    }
    if (oldWidget.syncController != widget.syncController) {
      oldWidget.syncController.removeListener(_onSyncChanged);
      widget.syncController.addListener(_onSyncChanged);
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _doubleTapTimer?.cancel();
    _showControlsNotifier.dispose();
    _draggingPositionNotifier.dispose();
    _leftDoubleTapNotifier.dispose();
    _rightDoubleTapNotifier.dispose();
    widget.player.removeListener(_onPlayerChanged);
    widget.syncController.removeListener(_onSyncChanged);
    super.dispose();
  }

  void _onDoubleTapLeft() {
    if (!widget.syncController.canControl) return;
    AppHaptics.selection();
    final target = (widget.player.position - 10).clamp(0.0, widget.player.duration);
    widget.syncController.requestSeek(target);
    setState(() {
      _leftDoubleTapActive = true;
      _rightDoubleTapActive = false;
    });
    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _leftDoubleTapActive = false);
    });
  }

  void _onDoubleTapRight() {
    if (!widget.syncController.canControl) return;
    AppHaptics.selection();
    final target = (widget.player.position + 10).clamp(0.0, widget.player.duration);
    widget.syncController.requestSeek(target);
    setState(() {
      _rightDoubleTapActive = true;
      _leftDoubleTapActive = false;
    });
    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _rightDoubleTapActive = false);
    });
  }

  void _onPlayerChanged() {
    final bool currentIsPlaying = widget.player.isPlaying;
    if (currentIsPlaying != _lastIsPlaying) {
      _lastIsPlaying = currentIsPlaying;
      if (currentIsPlaying) {
        // Playback transitioned to playing: auto-hide after 1.8s (preserves faster timer if already set)
        _startHideTimerIfNeeded();
      } else {
        // Playback transitioned to paused: cancel hide timer and reveal controls
        _hideControlsTimer?.cancel();
        if (!_showControls && mounted) {
          setState(() => _showControls = true);
        }
      }
    }
  }

  void _startHideTimerIfNeeded({
    Duration duration = const Duration(milliseconds: 3000),
    bool reset = false,
    bool assumePlaying = false,
  }) {
    if (!reset && _hideControlsTimer != null && _hideControlsTimer!.isActive) {
      return;
    }
    _hideControlsTimer?.cancel();
    final bool playing = assumePlaying || widget.player.isPlaying;
    if (playing && _draggingPosition == null) {
      _hideControlsTimer = Timer(duration, () {
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
    debugPrint('[UnifiedPlayerView] _toggleControls: now $_showControls, isPlaying: ${widget.player.isPlaying}');
    if (_showControls) {
      if (widget.player.isPlaying) {
        _startHideTimerIfNeeded(reset: true);
      }
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  Widget _buildSyncStatusBadge({bool isCompact = false}) {
    final status = widget.syncController.syncStatusLabel;
    final driftMs = (widget.syncController.currentDriftSeconds * 1000).round();
    final Color dotColor;
    final String label;

    switch (status) {
      case 'synced':
        dotColor = const Color(0xFF00E676);
        label = isCompact ? '±${driftMs}ms' : 'Sinkron (${driftMs}ms)';
        break;
      case 'adjusting':
        dotColor = const Color(0xFFFFD600);
        label = isCompact ? 'Slew' : 'Slewing (${driftMs}ms)';
        break;
      case 'seeking':
        dotColor = const Color(0xFF2979FF);
        label = 'Syncing';
        break;
      default:
        dotColor = const Color(0xFF9E9E9E);
        label = isCompact ? '...' : 'Menghubungkan';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dotColor.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: dotColor.withValues(alpha: 0.6),
                  blurRadius: 3,
                  spreadRadius: 0.5,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.player,
      builder: (context, _) {
        final bool hasMedia = widget.player.mediaUrl.isNotEmpty;
        final bool canControl = widget.syncController.canControl;
        final String? errorMsg = widget.player.errorMessage;
        final bool isFs = widget.player.isFullscreen;

        Widget playerWidget;
        if (!hasMedia) {
          playerWidget = _buildEmptyPlaceholder();
        } else if (widget.player.mediaType == 'youtube' &&
            widget.player.ytController != null) {
          playerWidget = YoutubePlayer(
            controller: widget.player.ytController!,
            aspectRatio: 16 / 9,
            enableFullScreenOnVerticalDrag: false,
            autoFullScreen: false,
            controlsBuilder: (context, isFullscreen) => PointerInterceptor(
              intercepting: true,
              child: _buildControlsOverlay(context, isFullscreen: isFullscreen || isFs),
            ),
          );
        } else if (widget.player.mediaType == 'bstation' &&
            widget.player.bstationController != null) {
          playerWidget = BstationPlayerWidget(
            controller: widget.player.bstationController!,
            aspectRatio: 16 / 9,
          );
        } else if (widget.player.mediaType == 'dailymotion' &&
            widget.player.dailymotionController != null) {
          playerWidget = DailymotionPlayerWidget(
            controller: widget.player.dailymotionController!,
            aspectRatio: 16 / 9,
          );
        } else if (kIsWeb && widget.player.webVideoWidget != null) {
          playerWidget = widget.player.webVideoWidget!;
        } else if (widget.player.mkVideoController != null) {
          playerWidget = Video(
            controller: widget.player.mkVideoController!,
            controls: NoVideoControls,
            fit: BoxFit.contain,
          );
        } else {
          playerWidget = _buildEmptyPlaceholder();
        }

        final Widget videoContainer = Container(
          color: Colors.black,
          child: Stack(
            children: [
              // Video Content
              Center(child: playerWidget),

              // Controls Overlay for media (for non-YouTube players; YouTube renders via controlsBuilder)
              if (hasMedia &&
                  widget.player.mediaType != 'youtube' &&
                  errorMsg == null &&
                  !widget.isPipMode)
                Positioned.fill(
                  child: PointerInterceptor(
                    intercepting: true,
                    child: _buildControlsOverlay(context, isFullscreen: isFs),
                  ),
                ),

              // Web Autoplay Muted Indicator / Unmute Prompt Badge
              if (hasMedia &&
                  kIsWeb &&
                  widget.player.isMuted &&
                  widget.player.isPlaying &&
                  errorMsg == null &&
                  !widget.isPipMode)
                Positioned(
                  bottom: _showControls ? 64 : 16,
                  left: 16,
                  child: PointerInterceptor(
                    child: GestureDetector(
                      onTap: () {
                        AppHaptics.selection();
                        widget.player.unmute();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryNeon.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.volume_off_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Suara dibisukan • Ketuk untuk bunyikan',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Error message overlay if playback failed
              if (hasMedia && errorMsg != null)
                Positioned.fill(
                  child: _buildErrorOverlay(
                    context,
                    errorMsg,
                    canControl: canControl,
                  ),
                ),
            ],
          ),
        );

        if (isFs) {
          return videoContainer;
        }

        return AspectRatio(aspectRatio: 16 / 9, child: videoContainer);
      },
    );
  }

  Widget _buildControlsOverlay(
    BuildContext context, {
    required bool isFullscreen,
  }) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _showControlsNotifier,
        _draggingPositionNotifier,
        _leftDoubleTapNotifier,
        _rightDoubleTapNotifier,
        widget.player,
        widget.syncController,
      ]),
      builder: (context, _) {
        final bool isFs = isFullscreen || widget.player.isFullscreen;
        final bool canControl = widget.syncController.canControl;
        final double pos = _draggingPosition ?? widget.player.position;
        final double duration = widget.player.duration > 0
            ? widget.player.duration
            : (pos > 0 ? pos * 1.5 : 100);

        return Stack(
          fit: StackFit.expand,
      children: [
        // 0. Base tap and double-tap targets (Seek -10s on left, Seek +10s on right)
        Positioned.fill(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    debugPrint('[UnifiedPlayerView] left half tapped');
                    _toggleControls();
                  },
                  onDoubleTap: _onDoubleTapLeft,
                  child: Container(color: Colors.transparent),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    debugPrint('[UnifiedPlayerView] right half tapped');
                    _toggleControls();
                  },
                  onDoubleTap: _onDoubleTapRight,
                  child: Container(color: Colors.transparent),
                ),
              ),
            ],
          ),
        ),

        // 0b. Double-Tap Seek Visual Feedback Badges
        if (_leftDoubleTapActive)
          Positioned(
            left: 32,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.secondaryNeon.withValues(alpha: 0.5),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fast_rewind_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 4),
                    Text(
                      '-10s',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_rightDoubleTapActive)
          Positioned(
            right: 32,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.secondaryNeon.withValues(alpha: 0.5),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '+10s',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.fast_forward_rounded, color: Colors.white, size: 22),
                  ],
                ),
              ),
            ),
          ),

        // 0c. Non-controller lock indicator badge
        if (!canControl && !widget.isPipMode)
          Positioned(
            top: 12,
            left: 12,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
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
          ),

        // 0d. Drift / Speed adjustment indicator
        if (widget.player.playbackSpeed != 1.0 && !widget.isPipMode)
          Positioned(
            top: 12,
            right: 12,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryNeon.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.sync_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
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
          ),

        // 1. Smooth animated overlay with interactive controls
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_showControls,
            child: AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: Stack(
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

                  // 2. Center Controls: Seek -10s, Play/Pause, Seek +10s (YouTube Style)
                  if (canControl)
                    Positioned.fill(
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Seek -10s
                            Material(
                              color: Colors.black.withValues(alpha: 0.45),
                              shape: const CircleBorder(),
                              clipBehavior: Clip.hardEdge,
                              child: IconButton(
                                iconSize: isFs ? 36 : 28,
                                padding: EdgeInsets.all(isFs ? 10 : 8),
                                icon: const Icon(
                                  Icons.replay_10_rounded,
                                  color: Colors.white,
                                ),
                                tooltip: 'Mundur 10 detik',
                                onPressed: () {
                                  final target = (widget.player.position - 10)
                                      .clamp(0.0, widget.player.duration);
                                  widget.syncController.requestSeek(target);
                                  _startHideTimerIfNeeded(
                                    duration: const Duration(milliseconds: 1800),
                                    reset: true,
                                  );
                                },
                              ),
                            ),
                            SizedBox(width: isFs ? 32 : 20),

                            // Center Play / Pause button
                            Container(
                              width: isFs ? 80 : 62,
                              height: isFs ? 80 : 62,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.65),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  width: 2.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primaryNeon.withValues(
                                      alpha: 0.45,
                                    ),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                shape: const CircleBorder(),
                                clipBehavior: Clip.hardEdge,
                                child: IconButton(
                                  iconSize: isFs ? 52 : 40,
                                  padding: EdgeInsets.zero,
                                  icon: Icon(
                                    widget.player.isPlaying
                                        ? Icons.pause_circle_filled_rounded
                                        : Icons.play_circle_filled_rounded,
                                    color: Colors.white,
                                  ),
                                  onPressed: () {
                                    if (widget.player.isPlaying) {
                                      _hideControlsTimer?.cancel();
                                      setState(() => _showControls = true);
                                      widget.syncController.requestPause();
                                    } else {
                                      widget.syncController.requestPlay();
                                      _startHideTimerIfNeeded(
                                        duration: const Duration(
                                          milliseconds: 3000,
                                        ),
                                        reset: true,
                                        assumePlaying: true,
                                      );
                                    }
                                  },
                                ),
                              ),
                            ),
                            SizedBox(width: isFs ? 32 : 20),

                            // Seek +10s
                            Material(
                              color: Colors.black.withValues(alpha: 0.45),
                              shape: const CircleBorder(),
                              clipBehavior: Clip.hardEdge,
                              child: IconButton(
                                iconSize: isFs ? 36 : 28,
                                padding: EdgeInsets.all(isFs ? 10 : 8),
                                icon: const Icon(
                                  Icons.forward_10_rounded,
                                  color: Colors.white,
                                ),
                                tooltip: 'Maju 10 detik',
                                onPressed: () {
                                  final target = (widget.player.position + 10)
                                      .clamp(0.0, widget.player.duration);
                                  widget.syncController.requestSeek(target);
                                  _startHideTimerIfNeeded(
                                    duration: const Duration(milliseconds: 1800),
                                    reset: true,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 3. Top bar: Title + Fullscreen button + Back button
                  if (isFs || widget.showTopBar)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        top: isFs,
                        bottom: false,
                        left: isFs,
                        right: isFs,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isFs ? 12 : 8,
                            vertical: isFs ? 6 : 4,
                          ),
                          child: Row(
                            children: [
                              // Back button
                              Material(
                                color: Colors.transparent,
                                shape: const CircleBorder(),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.arrow_back_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                  tooltip:
                                      (kIsWeb
                                          ? FullscreenHelper.isFullscreen
                                          : isFs)
                                      ? 'Keluar Fullscreen'
                                      : 'Kembali',
                                  onPressed: () {
                                    if (isFs) {
                                      widget.player.exitFullscreen();
                                    } else {
                                      widget.onExit?.call();
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 4),
                              if (widget.title != null)
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          widget.title!,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black,
                                                blurRadius: 4,
                                              ),
                                            ],
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (widget.player.isLocalFile) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.purple.withValues(alpha: 0.5),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: Colors.purpleAccent,
                                              width: 0.8,
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.folder_rounded,
                                                  size: 10, color: Colors.white),
                                              SizedBox(width: 3),
                                              Text(
                                                'File Lokal',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ] else if (widget.player.isP2PStream) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryNeon
                                                .withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: AppColors.primaryNeon,
                                              width: 0.8,
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.stream_rounded,
                                                  size: 10,
                                                  color: AppColors.primaryNeon),
                                              SizedBox(width: 3),
                                              Text(
                                                'P2P Stream',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.primaryNeon,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              if ((P2PFileStreamService.instance.activeMetadata != null ||
                                      widget.player.isLocalFile ||
                                      widget.player.mediaUrl.startsWith('blob:')) &&
                                  !P2PFileStreamService.instance.isHosting) ...[
                                const SizedBox(width: 6),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () async {
                                      final picked = await FilePicker.pickFile(
                                        type: FileType.video,
                                      );
                                      if (picked != null) {
                                        final path = kIsWeb
                                            ? (picked.xFile.path.isNotEmpty
                                                ? picked.xFile.path
                                                : picked.uri.toString())
                                            : (picked.path ?? '');
                                        if (path.isNotEmpty) {
                                          if (!kIsWeb) {
                                            P2PFileStreamService.instance
                                                .setLocalOverride(path);
                                          }
                                          await widget.player.loadMedia(
                                            'direct_url',
                                            path,
                                            autoPlay: widget.player.isPlaying,
                                            startSeconds: widget.player.position,
                                          );
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Memutar salinan file lokal (Syncplay)'),
                                                backgroundColor:
                                                    AppColors.primaryNeon,
                                              ),
                                            );
                                          }
                                        }
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.4),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: Colors.white24, width: 0.8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            P2PFileStreamService
                                                    .instance.hasLocalOverride
                                                ? Icons.check_circle_outline_rounded
                                                : Icons.folder_open_rounded,
                                            size: 12,
                                            color: P2PFileStreamService
                                                    .instance.hasLocalOverride
                                                ? AppColors.primaryNeon
                                                : Colors.white,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            P2PFileStreamService
                                                    .instance.hasLocalOverride
                                                ? 'File Lokal Aktif'
                                                : 'Punya File?',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: P2PFileStreamService
                                                      .instance.hasLocalOverride
                                                  ? AppColors.primaryNeon
                                                  : Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
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
                      bottom: isFs,
                      left: isFs,
                      right: isFs,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          isFs ? 16 : 12,
                          0,
                          isFs ? 16 : 12,
                          isFs ? 8 : 2,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 1. Time Label & Quick Actions Row
                            Row(
                              children: [
                                // Bottom bar Play / Pause button
                                Material(
                                  color: Colors.transparent,
                                  shape: const CircleBorder(),
                                  child: IconButton(
                                    icon: Icon(
                                      widget.player.isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      size: 22,
                                      color: canControl
                                          ? Colors.white
                                          : Colors.white38,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    tooltip: canControl
                                        ? (widget.player.isPlaying
                                            ? 'Pause'
                                            : 'Play')
                                        : 'Mode Kontrol Host (Hanya Host)',
                                    onPressed: () {
                                      if (!canControl) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Hanya Host yang dapat memutar atau mem-pause video.',
                                            ),
                                            duration: Duration(seconds: 2),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                        return;
                                      }
                                      if (widget.player.isPlaying) {
                                        _hideControlsTimer?.cancel();
                                        setState(() => _showControls = true);
                                        widget.syncController.requestPause();
                                      } else {
                                        widget.syncController.requestPlay();
                                        _startHideTimerIfNeeded(
                                          duration: const Duration(
                                            milliseconds: 3000,
                                          ),
                                          reset: true,
                                          assumePlaying: true,
                                        );
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 4),
                                if (duration <= 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.accentRed,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          color: Colors.white,
                                          size: 7,
                                        ),
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
                                  Flexible(
                                    child: Text(
                                      '${TimeFormatter.formatDuration(pos)} / ${TimeFormatter.formatDuration(duration)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black,
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                const SizedBox(width: 6),
                                const Spacer(),
                                if (widget.player.isLoaded) ...[
                                  _buildSyncStatusBadge(isCompact: !isFs),
                                  const SizedBox(width: 4),
                                ],
                                Material(
                                  color: Colors.transparent,
                                  shape: const CircleBorder(),
                                  child: IconButton(
                                    icon: Icon(
                                      widget.player.isMuted
                                          ? Icons.volume_off_rounded
                                          : Icons.volume_up_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    tooltip: widget.player.isMuted
                                        ? 'Nyalakan Suara'
                                        : 'Bisukan Suara',
                                    onPressed: () {
                                      widget.player.toggleMute();
                                      if (widget.player.isPlaying) {
                                        _startHideTimerIfNeeded(reset: true);
                                      }
                                    },
                                  ),
                                ),
                                if (widget.player.isLoaded) ...[
                                  const SizedBox(width: 4),
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () {
                                        AppHaptics.selection();
                                        VideoQualitySheet.show(
                                          context,
                                          player: widget.player,
                                        );
                                        if (widget.player.isPlaying) {
                                          _startHideTimerIfNeeded(reset: true);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.35),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(
                                            color: widget.player.selectedQuality != null &&
                                                    !widget.player.selectedQuality!.isAuto
                                                ? AppColors.primaryNeon.withValues(alpha: 0.6)
                                                : Colors.white.withValues(alpha: 0.25),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.tune_rounded,
                                              size: 12,
                                              color: widget.player.selectedQuality != null &&
                                                      !widget.player.selectedQuality!.isAuto
                                                  ? AppColors.primaryNeon
                                                  : Colors.white,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              widget.player.currentQualityLabel,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: widget.player.selectedQuality != null &&
                                                        !widget.player.selectedQuality!.isAuto
                                                    ? AppColors.primaryNeon
                                                    : Colors.white,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                // Integrated Fullscreen button
                                const SizedBox(width: 4),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () {
                                      AppHaptics.selection();
                                      widget.player.toggleFullscreen();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.35),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.25),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Icon(
                                        (kIsWeb ? FullscreenHelper.isFullscreen : isFs)
                                            ? Icons.fullscreen_exit_rounded
                                            : Icons.fullscreen_rounded,
                                        size: 15,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // 2. Timeline Slider / Scrub Bar (positioned at the very bottom edge)
                            if (duration > 0) ...[
                              if (canControl)
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 5,
                                    ),
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 10,
                                    ),
                                  ),
                                  child: SizedBox(
                                    height: 20,
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
                                        _startHideTimerIfNeeded(reset: true);
                                      },
                                    ),
                                  ),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: (pos / duration).clamp(0.0, 1.0),
                                      backgroundColor: AppColors.border,
                                      color: AppColors.primaryNeon,
                                      minHeight: 3,
                                    ),
                                  ),
                                ),
                            ] else ...[
                              const SizedBox(height: 2),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  },
);
}

  Widget _buildErrorOverlay(
    BuildContext context,
    String errorMsg, {
    required bool canControl,
  }) {
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    onPressed: () {
                      widget.player.reloadCurrentMedia();
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text(
                      'Coba Lagi',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  if (widget.player.isLocalFile ||
                      widget.player.mediaUrl.startsWith('blob:')) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryNeon,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                      ),
                      onPressed: () async {
                        final picked = await FilePicker.pickFile(
                          type: FileType.video,
                        );
                        if (picked != null) {
                          final path = kIsWeb
                              ? (picked.xFile.path.isNotEmpty
                                  ? picked.xFile.path
                                  : picked.uri.toString())
                              : (picked.path ?? '');
                          if (path.isNotEmpty) {
                            if (!kIsWeb) {
                              P2PFileStreamService.instance
                                  .setLocalOverride(path);
                            }
                            await widget.player.loadMedia(
                              'direct_url',
                              path,
                              autoPlay: widget.player.isPlaying,
                              startSeconds: widget.player.position,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Memutar salinan file lokal (Syncplay)'),
                                  backgroundColor: AppColors.primaryNeon,
                                ),
                              );
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.folder_open_rounded, size: 14),
                      label: const Text(
                        'Pilih File Lokal Saya',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                  if (canControl) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (widget.player.isLocalFile ||
                                widget.player.mediaUrl.startsWith('blob:'))
                            ? AppColors.surfaceElevated
                            : AppColors.primaryNeon,
                        foregroundColor: (widget.player.isLocalFile ||
                                widget.player.mediaUrl.startsWith('blob:'))
                            ? Colors.white
                            : Colors.black,
                        side: (widget.player.isLocalFile ||
                                widget.player.mediaUrl.startsWith('blob:'))
                            ? const BorderSide(color: AppColors.border)
                            : null,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                      ),
                      onPressed: widget.onOpenMediaPicker,
                      icon: const Icon(Icons.video_library_rounded, size: 14),
                      label: const Text(
                        'Pilih Video Lain',
                        style: TextStyle(fontSize: 12),
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

  Widget _buildEmptyPlaceholder() {
    final bool canControl = widget.syncController.canControl;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryNeon.withValues(alpha: 0.12),
                border: Border.all(
                  color: AppColors.primaryNeon.withValues(alpha: 0.25),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryNeon.withValues(alpha: 0.15),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.movie_creation_outlined,
                size: 32,
                color: AppColors.primaryNeon,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Belum ada media yang dimuat',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'Pilih video atau stream untuk mulai nonton bersama',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            if (canControl)
              ElevatedButton.icon(
                onPressed: widget.onOpenMediaPicker,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryNeon,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  visualDensity: VisualDensity.compact,
                  elevation: 4,
                  shadowColor: AppColors.primaryNeon.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: const Icon(Icons.video_library_rounded, size: 16),
                label: const Text(
                  'Pilih Video',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.accentYellow.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.hourglass_top_rounded,
                      size: 13,
                      color: AppColors.accentYellow,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Menunggu Host memilih video...',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.accentYellow,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
