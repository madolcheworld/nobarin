import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../controllers/chat_controller.dart';
import 'emoji_picker_sheet.dart';

class FullscreenReactionBar extends StatefulWidget {
  final ChatController chatController;
  final VoidCallback? onToggleComments;
  final bool isCommentDrawerOpen;
  final int unreadCommentCount;

  const FullscreenReactionBar({
    super.key,
    required this.chatController,
    this.onToggleComments,
    this.isCommentDrawerOpen = false,
    this.unreadCommentCount = 0,
  });

  @override
  State<FullscreenReactionBar> createState() => _FullscreenReactionBarState();
}

class _FullscreenReactionBarState extends State<FullscreenReactionBar>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  Timer? _collapseTimer;
  late AnimationController _animController;
  late Animation<double> _expandAnimation;

  static const List<String> _quickEmojis = [
    '❤️',
    '🔥',
    '😂',
    '👏',
    '🍿',
    '🎉',
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    AppHaptics.selection();
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animController.forward();
        _resetCollapseTimer();
      } else {
        _collapseTimer?.cancel();
        _animController.reverse();
      }
    });
  }

  void _resetCollapseTimer() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _isExpanded = false;
        _animController.reverse();
      });
    });
  }

  void _sendEmoji(String emoji) {
    widget.chatController.sendReaction(emoji);
    _resetCollapseTimer();
  }

  void _openFullPicker() {
    _collapseTimer?.cancel();
    EmojiPickerSheet.show(
      context,
      title: 'Kirim Reaksi Nobar',
      onSelectEmoji: (emoji) {
        _sendEmoji(emoji);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isCommentDrawerOpen) {
      return const SizedBox.shrink();
    }

    final screenSize = MediaQuery.sizeOf(context);
    final safePadding = MediaQuery.paddingOf(context);
    final maxDockHeight =
        (screenSize.height - safePadding.top - safePadding.bottom - 148)
            .clamp(120.0, 340.0);

    return Positioned(
      right: 16 + safePadding.right,
      bottom: 68 + safePadding.bottom,
      child: PointerInterceptor(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Expanded Emoji Dock
            SizeTransition(
              sizeFactor: _expandAnimation,
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                constraints: BoxConstraints(maxHeight: maxDockHeight),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Toggle floating reactions visibility
                      ListenableBuilder(
                        listenable: widget.chatController,
                        builder: (context, _) {
                          final isEnabled =
                              widget.chatController.showFloatingReactions;
                          return IconButton(
                            icon: Icon(
                              isEnabled
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: isEnabled
                                  ? AppColors.primaryNeon
                                  : AppColors.textMuted,
                              size: 19,
                            ),
                            padding: const EdgeInsets.all(6),
                            constraints: const BoxConstraints(
                              minWidth: 34,
                              minHeight: 34,
                            ),
                            visualDensity: VisualDensity.compact,
                            tooltip: isEnabled
                                ? 'Sembunyikan Reaksi Layar'
                                : 'Tampilkan Reaksi Layar',
                            onPressed: () {
                              AppHaptics.light();
                              widget.chatController.toggleFloatingReactions();
                              _resetCollapseTimer();
                            },
                          );
                        },
                      ),
                      // Full picker launcher button
                      IconButton(
                        icon: const Icon(
                          Icons.add_reaction_outlined,
                          color: AppColors.secondaryNeon,
                          size: 19,
                        ),
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(
                          minWidth: 34,
                          minHeight: 34,
                        ),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Semua Reaksi',
                        onPressed: _openFullPicker,
                      ),
                      const Divider(
                        height: 8,
                        thickness: 0.5,
                        color: Colors.white24,
                      ),
                      ..._quickEmojis.map((emoji) {
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _sendEmoji(emoji),
                            borderRadius: BorderRadius.circular(18),
                            splashColor:
                                AppColors.primaryNeon.withValues(alpha: 0.4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3.5,
                              ),
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 21),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),

          // Action Buttons Row / Stack (Comments Drawer Toggle + Main Reaction Toggle)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onToggleComments != null) ...[
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey('fullscreen_toggle_comments_button'),
                    onTap: () {
                      AppHaptics.selection();
                      widget.onToggleComments?.call();
                    },
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.78),
                            border: Border.all(
                              color:
                                  AppColors.secondaryNeon.withValues(alpha: 0.6),
                              width: 1.4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.secondaryNeon
                                    .withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.chat_bubble_rounded,
                              color: AppColors.secondaryNeon,
                              size: 21,
                            ),
                          ),
                        ),
                        if (widget.unreadCommentCount > 0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accentPink,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.black,
                                  width: 1.2,
                                ),
                              ),
                              child: Text(
                                widget.unreadCommentCount > 99
                                    ? '99+'
                                    : '${widget.unreadCommentCount}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],

              // Main Reaction Toggle Button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _toggleExpand,
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _isExpanded
                          ? AppColors.comboMegaGradient
                          : LinearGradient(
                              colors: [
                                Colors.black.withValues(alpha: 0.7),
                                Colors.black.withValues(alpha: 0.85),
                              ],
                            ),
                      border: Border.all(
                        color: _isExpanded
                            ? Colors.white
                            : AppColors.primaryNeon.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_isExpanded
                                  ? AppColors.accentPink
                                  : AppColors.primaryNeon)
                              .withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: AnimatedRotation(
                        turns: _isExpanded ? 0.25 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          _isExpanded
                              ? Icons.close_rounded
                              : Icons.favorite_rounded,
                          color:
                              _isExpanded ? Colors.white : AppColors.accentRed,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}
