import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _ChatPanelWidgetState extends State<ChatPanelWidget>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _lastMessageId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final msgs = widget.chatController.messages;
    _lastMessageId = msgs.isNotEmpty ? msgs.last.id : null;
    widget.chatController.addListener(_handleChatUpdate);
    _inputController.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didUpdateWidget(covariant ChatPanelWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatController != widget.chatController) {
      oldWidget.chatController.setTyping(false);
      oldWidget.chatController.removeListener(_handleChatUpdate);
      final msgs = widget.chatController.messages;
      _lastMessageId = msgs.isNotEmpty ? msgs.last.id : null;
      widget.chatController.addListener(_handleChatUpdate);
    }
  }

  void _onTextChanged() {
    final hasText = _inputController.text.trim().isNotEmpty;
    widget.chatController.setTyping(hasText);
  }

  void _handleChatUpdate() {
    final msgs = widget.chatController.messages;
    final latestId = msgs.isNotEmpty ? msgs.last.id : null;
    if (latestId != _lastMessageId) {
      _lastMessageId = latestId;
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
    final currentUserId = widget.chatController.currentUser.id;
    final isMe = msg.userId == currentUserId;
    final isHostOrCoHost = (widget.hostId != null && widget.hostId == currentUserId) ||
        widget.coHostUserIds.contains(currentUserId);
    final canDelete = isMe || isHostOrCoHost;
    final snippet = msg.content.characters.length > 25
        ? '${msg.content.characters.take(25)}...'
        : msg.content;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
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
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                'Aksi untuk ${msg.username}: "$snippet"',
                style:
                    const TextStyle(fontSize: 12, color: AppColors.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              // Emojis row
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
              const Divider(color: AppColors.border, height: 24, thickness: 0.8),
              // Actions List
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: const Icon(Icons.copy_rounded, size: 20, color: AppColors.textPrimary),
                title: const Text('Salin Pesan', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Clipboard.setData(ClipboardData(text: msg.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Pesan disalin ke clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              if (!isMe && msg.userId != null && msg.userId!.isNotEmpty)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.flag_outlined, size: 20, color: AppColors.accentRed),
                  title: const Text('Laporkan Pesan', style: TextStyle(fontSize: 13, color: AppColors.accentRed)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showReportDialog(msg);
                  },
                ),
              if (!isMe && msg.userId != null && msg.userId!.isNotEmpty)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.block_rounded, size: 20, color: AppColors.textMuted),
                  title: Text('Blokir ${msg.username}', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showBlockUserConfirmation(msg);
                  },
                ),
              if (canDelete)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.accentRed),
                  title: const Text('Hapus Pesan', style: TextStyle(fontSize: 13, color: AppColors.accentRed)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    widget.chatController.deleteMessage(msg.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Pesan telah dihapus'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showReportDialog(ChatMessage msg) {
    const reasons = [
      'Spam atau iklan',
      'Ujaran kebencian / pelecehan',
      'Konten pornografi atau vulgar',
      'Pelanggaran hak cipta',
      'Penipuan atau aktivitas berbahaya',
      'Lainnya',
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.flag_rounded, color: AppColors.accentRed, size: 22),
            SizedBox(width: 8),
            Text('Laporkan Pesan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Laporkan konten dari ${msg.username}. Pilih alasan pelaporan:',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            ...reasons.map(
              (reason) => InkWell(
                onTap: () {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.surfaceElevated,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: AppColors.primaryNeon, width: 0.8),
                      ),
                      content: const Text(
                        'Laporan Anda telah diterima dan akan ditinjau tim moderator. Terima kasih.',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      ),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          reason,
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal', style: TextStyle(color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  void _showBlockUserConfirmation(ChatMessage msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(
          'Blokir ${msg.username}?',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        content: Text(
          'Pesan dari pengguna ${msg.username} tidak akan lagi ditampilkan pada layar Anda selama sesi room.',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              if (msg.userId != null) {
                widget.chatController.blockUser(msg.userId!);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${msg.username} berhasil diblokir'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Blokir'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
                              color: AppColors.textMuted.withValues(alpha: 0.65),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Belum ada pesan',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
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

              // Quick Reactions Row (Responsive & Polished across any screen size)
              if (widget.showReactions) _buildQuickReactionsBar(),

              // Typing Indicator Banner
              _buildTypingIndicator(widget.chatController.typingStatusText),

              // Input Bar
              Container(
                decoration: BoxDecoration(
                  color: AppColors.glassFillHeavy,
                  border: Border(
                    top: BorderSide(color: AppColors.glassBorder, width: 0.9),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                            maxLength: 500,
                            buildCounter: (context,
                                    {required currentLength,
                                    required isFocused,
                                    required maxLength}) =>
                                null,
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
                            tooltip: 'Kirim pesan',
                            icon: const Icon(Icons.send_rounded,
                                size: 18, color: Colors.white),
                            onPressed: _sendMessage,
                          ),
                        ),
                      ],
                    ),
                  ),
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
    final isHost = widget.hostId != null &&
        widget.hostId!.isNotEmpty &&
        msg.userId == widget.hostId;
    final isCoHost = widget.coHostUserIds.contains(msg.userId);

    final trimmedContent = msg.content.trim();
    final bool isAsciiOrSymbol = trimmedContent.runes.any((r) => r <= 127);
    final isSingleEmoji = msg.isReaction ||
        (!isAsciiOrSymbol && trimmedContent.characters.length == 1);

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
                                  : AppColors.chatBubbleSelf)
                              : AppColors.glassFill),
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
                                      : AppColors.primaryNeon.withValues(alpha: 0.45))
                                  : AppColors.glassBorder,
                              width: 1,
                            ),
                      boxShadow: (!isSingleEmoji &&
                              msg.status != MessageStatus.failed)
                          ? [
                              BoxShadow(
                                color: isMe
                                    ? AppColors.primaryNeon.withValues(alpha: 0.15)
                                    : Colors.black.withValues(alpha: 0.20),
                                blurRadius: isMe ? 8 : 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      msg.content,
                      style: TextStyle(
                        fontSize: isSingleEmoji ? 30 : 14.0,
                        color: AppColors.textPrimary,
                        fontWeight: isMe ? FontWeight.w500 : FontWeight.w400,
                        height: isSingleEmoji ? 1.2 : 1.4,
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

  Widget _buildQuickReactionsBar() {
    final emojis = ApiConstants.quickReactions;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 0.8),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double maxBarWidth =
              constraints.maxWidth > 520 ? 520 : constraints.maxWidth;
          final bool isVeryNarrow = constraints.maxWidth < 340;

          if (isVeryNarrow) {
            return SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: emojis.length + 2,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  if (index == emojis.length) {
                    return _buildAddReactionButton(compact: true);
                  }
                  if (index == emojis.length + 1) {
                    return _buildToggleVisibilityButton(compact: true);
                  }
                  return _buildQuickReactionItem(emojis[index], compact: true);
                },
              ),
            );
          }

          // Responsive Evenly Distributed Bar across full screen width
          return Center(
            child: SizedBox(
              width: maxBarWidth,
              height: 38,
              child: Row(
                children: [
                  for (final emoji in emojis)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _buildQuickReactionItem(emoji),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _buildAddReactionButton(),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _buildToggleVisibilityButton(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickReactionItem(String emoji, {bool compact = false}) {
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {
          AppHaptics.selection();
          widget.chatController.sendReaction(emoji);
          _scrollToBottom();
        },
        borderRadius: BorderRadius.circular(10),
        splashColor: AppColors.primaryNeon.withValues(alpha: 0.25),
        highlightColor: AppColors.primaryNeon.withValues(alpha: 0.1),
        child: Container(
          width: compact ? 38 : null,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.border.withValues(alpha: 0.6),
              width: 0.8,
            ),
          ),
          child: Text(
            emoji,
            style: const TextStyle(fontSize: 19, height: 1.1),
          ),
        ),
      ),
    );
  }

  Widget _buildAddReactionButton({bool compact = false}) {
    return Material(
      color: AppColors.surfaceHighlight.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: _openEmojiPickerForFloating,
        borderRadius: BorderRadius.circular(10),
        splashColor: AppColors.secondaryNeon.withValues(alpha: 0.25),
        child: Container(
          width: compact ? 38 : null,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.borderLight.withValues(alpha: 0.8),
              width: 0.8,
            ),
          ),
          child: const Icon(
            Icons.add_rounded,
            size: 18,
            color: AppColors.secondaryNeon,
          ),
        ),
      ),
    );
  }

  Widget _buildToggleVisibilityButton({bool compact = false}) {
    final isEnabled = widget.chatController.showFloatingReactions;
    return Material(
      color: isEnabled
          ? AppColors.primaryNeon.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {
          AppHaptics.light();
          widget.chatController.toggleFloatingReactions();
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              duration: const Duration(milliseconds: 1500),
              backgroundColor: AppColors.surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color:
                      isEnabled ? AppColors.textMuted : AppColors.primaryNeon,
                  width: 0.8,
                ),
              ),
              content: Row(
                children: [
                  Icon(
                    !isEnabled
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 16,
                    color: !isEnabled
                        ? AppColors.primaryNeon
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      !isEnabled
                          ? 'Reaksi melayang di video ditampilkan'
                          : 'Reaksi melayang di video disembunyikan',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(10),
        splashColor: AppColors.primaryNeon.withValues(alpha: 0.25),
        child: Container(
          width: compact ? 38 : null,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isEnabled
                  ? AppColors.primaryNeon.withValues(alpha: 0.5)
                  : AppColors.border.withValues(alpha: 0.6),
              width: 0.8,
            ),
          ),
          child: Tooltip(
            message: isEnabled
                ? 'Sembunyikan reaksi melayang di video'
                : 'Tampilkan reaksi melayang di video',
            child: Icon(
              isEnabled
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              size: 18,
              color: isEnabled ? AppColors.primaryNeon : AppColors.textMuted,
            ),
          ),
        ),
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
