import 'package:flutter/material.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/time_formatter.dart';
import '../controllers/chat_controller.dart';
import '../models/chat_message.dart';

class ChatPanelWidget extends StatefulWidget {
  final ChatController chatController;
  final bool showReactions;

  const ChatPanelWidget({
    super.key,
    required this.chatController,
    this.showReactions = true,
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
  }

  @override
  void didUpdateWidget(covariant ChatPanelWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatController != widget.chatController) {
      oldWidget.chatController.removeListener(_handleChatUpdate);
      _lastMessageCount = widget.chatController.messages.length;
      widget.chatController.addListener(_handleChatUpdate);
    }
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
    widget.chatController.removeListener(_handleChatUpdate);
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
                child: ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                          hintText: 'Tulis pesan chat...',
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
                    child: Text(
                      msg.username,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondaryNeon,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: isMe
                        ? AppColors.primaryNeon.withValues(alpha: 0.85)
                        : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(14),
                      topRight: const Radius.circular(14),
                      bottomLeft: Radius.circular(isMe ? 14 : 2),
                      bottomRight: Radius.circular(isMe ? 2 : 14),
                    ),
                    border: Border.all(
                      color: isMe
                          ? AppColors.primaryNeon
                          : AppColors.border,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    msg.content,
                    style: TextStyle(
                      fontSize: msg.isReaction ? 24 : 13,
                      color: Colors.white,
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.only(top: 2, left: 4, right: 4),
                  child: Text(
                    TimeFormatter.formatChatTime(msg.createdAt),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
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
}
