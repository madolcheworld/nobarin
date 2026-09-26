import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../core/widgets/frosted_glass_box.dart';
import '../../controllers/chat_controller.dart';
import '../../models/chat_message.dart';
import '../chat_panel_widget.dart';

class FullscreenCommentOverlay extends StatefulWidget {
  final ChatController chatController;
  final bool isDrawerOpen;
  final VoidCallback onOpenDrawer;
  final VoidCallback onCloseDrawer;
  final String? hostId;
  final String? hostName;
  final Set<String> coHostUserIds;

  const FullscreenCommentOverlay({
    super.key,
    required this.chatController,
    required this.isDrawerOpen,
    required this.onOpenDrawer,
    required this.onCloseDrawer,
    this.hostId,
    this.hostName,
    this.coHostUserIds = const {},
  });

  @override
  State<FullscreenCommentOverlay> createState() =>
      _FullscreenCommentOverlayState();
}

class _FullscreenCommentOverlayState extends State<FullscreenCommentOverlay> {
  static const int _maxToastCount = 3;
  static const Duration _toastDuration = Duration(seconds: 4);

  final List<ChatMessage> _activeToasts = [];
  final Map<String, Timer> _toastTimers = {};
  StreamSubscription<ChatMessage>? _messageSub;

  @override
  void initState() {
    super.initState();
    widget.chatController.addListener(_onControllerChanged);
    _messageSub =
        widget.chatController.incomingMessageStream.listen(_onNewMessage);
  }

  @override
  void didUpdateWidget(covariant FullscreenCommentOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatController != widget.chatController) {
      oldWidget.chatController.removeListener(_onControllerChanged);
      widget.chatController.addListener(_onControllerChanged);
      _messageSub?.cancel();
      _messageSub =
          widget.chatController.incomingMessageStream.listen(_onNewMessage);
    }
    if (widget.isDrawerOpen && _activeToasts.isNotEmpty) {
      _clearAllToasts();
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (!widget.chatController.showFloatingReactions &&
        _activeToasts.isNotEmpty) {
      setState(() {
        _clearAllToasts();
      });
    }
  }

  void _onNewMessage(ChatMessage msg) {
    if (!mounted) return;
    if (!widget.chatController.showFloatingReactions) return;
    if (widget.isDrawerOpen) return;
    if (!msg.isText || msg.isSystem || msg.isReaction) return;

    setState(() {
      if (_activeToasts.length >= _maxToastCount) {
        final oldest = _activeToasts.removeAt(0);
        _toastTimers.remove(oldest.id)?.cancel();
      }
      _activeToasts.add(msg);
    });

    _toastTimers[msg.id]?.cancel();
    _toastTimers[msg.id] = Timer(_toastDuration, () {
      if (!mounted) return;
      setState(() {
        _activeToasts.removeWhere((m) => m.id == msg.id);
        _toastTimers.remove(msg.id);
      });
    });
  }

  void _clearAllToasts() {
    for (final timer in _toastTimers.values) {
      timer.cancel();
    }
    _toastTimers.clear();
    _activeToasts.clear();
  }

  @override
  void dispose() {
    widget.chatController.removeListener(_onControllerChanged);
    _messageSub?.cancel();
    _clearAllToasts();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final safePadding = MediaQuery.paddingOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double drawerWidth =
            (constraints.maxWidth * 0.44).clamp(280.0, 380.0);
        final double availableDrawerHeight =
            constraints.maxHeight - keyboardInset;
        final bool isKeyboardCompact =
            keyboardInset > 0 && availableDrawerHeight < 260;

        return Stack(
          children: [
            // Live Comment Toast Pills (Bottom-Left, Non-Intrusive)
            if (!widget.isDrawerOpen &&
                widget.chatController.showFloatingReactions &&
                _activeToasts.isNotEmpty)
              Positioned(
                left: 16 + safePadding.left,
                bottom: 72 + safePadding.bottom,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (constraints.maxWidth * 0.55).clamp(200.0, 310.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: _activeToasts.map((msg) {
                      return Padding(
                        key: ValueKey('fullscreen_toast_${msg.id}'),
                        padding: const EdgeInsets.only(top: 6),
                        child: PointerInterceptor(
                          child: FrostedGlassBox(
                            blur: 10,
                            borderRadius: BorderRadius.circular(14),
                            backgroundColor:
                                AppColors.surface.withValues(alpha: 0.76),
                            borderColor: AppColors.glassBorder,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 7,
                            ),
                            onTap: () {
                              AppHaptics.selection();
                              widget.onOpenDrawer();
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg.avatarUrl,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: RichText(
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '${msg.username}: ',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.secondaryNeon,
                                          ),
                                        ),
                                        TextSpan(
                                          text: msg.content,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

            // Scrim tap target when drawer is open
            if (widget.isDrawerOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    widget.onCloseDrawer();
                  },
                  child: const SizedBox.expand(),
                ),
              ),

            // Slide-Over Glass Comment Drawer on the right
            AnimatedPositioned(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              top: 0,
              bottom: keyboardInset,
              right: widget.isDrawerOpen ? 0 : -(drawerWidth + 24),
              width: drawerWidth,
              child: IgnorePointer(
                ignoring: !widget.isDrawerOpen,
                child: PointerInterceptor(
                  intercepting: widget.isDrawerOpen,
                  child: FrostedGlassBox(
                    key: const ValueKey('fullscreen_comment_drawer'),
                    blur: 16,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(20),
                    ),
                    backgroundColor: AppColors.glassFillHeavy,
                    borderColor: AppColors.glassBorderHighlight,
                    boxShadow: AppColors.atmosphericCardShadow,
                    child: Material(
                      type: MaterialType.transparency,
                      child: SafeArea(
                        left: false,
                        bottom: keyboardInset == 0,
                        child: Column(
                          children: [
                            // Drawer Header (compact or hidden when keyboard is open in tight landscape)
                            if (!isKeyboardCompact)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: AppColors.border,
                                      width: 0.8,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryNeon
                                            .withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.forum_rounded,
                                        size: 16,
                                        color: AppColors.primaryNeonLight,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Komentar Live',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      key: const ValueKey(
                                          'close_fullscreen_drawer_button'),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 20,
                                        color: AppColors.textSecondary,
                                      ),
                                      tooltip: 'Tutup Komentar',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () {
                                        AppHaptics.light();
                                        FocusManager.instance.primaryFocus
                                            ?.unfocus();
                                        widget.onCloseDrawer();
                                      },
                                    ),
                                  ],
                                ),
                              ),

                            // Compact Chat Panel
                            Expanded(
                              child: ChatPanelWidget(
                                chatController: widget.chatController,
                                isCompact: true,
                                showReactions: false,
                                hostId: widget.hostId,
                                hostName: widget.hostName,
                                coHostUserIds: widget.coHostUserIds,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
