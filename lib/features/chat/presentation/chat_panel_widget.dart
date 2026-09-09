import 'package:flutter/material.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../core/utils/time_formatter.dart';
import '../controllers/chat_controller.dart';
import '../models/chat_message.dart';

class ChatPanelWidget extends StatefulWidget {
  final ChatController chatController;
  final bool showReactions;
  final String? hostId;
  final String? hostName;
  final Set<String> coHostUserIds;

  const ChatPanelWidget({
    super.key,
    required this.chatController,
    this.showReactions = true,
    this.hostId,
    this.hostName,
    this.coHostUserIds = const {},
  });

  @override
  State<ChatPanelWidget> createState() => _ChatPanelWidgetState();
}

class _ChatPanelWidgetState extends State<ChatPanelWidget> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _lastMessageCount = widget.chatController.messages.length;
    widget.chatController.addListener(_handleChatUpdate);
    _inputController.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant ChatPanelWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatController != widget.chatController) {
      oldWidget.chatController.setTyping(false);
      oldWidget.chatController.removeListener(_handleChatUpdate);
      _lastMessageCount = widget.chatController.messages.length;
      widget.chatController.addListener(_handleChatUpdate);
    }
  }

  void _onTextChanged() {
    final hasText = _inputController.text.trim().isNotEmpty;
    widget.chatController.setTyping(hasText);
  }

  void _handleChatUpdate() {
    final currentCount = widget.chatController.messages.length;
    if (currentCount > _lastMessageCount) {
      _lastMessageCount = currentCount;
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    widget.chatController.setTyping(false);
    widget.chatController.removeListener(_handleChatUpdate);
    _inputController.removeListener(_onTextChanged);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    AppHaptics.light();
    widget.chatController.sendMessage(text);
    _inputController.clear();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.chatController,
      builder: (context, _) {
        final messages = widget.chatController.messages;
        final currentUserId = widget.chatController.currentUser.id;

        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
          ),
          child: Column(
            children: [
              // Message List
              Expanded(
                child: messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 32,
                              color: AppColors.textMuted.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Belum ada pesan',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          if (msg.isSystem) {
                            return _buildSystemMessage(msg);
                          }
                          final bool isMe = msg.userId == currentUserId;
                          return _buildMessageBubble(msg, isMe);
                        },
                      ),
              ),

              // Quick Reactions Row
              if (widget.showReactions)
                Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceElevated,
                    border: Border(
                      top: BorderSide(color: AppColors.border, width: 0.8),
                    ),
                  ),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: ApiConstants.quickReactions.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 4),
                    itemBuilder: (context, index) {
                      final emoji = ApiConstants.quickReactions[index];
                      return InkWell(
                        onTap: () {
                          AppHaptics.selection();
                          widget.chatController.sendReaction(emoji);
                          _scrollToBottom();
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // Typing Indicator Banner
              _buildTypingIndicator(widget.chatController.typingStatusText),

              // Input Bar
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    top: BorderSide(color: AppColors.border),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Tulis pesan...',
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.primaryGradient,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded,
                            size: 18, color: Colors.white),
                        onPressed: _sendMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSystemMessage(ChatMessage msg) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          msg.content,
          style: const TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isMe) {
    final isHost = (widget.hostId != null &&
            widget.hostId!.isNotEmpty &&
            msg.userId == widget.hostId) ||
        (widget.hostName != null &&
            widget.hostName!.isNotEmpty &&
            widget.hostName != 'Host' &&
            msg.username == widget.hostName);
    final isCoHost = widget.coHostUserIds.contains(msg.userId) ||
        widget.coHostUserIds.contains(msg.username);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.surfaceElevated,
              child: Text(msg.avatarUrl, style: const TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          msg.username,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.secondaryNeon,
                          ),
                        ),
                        if (isHost) ...[
                          const SizedBox(width: 4),
                          const Text('👑', style: TextStyle(fontSize: 10)),
                        ] else if (isCoHost) ...[
                          const SizedBox(width: 4),
                          const Text('⭐', style: TextStyle(fontSize: 10)),
                        ],
                      ],
                    ),
                  ),
                Container(
                  padding: msg.isReaction
                      ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                      : const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: msg.isReaction
                        ? Colors.transparent
                        : (isMe
                            ? (msg.status == MessageStatus.failed
                                ? AppColors.accentRed.withValues(alpha: 0.2)
                                : null)
                            : AppColors.surfaceElevated),
                    gradient: (!msg.isReaction &&
                            isMe &&
                            msg.status != MessageStatus.failed)
                        ? const LinearGradient(
                            colors: [
                              Color(0xFF6366F1), // Indigo
                              Color(0xFF00E5FF), // Cyan neon
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 3),
                      bottomRight: Radius.circular(isMe ? 3 : 16),
                    ),
                    border: msg.isReaction
                        ? null
                        : Border.all(
                            color: isMe
                                ? (msg.status == MessageStatus.failed
                                    ? AppColors.accentRed
                                    : AppColors.borderLight)
                                : AppColors.borderLight,
                            width: 1,
                          ),
                    boxShadow: (!msg.isReaction &&
                            isMe &&
                            msg.status != MessageStatus.failed)
                        ? [
                            BoxShadow(
                              color: AppColors.primaryNeon.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    msg.content,
                    style: TextStyle(
                      fontSize: msg.isReaction ? 28 : 13,
                      color: Colors.white,
                      fontWeight: isMe ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.only(top: 2, left: 4, right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        TimeFormatter.formatChatTime(msg.createdAt),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        if (msg.status == MessageStatus.sending)
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.textMuted,
                            ),
                          )
                        else if (msg.status == MessageStatus.failed)
                          InkWell(
                            onTap: () => widget.chatController.retryMessage(msg.id),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline_rounded,
                                    size: 12, color: AppColors.accentRed),
                                SizedBox(width: 2),
                                Text(
                                  'Gagal (Kirim ulang)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.accentRed,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.surfaceElevated,
              child: Text(msg.avatarUrl, style: const TextStyle(fontSize: 14)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(String? typingText) {
    final isTyping = typingText != null && typingText.isNotEmpty;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: isTyping
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated.withValues(alpha: 0.7),
                border: const Border(
                  top: BorderSide(color: AppColors.border, width: 0.6),
                ),
              ),
              child: Row(
                children: [
                  const _TypingDotsIndicator(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      typingText,
                      style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: AppColors.secondaryNeon,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _TypingDotsIndicator extends StatefulWidget {
  const _TypingDotsIndicator();

  @override
  State<_TypingDotsIndicator> createState() => _TypingDotsIndicatorState();
}

class _TypingDotsIndicatorState extends State<_TypingDotsIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final progress = (_animController.value - (index * 0.2)) % 1.0;
            final double t = progress < 0.5 ? progress * 2 : (1.0 - progress) * 2;
            final double scale = 0.6 + 0.4 * t;
            final double opacity = 0.3 + 0.7 * t;
            return Transform.scale(
              scale: scale,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.secondaryNeon.withValues(alpha: opacity.clamp(0.2, 1.0)),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
