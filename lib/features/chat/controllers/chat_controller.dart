import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../core/utils/app_haptics.dart';
import '../../auth/domain/user_profile.dart';
import '../models/chat_message.dart';

class FloatingReaction {
  final String id;
  final String emoji;
  final double startX; // Normalized 0.0 to 1.0
  final int comboCount;
  final String? senderName;
  final bool isLocal;

  FloatingReaction({
    required this.id,
    required this.emoji,
    required this.startX,
    this.comboCount = 1,
    this.senderName,
    this.isLocal = false,
  });
}

class ChatController extends ChangeNotifier {
  final String roomId;
  final UserProfile currentUser;
  final SupabaseClient? supabase;

  static const int maxInMemoryMessages = 150;

  final List<ChatMessage> _messages = [];
  final Set<String> _blockedUserIds = {};
  Set<String> get blockedUserIds => Set.unmodifiable(_blockedUserIds);

  /// Returns messages filtered by blocked users
  List<ChatMessage> get messages => List.unmodifiable(
        _messages.where(
          (m) => m.userId == null || !_blockedUserIds.contains(m.userId),
        ),
      );

  void blockUser(String userId) {
    if (userId.isEmpty || userId == currentUser.id) return;
    _blockedUserIds.add(userId);
    notifyListeners();
  }

  void unblockUser(String userId) {
    if (_blockedUserIds.remove(userId)) {
      notifyListeners();
    }
  }

  bool isUserBlocked(String? userId) =>
      userId != null && _blockedUserIds.contains(userId);

  void _pruneOldMessages() {
    if (_messages.length > maxInMemoryMessages) {
      _messages.removeRange(0, _messages.length - maxInMemoryMessages);
    }
  }

  final StreamController<FloatingReaction> _reactionsStreamController =
      StreamController<FloatingReaction>.broadcast();
  Stream<FloatingReaction> get reactionsStream =>
      _reactionsStreamController.stream;

  bool _showFloatingReactions = true;
  bool get showFloatingReactions => _showFloatingReactions;

  void toggleFloatingReactions() {
    _showFloatingReactions = !_showFloatingReactions;
    notifyListeners();
  }

  final Map<String, DateTime> _recentSystemMessages = {};

  final Map<String, String> _typingUsers = {};
  final Map<String, Timer> _typingTimers = {};
  Timer? _localTypingDebounceTimer;
  Timer? _typingHeartbeatTimer;
  bool _isLocalTyping = false;

  String? _lastReactionEmoji;
  DateTime? _lastReactionTime;
  int _localReactionCombo = 1;
  Timer? _reactionBroadcastDebounceTimer;

  List<String> get typingUsernames => _typingUsers.values.toList();
  bool get hasTypingUsers => _typingUsers.isNotEmpty;

  String? get typingStatusText {
    if (_typingUsers.isEmpty) return null;
    final names = _typingUsers.values.toList();
    if (names.length == 1) {
      return '${names[0]} sedang mengetik...';
    } else if (names.length == 2) {
      return '${names[0]} dan ${names[1]} sedang mengetik...';
    } else {
      return '${names[0]} dan ${names.length - 1} lainnya sedang mengetik...';
    }
  }

  RealtimeChannel? _chatChannel;
  bool _isDisposed = false;

  ChatController({
    required this.roomId,
    required this.currentUser,
    this.supabase,
  }) {
    _initChat();
  }

