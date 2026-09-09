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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row
            Row(
              children: [
                const ShimmerBox(width: 80, height: 22, borderRadius: 6),
                const Spacer(),
                const ShimmerBox(width: 50, height: 16, borderRadius: 8),
                const SizedBox(width: 10),
                const ShimmerBox(width: 36, height: 20, borderRadius: 6),
              ],
            ),
            const SizedBox(height: 14),
            // Title Lines
            const ShimmerBox(width: double.infinity, height: 16, borderRadius: 4),
            const SizedBox(height: 6),
            const ShimmerBox(width: 180, height: 14, borderRadius: 4),
            const SizedBox(height: 16),
            // Bottom Row
            Row(
              children: [
                const ShimmerBox(width: 24, height: 24, borderRadius: 12),
                const SizedBox(width: 8),
                const ShimmerBox(width: 90, height: 14, borderRadius: 4),
                const Spacer(),
                const ShimmerBox(width: 55, height: 20, borderRadius: 6),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
