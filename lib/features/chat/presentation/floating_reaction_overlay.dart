import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../controllers/chat_controller.dart';

class FloatingReactionOverlay extends StatefulWidget {
  final ChatController chatController;

  const FloatingReactionOverlay({super.key, required this.chatController});

  @override
  State<FloatingReactionOverlay> createState() =>
      _FloatingReactionOverlayState();
}

class _FloatingReactionOverlayState extends State<FloatingReactionOverlay> {
  final List<FloatingReactionItemData> _items = [];
  StreamSubscription<FloatingReaction>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.chatController.reactionsStream.listen(_onReaction);
  }

  @override
  void didUpdateWidget(FloatingReactionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatController != widget.chatController) {
      _subscription?.cancel();
      _subscription = widget.chatController.reactionsStream.listen(_onReaction);
    }
  }

  void _removeItem(String id) {
    if (!mounted) return;
    setState(() {
      _items.removeWhere((i) => i.id == id);
    });
  }

  void _onReaction(FloatingReaction reaction) {
    if (!mounted) return;

    // Haptic escalation based on combo
    if (reaction.comboCount >= 8) {
      AppHaptics.heavy();
    } else if (reaction.comboCount >= 4) {
      AppHaptics.medium();
    } else {
      AppHaptics.selection();
    }

    final item = FloatingReactionItemData(
      id: reaction.id,
      emoji: reaction.emoji,
      startX: reaction.startX,
      comboCount: reaction.comboCount,
      senderName: reaction.senderName,
      randomSeed: math.Random().nextDouble() * math.pi * 2,
      swaySpeed: 1.8 + math.Random().nextDouble() * 1.5,
    );

    setState(() {
      _items.add(item);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;

          return Stack(
            clipBehavior: Clip.none,
            children: _items.map((item) {
              return _PhysicsReactionWidget(
                key: ValueKey(item.id),
                item: item,
                containerWidth: width,
                containerHeight: height,
                onComplete: () => _removeItem(item.id),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class FloatingReactionItemData {
  final String id;
  final String emoji;
  final double startX;
  final int comboCount;
  final String? senderName;
  final double randomSeed;
  final double swaySpeed;

  FloatingReactionItemData({
    required this.id,
    required this.emoji,
    required this.startX,
    required this.comboCount,
    this.senderName,
    required this.randomSeed,
    required this.swaySpeed,
  });
}

class _PhysicsReactionWidget extends StatefulWidget {
  final FloatingReactionItemData item;
  final double containerWidth;
  final double containerHeight;
  final VoidCallback onComplete;

  const _PhysicsReactionWidget({
    super.key,
    required this.item,
    required this.containerWidth,
    required this.containerHeight,
    required this.onComplete,
  });

  @override
  State<_PhysicsReactionWidget> createState() => _PhysicsReactionWidgetState();
}

class _PhysicsReactionWidgetState extends State<_PhysicsReactionWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _controller.forward().then((_) {
      widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final width = widget.containerWidth;
    final height = widget.containerHeight;

    // Base position bounded within screen margins
    final double baseX = (item.startX * (width - 64)).clamp(16.0, width - 64.0);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;

        // Vertical motion: rises smoothly with easeOutCubic
        final double curveY = Curves.easeOutCubic.transform(t);
        final double yOffset = (height * 0.72) * curveY;

        // Horizontal sinusoidal sway
        final double sway =
            math.sin((t * math.pi * item.swaySpeed) + item.randomSeed) * 24.0;
        final double currentX = baseX + sway;

        // Gentle rotation tilt (wobble)
        final double rotation =
            math.sin((t * math.pi * 2.5) + item.randomSeed) * 0.22;

        // Scale: elastic pop at spawn, expands on combo, slight expansion at fade
        double scale;
        if (t < 0.18) {
          final pop = t / 0.18;
          scale = Curves.elasticOut.transform(pop) *
              (1.0 + math.min(item.comboCount * 0.05, 0.45));
        } else if (t > 0.8) {
          final endP = (t - 0.8) / 0.2;
          scale = (1.0 + math.min(item.comboCount * 0.05, 0.45)) *
              (1.0 + endP * 0.25);
        } else {
          scale = 1.0 + math.min(item.comboCount * 0.05, 0.45);
        }

        // Opacity: solid until 72%, then fades out to 0
        final double opacity =
            t < 0.72 ? 1.0 : (1.0 - ((t - 0.72) / 0.28)).clamp(0.0, 1.0);

        return Positioned(
          left: currentX,
          bottom: 24 + yOffset,
          child: Opacity(
            opacity: opacity,
            child: Transform.rotate(
              angle: rotation,
              child: Transform.scale(
                scale: scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Combo Badge
                    if (item.comboCount > 1)
                      _buildComboBadge(item.comboCount, t),
                    const SizedBox(height: 2),
                    // Main Emoji
                    Text(
                      item.emoji,
                      style: TextStyle(
                        fontSize: item.comboCount >= 8 ? 40 : 34,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildComboBadge(int combo, double progress) {
    final isMega = combo >= 8;
    final isSuper = combo >= 4;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isMega
              ? const [Color(0xFFFF007A), Color(0xFFFF8A00)]
              : isSuper
                  ? const [Color(0xFFFF5252), Color(0xFFFFD700)]
                  : const [AppColors.primaryNeon, AppColors.secondaryNeon],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: (isMega ? const Color(0xFFFF007A) : AppColors.primaryNeon)
                .withValues(alpha: 0.6),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isMega) ...[
            const Text('🔥', style: TextStyle(fontSize: 10)),
            const SizedBox(width: 2),
          ],
          Text(
            'x$combo',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