  void _initChat() {
    if (supabase == null) return;

    try {
      final channelName = 'chat_$roomId';
      _chatChannel = supabase!.channel(channelName);

      _chatChannel!.onBroadcast(
        event: 'NEW_MESSAGE',
        callback: (payload) {
          if (_isDisposed) return;
          final message = ChatMessage.fromJson(payload);
          // Deduplicate if already added locally (e.g. sender self-broadcast echo)
          if (_messages.any((m) => m.id == message.id)) {
            return;
          }
          // Deduplicate system messages with identical content within 6 seconds
          if (message.isSystem &&
              _messages.reversed.take(6).any((m) =>
                  m.isSystem &&
                  m.content == message.content &&
                  DateTime.now().difference(m.createdAt).inSeconds.abs() < 6)) {
            return;
          }

          if (message.isReaction) {
            final combo = (payload['combo'] as num?)?.toInt() ?? 1;
            final rawEmoji = (payload['raw_emoji'] as String?) ??
                message.content.split(' ').first;
            _triggerFloatingReaction(
              rawEmoji,
              comboCount: combo,
              senderName: message.username,
              isLocal: false,
            );

            // Aggregate consecutive reactions from the same user within 5 seconds
            if (_messages.isNotEmpty) {
              final lastMsg = _messages.last;
              if (lastMsg.isReaction &&
                  lastMsg.userId == message.userId &&
                  lastMsg.content.startsWith(rawEmoji) &&
                  message.createdAt.difference(lastMsg.createdAt).inSeconds.abs() < 5) {
                _messages[_messages.length - 1] = lastMsg.copyWith(
                  content: message.content,
                  createdAt: message.createdAt,
                );
                notifyListeners();
                return;
              }
            }
          }

          _messages.add(message);
          _pruneOldMessages();
          notifyListeners();
        },
      );

      _chatChannel!.onBroadcast(
        event: 'MESSAGE_REACTION',
        callback: (payload) {
          if (_isDisposed) return;
          handleReactionToggledBroadcast(payload);
        },
      );

      _chatChannel!.onBroadcast(
        event: 'MESSAGE_DELETED',
        callback: (payload) {
          if (_isDisposed) return;
          handleMessageDeletedBroadcast(payload);
        },
      );

      _chatChannel!.onBroadcast(
        event: 'TYPING_STATUS',
        callback: (payload) {
          if (_isDisposed) return;
          handleTypingBroadcast(payload);
        },
      );

      _chatChannel!.subscribe();
      _loadHistory();
    } catch (e) {
      debugPrint('[ChatController] Error init chat channel: $e');
    }
  }

