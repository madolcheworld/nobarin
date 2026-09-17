import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Animated shimmer wrapper that sweeps a glowing gradient across its child.
class ShimmerLoading extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const ShimmerLoading({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final double progress = _controller.value;
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: [
                (progress - 0.3).clamp(0.0, 1.0),
                progress.clamp(0.0, 1.0),
                (progress + 0.3).clamp(0.0, 1.0),
              ],
              colors: const [
                AppColors.shimmerBase,
                AppColors.shimmerHighlight,
                AppColors.shimmerBase,
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Standalone skeleton box with rounded corners.
class ShimmerBox extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.shimmerBase,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton loading card matching the layout of [RoomCard].
class RoomCardSkeleton extends StatelessWidget {
  const RoomCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight, width: 1.1),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Thumbnail
            SizedBox(
              width: 124,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ShimmerBox(
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: 10,
                ),
              ),
            ),
            SizedBox(width: 12),
            // Right info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShimmerBox(
                    width: double.infinity,
                    height: 14,
                    borderRadius: 4,
                  ),
                  SizedBox(height: 6),
                  ShimmerBox(
                    width: 100,
                    height: 12,
                    borderRadius: 4,
                  ),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      ShimmerBox(
                        width: 50,
                        height: 18,
                        borderRadius: 6,
                      ),
                      SizedBox(width: 6),
                      ShimmerBox(
                        width: 60,
                        height: 18,
                        borderRadius: 6,
                      ),
                    ],
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
