import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/fullscreen/fullscreen_helper.dart';
import '../../controllers/webrtc_screenshare_controller.dart';

/// Interactive player view that displays WebRTC screen sharing streams.
class ScreenShareView extends StatefulWidget {
  final WebRtcScreenShareController controller;
  final bool isHost;
  final VoidCallback? onExit;
  final String? roomTitle;

  const ScreenShareView({
    super.key,
    required this.controller,
    required this.isHost,
    this.onExit,
    this.roomTitle,
  });

  @override
  State<ScreenShareView> createState() => _ScreenShareViewState();
}

class _ScreenShareViewState extends State<ScreenShareView> {
  bool _isFullscreen = false;
  bool _fitContain = true;

  Future<void> _toggleFullscreen() async {
    final next = !_isFullscreen;
    setState(() => _isFullscreen = next);

    try {
      if (next) {
        FullscreenHelper.enterFullscreen();
      } else {
        FullscreenHelper.exitFullscreen();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final isSharing = widget.controller.isSharing;
        final sharerName = widget.controller.sharerName ?? 'Peserta';
        final hasRemoteStream = widget.controller.remoteStream != null ||
            widget.controller.remoteRenderer.srcObject != null;

        Widget content;
        if (isSharing) {
          // Local sharer view
          content = Stack(
            fit: StackFit.expand,
            children: [
              RTCVideoView(
                widget.controller.localRenderer,
                objectFit: _fitContain
                    ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                    : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                mirror: false,
              ),
              _buildTopBar(
                isSharing: true,
                title: 'Anda sedang berbagi layar',
                isLocal: true,
              ),
              _buildLocalPresenterIndicator(),
            ],
          );
        } else if (hasRemoteStream) {
          // Remote viewer view
          content = Stack(
            fit: StackFit.expand,
            children: [
              RTCVideoView(
                widget.controller.remoteRenderer,
                objectFit: _fitContain
                    ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                    : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                mirror: false,
              ),
              _buildTopBar(
                isSharing: false,
                title: 'Layar: $sharerName',
                isLocal: false,
              ),
            ],
          );
        } else {
          // Connecting placeholder
          content = Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppColors.secondaryNeon,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Menghubungkan ke siaran layar $sharerName...',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Sedang menegosiasikan stream WebRTC peer-to-peer',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _buildTopBar(
                isSharing: false,
                title: 'Layar: $sharerName',
                isLocal: false,
              ),
            ],
          );
        }

        final mainContainer = Container(
          color: Colors.black,
          child: content,
        );

        if (_isFullscreen) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              _toggleFullscreen();
            },
            child: Scaffold(
              backgroundColor: Colors.black,
              body: mainContainer,
            ),
          );
        }

        return AspectRatio(
          aspectRatio: 16 / 9,
          child: mainContainer,
        );
      },
    );
  }

  Widget _buildTopBar({
    required bool isSharing,
    required String title,
    required bool isLocal,
  }) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        top: _isFullscreen,
        bottom: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.8),
                Colors.transparent,
              ],
            ),
          ),
          child: Row(
            children: [
              // Live Screen Share Indicator
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isLocal
                        ? AppColors.accentRed.withValues(alpha: 0.85)
                        : AppColors.secondaryNeon.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isLocal
                            ? Icons.screen_share_rounded
                            : Icons.personal_video_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // Fit / Fill toggle button
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: _fitContain ? 'Penuh Layar' : 'Pas Layar (Contain)',
                icon: Icon(
                  _fitContain
                      ? Icons.aspect_ratio_rounded
                      : Icons.fit_screen_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _fitContain = !_fitContain);
                },
              ),

              // Fullscreen toggle button
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: _isFullscreen ? 'Keluar Fullscreen' : 'Fullscreen',
                icon: Icon(
                  _isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                onPressed: _toggleFullscreen,
              ),

              // Stop sharing button (if local sharer or host)
              if (isLocal || widget.isHost) ...[
                const SizedBox(width: 2),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: isLocal ? 'Hentikan Layar' : 'Paksa Henti',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.accentRed.withValues(alpha: 0.9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(6),
                  ),
                  icon: const Icon(Icons.stop_screen_share_rounded, size: 18),
                  onPressed: () async {
                    await widget.controller.stopScreenShare(
                      forcedByHost: !isLocal && widget.isHost,
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocalPresenterIndicator() {
    return Positioned(
      bottom: 12,
      left: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.accentRed.withValues(alpha: 0.5),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_rounded, color: AppColors.accentRed, size: 14),
            SizedBox(width: 6),
            Text(
              'Layar Anda dapat dilihat semua peserta',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