  Future<void> _loadHistory() async {
    if (supabase == null) return;
    try {
      dynamic response;
      try {
        response = await supabase!
            .from('room_messages')
            .select('*, profiles(username, avatar_url)')
            .eq('room_id', roomId)
            .order('created_at', ascending: false)
            .limit(50);
      } catch (e) {
        debugPrint('[ChatController] Error loading history with profiles join: $e');
        response = await supabase!
            .from('room_messages')
            .select('*')
            .eq('room_id', roomId)
            .order('created_at', ascending: false)
            .limit(50);
      }

      final list = response as List<dynamic>;
      if (list.isNotEmpty) {
        final reversedList = list.reversed.toList();
        bool addedAny = false;
        for (final item in reversedList) {
          final msg = ChatMessage.fromJson(item as Map<String, dynamic>);
          if (!_messages.any((m) => m.id == msg.id)) {
            _messages.add(msg);
            addedAny = true;
          }
        }
        if (addedAny) {
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          _pruneOldMessages();
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[ChatController] Error loading history: $e');
    }
  }

  void _triggerFloatingReaction(
    String emoji, {
    int comboCount = 1,
    String? senderName,
    bool isLocal = false,
  }) {
    if (!_showFloatingReactions) return;
    final reaction = FloatingReaction(
      id: const Uuid().v4(),
      emoji: emoji,
      // Confine startX to right side track (78% - 93% width) to avoid blocking subtitles and center video
      startX: 0.78 + (DateTime.now().millisecond % 15) / 100.0,
      comboCount: comboCount,
      senderName: senderName,
      isLocal: isLocal,
    );
    _reactionsStreamController.add(reaction);
  }

  /// Updates local typing status and dispatches broadcast if changed
  void setTyping(bool isTyping) {
    if (_isDisposed) return;

    if (isTyping) {
      if (!_isLocalTyping) {
        _isLocalTyping = true;
        _broadcastTypingStatus(true);
        _typingHeartbeatTimer?.cancel();
        _typingHeartbeatTimer = Timer.periodic(
          const Duration(milliseconds: 2500),
          (timer) {
            if (_isDisposed || !_isLocalTyping) {
              timer.cancel();
              return;
            }
            _broadcastTypingStatus(true);
          },
        );
      }
      _localTypingDebounceTimer?.cancel();
      _localTypingDebounceTimer = Timer(const Duration(seconds: 4), () {
        if (_isDisposed) return;
        setTyping(false);
      });
    } else {
      _typingHeartbeatTimer?.cancel();
      _typingHeartbeatTimer = null;
      _localTypingDebounceTimer?.cancel();
      _localTypingDebounceTimer = null;
      if (_isLocalTyping) {
        _isLocalTyping = false;
        _broadcastTypingStatus(false);
      }
    }
  }

  Future<void> _broadcastTypingStatus(bool isTyping) async {
    if (_chatChannel == null || _isDisposed) return;
    try {
      await _chatChannel!.sendBroadcastMessage(
        event: 'TYPING_STATUS',
        payload: {
          'user_id': currentUser.id,
          'username': currentUser.username,
          'is_typing': isTyping,
        },
      );
    } catch (e) {
      debugPrint('[ChatController] Error broadcasting typing status: $e');
    }
  }

  @visibleForTesting
  void handleTypingBroadcast(Map<String, dynamic> raw) {
    final payload = (raw['payload'] is Map)
        ? Map<String, dynamic>.from(raw['payload'] as Map)
        : raw;
    final userId = payload['user_id'] as String?;
    final username = payload['username'] as String?;
    final isTyping = payload['is_typing'] as bool? ?? false;

    if (userId == null || userId == currentUser.id) return;

    if (isTyping) {
      _typingUsers[userId] =
          (username != null && username.isNotEmpty) ? username : 'Seseorang';
      _typingTimers[userId]?.cancel();
      _typingTimers[userId] = Timer(const Duration(seconds: 4), () {
        if (_isDisposed) return;
        _typingUsers.remove(userId);
        _typingTimers.remove(userId);
        notifyListeners();
      });
      notifyListeners();
    } else {
      _typingTimers[userId]?.cancel();
      _typingTimers.remove(userId);
      if (_typingUsers.remove(userId) != null) {
        notifyListeners();
      }
    }
  }

  @visibleForTesting
  void addMessage(ChatMessage message) {
    _messages.add(message);
    notifyListeners();
  }

  @visibleForTesting
  void handleReactionToggledBroadcast(Map<String, dynamic> raw) {
    final data = (raw['payload'] is Map)
        ? Map<String, dynamic>.from(raw['payload'] as Map)
        : raw;
    final msgId = data['message_id'] as String?;
    if (msgId == null) return;
    final index = _messages.indexWhere((m) => m.id == msgId);
    if (index == -1) return;

    final action = data['action'] as String?;
    final userId = data['user_id'] as String?;
    final emoji = data['emoji'] as String?;

    if (action != null && userId != null && emoji != null) {
      final msg = _messages[index];
      final updatedReactions = Map<String, List<String>>.from(
        msg.reactions.map((k, v) => MapEntry(k, List<String>.from(v))),
      );
      final users = updatedReactions[emoji] ?? [];
      if (action == 'add') {
        if (!users.contains(userId)) {
          users.add(userId);
          updatedReactions[emoji] = users;
        }
      } else if (action == 'remove') {
        users.remove(userId);
        if (users.isEmpty) {
          updatedReactions.remove(emoji);
        } else {
          updatedReactions[emoji] = users;
        }
      }
      _messages[index] = msg.copyWith(reactions: updatedReactions);
      notifyListeners();
    } else {
      final reactionsRaw = data['reactions'];
      final Map<String, List<String>> updatedReactions = {};
      if (reactionsRaw is Map) {
        reactionsRaw.forEach((k, v) {
          if (v is List) {
            updatedReactions[k.toString()] =
                v.map((e) => e.toString()).toList();
          }
        });
      }
      _messages[index] =
          _messages[index].copyWith(reactions: updatedReactions);
      notifyListeners();
    }
  }

  @visibleForTesting
  void handleMessageDeletedBroadcast(Map<String, dynamic> raw) {
    final data = (raw['payload'] is Map)
        ? Map<String, dynamic>.from(raw['payload'] as Map)
        : raw;
    final msgId = data['message_id'] as String?;
    if (msgId == null) return;
    final index = _messages.indexWhere((m) => m.id == msgId);
    if (index != -1) {
      _messages.removeAt(index);
      notifyListeners();
    }
  }

  void _updateMessageStatus(String messageId, MessageStatus newStatus) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(status: newStatus);
      notifyListeners();
    }
  }

