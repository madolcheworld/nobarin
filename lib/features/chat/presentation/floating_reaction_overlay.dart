import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../controllers/chat_controller.dart';

class FloatingReactionOverlay extends StatefulWidget {
  final ChatController chatController;

  const FloatingReactionOverlay({super.key, required this.chatController});

  @override
  State<FloatingReactionOverlay> createState() =>
      _FloatingReactionOverlayState();
}

class _FloatingReactionOverlayState extends State<FloatingReactionOverlay> {
  final List<FloatingReaction> _activeReactions = [];
  StreamSubscription<FloatingReaction>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription =
        widget.chatController.reactionsStream.listen((reaction) {
      if (!mounted) return;
      setState(() {
        _activeReactions.add(reaction);
      });

      // Remove after animation finishes (2.5s)
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (!mounted) return;
        setState(() {
          _activeReactions.removeWhere((r) => r.id == reaction.id);
        });
      });
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
            children: _activeReactions.map((reaction) {
              final xPos = reaction.startX * (width - 40);

              return Positioned(
                left: xPos,
                bottom: 20,
                child: Text(
                  reaction.emoji,
                  style: const TextStyle(fontSize: 34),
                )
                    .animate(key: ValueKey(reaction.id))
                    .fadeIn(duration: 200.ms)
                    .scale(
                      begin: const Offset(0.5, 0.5),
                      end: const Offset(1.2, 1.2),
                      duration: 400.ms,
                      curve: Curves.elasticOut,
                    )
                    .slideY(
                      begin: 0,
                      end: - (height * 0.8) / 34,
                      duration: 2200.ms,
                      curve: Curves.easeOutQuad,
                    )
                    .fadeOut(
                      delay: 1500.ms,
                      duration: 700.ms,
                    ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
