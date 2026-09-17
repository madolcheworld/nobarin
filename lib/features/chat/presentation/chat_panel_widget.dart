import 'package:flutter/material.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../core/utils/time_formatter.dart';
import '../controllers/chat_controller.dart';
import '../models/chat_message.dart';
import 'widgets/emoji_picker_sheet.dart';

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

  void _openEmojiPickerForFloating() {
    EmojiPickerSheet.show(
      context,
      title: 'Kirim Reaksi Nobar',
      onSelectEmoji: (emoji) {
        widget.chatController.sendReaction(emoji);
        _scrollToBottom();
      },
      onSelectCallout: (callout) {
        widget.chatController.sendMessage(callout);
        _scrollToBottom();
      },
    );
  }

  void _openEmojiPickerForInput() {
    EmojiPickerSheet.show(
      context,
      title: 'Sisipkan Emoticon',
      onSelectEmoji: (emoji) {
        _insertEmojiAtCursor(emoji);
      },
      onSelectCallout: (callout) {
        _inputController.text = callout;
        _inputController.selection =
            TextSelection.collapsed(offset: callout.length);
      },
    );
  }

  void _insertEmojiAtCursor(String emoji) {
    final text = _inputController.text;
    final selection = _inputController.selection;
    if (selection.start < 0 || selection.end < 0) {
      _inputController.text = '$text$emoji';
      _inputController.selection =
          TextSelection.collapsed(offset: _inputController.text.length);
    } else {
      final newText = text.replaceRange(selection.start, selection.end, emoji);
      _inputController.text = newText;
      _inputController.selection =
          TextSelection.collapsed(offset: selection.start + emoji.length);
    }
  }

  void _showMessageReactionBar(ChatMessage msg) {
    if (msg.isSystem || msg.isReaction) return;
    AppHaptics.medium();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Reaksi untuk ${msg.username}: "${msg.content.length > 25 ? '${msg.content.substring(0, 25)}...' : msg.content}"',
                style:
                    const TextStyle(fontSize: 12, color: AppColors.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...['❤️', '👍', '😂', '🔥', '😮', '😢', '👏', '🎉']
                        .map((emoji) {
                      final hasReacted = msg.hasUserReacted(
                        emoji,
                        widget.chatController.currentUser.id,
                      );
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          onTap: () {
                            AppHaptics.selection();
                            Navigator.of(ctx).pop();
                            widget.chatController
                                .toggleMessageReaction(msg.id, emoji);
                          },
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: hasReacted
                                  ? AppColors.primaryNeon.withValues(alpha: 0.25)
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child:
                                Text(emoji, style: const TextStyle(fontSize: 26)),
                          ),
                        ),
                      );
                    }),
                    // More icon
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: InkWell(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          EmojiPickerSheet.show(
                            context,
                            title: 'Pilih Reaksi Pesan',
                            onSelectEmoji: (emoji) {
                              widget.chatController
                                  .toggleMessageReaction(msg.id, emoji);
                            },
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            size: 22,
                            color: AppColors.secondaryNeon,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

              // Quick Reactions Row (Compact & Streamlined)
              if (widget.showReactions)
                Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceElevated,
                    border: Border(
                      top: BorderSide(color: AppColors.border, width: 0.8),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        size: 14,
                        color: AppColors.primaryNeon,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: ApiConstants.quickReactions.length + 1,
                          separatorBuilder: (_, _) => const SizedBox(width: 4),
                          itemBuilder: (context, index) {
                            if (index == ApiConstants.quickReactions.length) {
                              return InkWell(
                                onTap: _openEmojiPickerForFloating,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceHighlight,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: AppColors.borderLight,
                                      width: 0.8,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.add_rounded,
                                    size: 14,
                                    color: AppColors.secondaryNeon,
                                  ),
                                ),
                              );
                            }
                            final emoji = ApiConstants.quickReactions[index];
                            return InkWell(
                              onTap: () {
                                AppHaptics.selection();
                                widget.chatController.sendReaction(emoji);
                                _scrollToBottom();
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                child: Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
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
                    // Emoji Picker for text input
                    IconButton(
                      icon: const Icon(
                        Icons.mood_rounded,
                        size: 22,
                        color: AppColors.textMuted,
                      ),
                      tooltip: 'Sisipkan Emoticon',
                      onPressed: _openEmojiPickerForInput,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
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

    final trimmedContent = msg.content.trim();
    final isSingleEmoji = msg.isReaction ||
        (trimmedContent.characters.length == 1 &&
            !RegExp(r'[a-zA-Z0-9\s]').hasMatch(trimmedContent));

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
                GestureDetector(
                  onLongPress: () => _showMessageReactionBar(msg),
                  child: Container(
                    padding: isSingleEmoji
                        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
                        : const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9.5),
                    decoration: BoxDecoration(
                      color: isSingleEmoji
                          ? Colors.transparent
                          : (isMe
                              ? (msg.status == MessageStatus.failed
                                  ? AppColors.accentRed.withValues(alpha: 0.2)
                                  : const Color(0xFF2B1F45))
                              : AppColors.surfaceElevated),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isMe ? 16 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 16),
                      ),
                      border: isSingleEmoji
                          ? null
                          : Border.all(
                              color: isMe
                                  ? (msg.status == MessageStatus.failed
                                      ? AppColors.accentRed
                                      : AppColors.primaryNeon.withValues(alpha: 0.5))
                                  : AppColors.borderLight,
                              width: 1,
                            ),
                      boxShadow: (!isSingleEmoji &&
                              msg.status != MessageStatus.failed)
                          ? [
                              BoxShadow(
                                color: isMe
                                    ? AppColors.primaryNeon.withValues(alpha: 0.12)
                                    : Colors.black.withValues(alpha: 0.15),
                                blurRadius: isMe ? 6 : 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      msg.content,
                      style: TextStyle(
                        fontSize: isSingleEmoji ? 30 : 13.5,
                        color: Colors.white,
                        fontWeight: isMe ? FontWeight.w500 : FontWeight.w400,
                        height: isSingleEmoji ? 1.2 : 1.35,
                      ),
                    ),
                  ),
                ),
                // Message Reaction Pills
                if (msg.hasReactions)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      alignment: isMe ? WrapAlignment.end : WrapAlignment.start,
                      children: msg.reactions.entries.map((entry) {
                        final emoji = entry.key;
                        final count = entry.value.length;
                        if (count == 0) return const SizedBox.shrink();
                        final hasReacted =
                            entry.value.contains(widget.chatController.currentUser.id);

                        return Material(
                          color: hasReacted
                              ? AppColors.primaryNeon.withValues(alpha: 0.25)
                              : AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () {
                              AppHaptics.selection();
                              widget.chatController
                                  .toggleMessageReaction(msg.id, emoji);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: hasReacted
                                      ? AppColors.primaryNeon
                                      : AppColors.borderLight,
                                  width: hasReacted ? 1.2 : 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(emoji,
                                      style: const TextStyle(fontSize: 12)),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$count',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: hasReacted
                                          ? AppColors.primaryNeon
                                          : Colors.white70,
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