  /// Deletes a message from memory, broadcasts the deletion, and removes from DB
  Future<void> deleteMessage(String messageId) async {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    _messages.removeAt(index);
    notifyListeners();

    if (_chatChannel != null) {
      try {
        await _chatChannel!.sendBroadcastMessage(
          event: 'MESSAGE_DELETED',
          payload: {'message_id': messageId},
        );
      } catch (e) {
        debugPrint('[ChatController] Error broadcasting message deletion: $e');
      }
    }

    if (supabase != null) {
      try {
        await supabase!
            .from('room_messages')
            .delete()
            .eq('id', messageId)
            .timeout(const Duration(seconds: 4));
      } catch (dbErr) {
        debugPrint('[ChatController] Error deleting message from DB: $dbErr');
      }
    }
  }

  /// Retries sending a previously failed message
  Future<void> retryMessage(String messageId) async {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    final msg = _messages[index];
    if (msg.status != MessageStatus.failed) return;

    _updateMessageStatus(messageId, MessageStatus.sending);

    if (_chatChannel != null) {
      try {
        await _chatChannel!.sendBroadcastMessage(
          event: 'NEW_MESSAGE',
          payload: {
            ...msg.toJson(),
            'username': currentUser.username,
            'avatar_url': currentUser.avatarUrl,
            'sender_name': currentUser.username,
            'sender_avatar': currentUser.avatarUrl,
          },
        );
        _updateMessageStatus(messageId, MessageStatus.sent);

        if (supabase != null) {
          final payload = msg.toJson();
          payload.remove('reactions');
          if (supabase!.auth.currentUser == null ||
              supabase!.auth.currentUser!.id != currentUser.id) {
            payload.remove('user_id');
          }
          try {
            await supabase!
                .from('room_messages')
                .insert(payload)
                .timeout(const Duration(seconds: 4));
          } catch (dbErr) {
            // Graceful fallback if schema does not have sender_name/sender_avatar yet
            if (dbErr.toString().contains('sender_name') ||
                dbErr.toString().contains('sender_avatar')) {
              payload.remove('sender_name');
              payload.remove('sender_avatar');
              try {
                await supabase!.from('room_messages').insert(payload);
              } catch (_) {}
            }
            debugPrint('[ChatController] DB persistence note on retry: $dbErr');
          }
        }
      } catch (e) {
        debugPrint('[ChatController] Error retrying message: $e');
        _updateMessageStatus(messageId, MessageStatus.failed);
      }
    } else {
      _updateMessageStatus(messageId, MessageStatus.failed);
    }
  }

  /// Sends a chat message with length validation and sanitization
  Future<void> sendMessage(String text) async {
    setTyping(false);
    var clean = text.trim();
    if (clean.isEmpty) return;

    // Enforce 500 characters max
    if (clean.length > 500) {
      clean = clean.substring(0, 500).trim();
    }
    // Collapse excessive consecutive newlines (max 2)
    clean = clean.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    final msg = ChatMessage(
      id: const Uuid().v4(),
      roomId: roomId,
      userId: currentUser.id,
      username: currentUser.username,
      avatarUrl: currentUser.avatarUrl,
      content: clean,
      type: 'text',
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
    );

    _messages.add(msg);
    _pruneOldMessages();
    notifyListeners();

    if (_chatChannel != null) {
      try {
        await _chatChannel!.sendBroadcastMessage(
          event: 'NEW_MESSAGE',
          payload: {
            ...msg.toJson(),
            'username': currentUser.username,
            'avatar_url': currentUser.avatarUrl,
            'sender_name': currentUser.username,
            'sender_avatar': currentUser.avatarUrl,
          },
        );
        _updateMessageStatus(msg.id, MessageStatus.sent);

        if (supabase != null) {
          final payload = msg.toJson();
          payload.remove('reactions');
          if (supabase!.auth.currentUser == null ||
              supabase!.auth.currentUser!.id != currentUser.id) {
            payload.remove('user_id');
          }
          try {
            await supabase!
                .from('room_messages')
                .insert(payload)
                .timeout(const Duration(seconds: 4));
          } catch (dbErr) {
            // Graceful fallback if schema does not have sender_name/sender_avatar yet
            if (dbErr.toString().contains('sender_name') ||
                dbErr.toString().contains('sender_avatar')) {
              payload.remove('sender_name');
              payload.remove('sender_avatar');
              try {
                await supabase!.from('room_messages').insert(payload);
              } catch (_) {}
            }
            debugPrint('[ChatController] DB insert note: $dbErr');
          }
        }
      } catch (e) {
        debugPrint('[ChatController] Error broadcasting message: $e');
        _updateMessageStatus(msg.id, MessageStatus.failed);
      }
    } else {
      _updateMessageStatus(msg.id, MessageStatus.failed);
    }
  }

  /// Sends an emoji reaction burst with combo tracking and chat aggregation
  Future<void> sendReaction(String emoji) async {
    final now = DateTime.now();
    if (_lastReactionEmoji == emoji &&
        _lastReactionTime != null &&
        now.difference(_lastReactionTime!).inMilliseconds < 1400) {
      _localReactionCombo++;
    } else {
      _localReactionCombo = 1;
    }
    _lastReactionEmoji = emoji;
    _lastReactionTime = now;

    final combo = _localReactionCombo;

    // Trigger tactile haptics only for the local user tapping the reaction
    if (combo >= 8) {
      AppHaptics.heavy();
    } else if (combo >= 4) {
      AppHaptics.medium();
    } else {
      AppHaptics.selection();
    }

    _triggerFloatingReaction(
      emoji,
      comboCount: combo,
      senderName: currentUser.username,
      isLocal: true,
    );

    // Check if we can aggregate into previous message in chat log
    if (_messages.isNotEmpty) {
      final lastMsg = _messages.last;
      if (lastMsg.isReaction &&
          lastMsg.userId == currentUser.id &&
          lastMsg.content.startsWith(emoji) &&
          now.difference(lastMsg.createdAt).inSeconds < 5) {
        final updatedContent = '$emoji x$combo';
        _messages[_messages.length - 1] = lastMsg.copyWith(
          content: updatedContent,
          createdAt: now,
        );
        notifyListeners();
        _scheduleBroadcastReaction(emoji, combo);
        return;
      }
    }

    final msg = ChatMessage(
      id: const Uuid().v4(),
      roomId: roomId,
      userId: currentUser.id,
      username: currentUser.username,
      avatarUrl: currentUser.avatarUrl,
      content: combo > 1 ? '$emoji x$combo' : emoji,
      type: 'emoji_reaction',
      createdAt: now,
    );

    _messages.add(msg);
    _pruneOldMessages();
    notifyListeners();

    _scheduleBroadcastReaction(emoji, combo, msg: msg);
  }

  void _scheduleBroadcastReaction(
    String emoji,
    int combo, {
    ChatMessage? msg,
  }) {
    _reactionBroadcastDebounceTimer?.cancel();
    _reactionBroadcastDebounceTimer = Timer(
      const Duration(milliseconds: 150),
      () => _broadcastReaction(emoji, combo, msg: msg),
    );
  }

  Future<void> _broadcastReaction(
    String emoji,
    int combo, {
    ChatMessage? msg,
  }) async {
    if (_chatChannel == null || _isDisposed) return;
    try {
      await _chatChannel!.sendBroadcastMessage(
        event: 'NEW_MESSAGE',
        payload: {
          if (msg != null) ...msg.toJson(),
          if (msg == null) ...{
            'id': const Uuid().v4(),
            'room_id': roomId,
            'user_id': currentUser.id,
            'content': '$emoji x$combo',
            'type': 'emoji_reaction',
            'created_at': DateTime.now().toIso8601String(),
          },
          'username': currentUser.username,
          'avatar_url': currentUser.avatarUrl,
          'sender_name': currentUser.username,
          'sender_avatar': currentUser.avatarUrl,
          'combo': combo,
          'raw_emoji': emoji,
        },
      );
    } catch (e) {
      debugPrint('[ChatController] Error broadcasting reaction: $e');
    }
  }

  /// Toggles an emoji reaction on a specific chat message bubble (atomic delta)
  Future<void> toggleMessageReaction(String messageId, String emoji) async {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    final msg = _messages[index];
    final currentReactions = Map<String, List<String>>.from(
      msg.reactions.map((k, v) => MapEntry(k, List<String>.from(v))),
    );
    final users = currentReactions[emoji] ?? [];
    final hasReacted = users.contains(currentUser.id);
    final action = hasReacted ? 'remove' : 'add';

    if (hasReacted) {
      users.remove(currentUser.id);
      if (users.isEmpty) {
        currentReactions.remove(emoji);
      } else {
        currentReactions[emoji] = users;
      }
    } else {
      users.add(currentUser.id);
      currentReactions[emoji] = users;
    }

    _messages[index] = msg.copyWith(reactions: currentReactions);
    notifyListeners();

    if (_chatChannel != null) {
      try {
        await _chatChannel!.sendBroadcastMessage(
          event: 'MESSAGE_REACTION',
          payload: {
            'message_id': messageId,
            'user_id': currentUser.id,
            'emoji': emoji,
            'action': action,
            'reactions': currentReactions,
          },
        );
      } catch (e) {
        debugPrint('[ChatController] Error broadcasting message reaction: $e');
      }
    }
  }

  /// Sends a system notification message (e.g. user joined, media changed)
  Future<void> sendSystemMessage(String content) async {
    final clean = content.trim();
    if (clean.isEmpty) return;

    final now = DateTime.now();
    final lastSent = _recentSystemMessages[clean];
    if (lastSent != null && now.difference(lastSent).inSeconds < 6) {
      return;
    }
    _recentSystemMessages[clean] = now;

    // Prune cache if it grows too large (prevent memory leak)
    if (_recentSystemMessages.length > 50) {
      _recentSystemMessages.clear();
      _recentSystemMessages[clean] = now;
    }

    final msg = ChatMessage(
      id: const Uuid().v4(),
      roomId: roomId,
      content: clean,
      type: 'system',
      createdAt: now,
    );

    _messages.add(msg);
    _pruneOldMessages();
    notifyListeners();

    if (_chatChannel != null) {
      try {
        await _chatChannel!.sendBroadcastMessage(
          event: 'NEW_MESSAGE',
          payload: msg.toJson(),
        );

        if (supabase != null) {
          final payload = msg.toJson();
          payload.remove('user_id');
          await supabase!.from('room_messages').insert(payload);
        }
      } catch (e) {
        debugPrint('[ChatController] Error broadcasting system message: $e');
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _typingHeartbeatTimer?.cancel();
    _typingHeartbeatTimer = null;
    _localTypingDebounceTimer?.cancel();
    _localTypingDebounceTimer = null;
    _reactionBroadcastDebounceTimer?.cancel();
    _reactionBroadcastDebounceTimer = null;
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _typingUsers.clear();
    _reactionsStreamController.close();
    if (_chatChannel != null && supabase != null) {
      supabase!.removeChannel(_chatChannel!);
    }
    super.dispose();
  }
}
