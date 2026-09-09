import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../auth/domain/user_profile.dart';
import '../models/chat_message.dart';

class FloatingReaction {
  final String id;
  final String emoji;
  final double startX; // Normalized 0.0 to 1.0

  FloatingReaction({
    required this.id,
    required this.emoji,
    required this.startX,
  });
}

class ChatController extends ChangeNotifier {
  final String roomId;
  final UserProfile currentUser;
  final SupabaseClient? supabase;

  static const int maxInMemoryMessages = 150;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  void _pruneOldMessages() {
    if (_messages.length > maxInMemoryMessages) {
      _messages.removeRange(0, _messages.length - maxInMemoryMessages);
    }
  }

  final StreamController<FloatingReaction> _reactionsStreamController =
      StreamController<FloatingReaction>.broadcast();
  Stream<FloatingReaction> get reactionsStream =>
      _reactionsStreamController.stream;

  final Map<String, DateTime> _recentSystemMessages = {};

  final Map<String, String> _typingUsers = {};
  final Map<String, Timer> _typingTimers = {};
  Timer? _localTypingDebounceTimer;
  bool _isLocalTyping = false;

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
          _messages.add(message);
          _pruneOldMessages();
          notifyListeners();

          if (message.isReaction) {
            _triggerFloatingReaction(message.content);
          }
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
            .order('created_at', ascending: true)
            .limit(50);
      } catch (e) {
        debugPrint('[ChatController] Error loading history with profiles join: $e');
        response = await supabase!
            .from('room_messages')
            .select('*')
            .eq('room_id', roomId)
            .order('created_at', ascending: true)
            .limit(50);
      }

      final list = response as List<dynamic>;
      if (list.isNotEmpty) {
        bool addedAny = false;
        for (final item in list) {
          final msg = ChatMessage.fromJson(item as Map<String, dynamic>);
          if (!_messages.any((m) => m.id == msg.id)) {
            _messages.add(msg);
            addedAny = true;
          }
        }
        if (addedAny) {
          _pruneOldMessages();
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[ChatController] Error loading history: $e');
    }
  }

  void _triggerFloatingReaction(String emoji) {
    final reaction = FloatingReaction(
      id: const Uuid().v4(),
      emoji: emoji,
      startX: 0.2 + (DateTime.now().millisecond % 60) / 100.0,
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
      }
      _localTypingDebounceTimer?.cancel();
      _localTypingDebounceTimer = Timer(const Duration(seconds: 3), () {
        if (_isDisposed) return;
        setTyping(false);
      });
    } else {
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
  void handleTypingBroadcast(Map<String, dynamic> payload) {
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

  void _updateMessageStatus(String messageId, MessageStatus newStatus) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(status: newStatus);
      notifyListeners();
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
          },
        );

        if (supabase != null) {
          final payload = msg.toJson();
          if (supabase!.auth.currentUser == null ||
              supabase!.auth.currentUser!.id != currentUser.id) {
            payload.remove('user_id');
          }
          await supabase!.from('room_messages').insert(payload);
        }
        _updateMessageStatus(messageId, MessageStatus.sent);
      } catch (e) {
        debugPrint('[ChatController] Error retrying message: $e');
        _updateMessageStatus(messageId, MessageStatus.failed);
      }
    } else {
      _updateMessageStatus(messageId, MessageStatus.failed);
    }
  }

  /// Sends a chat message
  Future<void> sendMessage(String text) async {
    setTyping(false);
    final clean = text.trim();
    if (clean.isEmpty) return;

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
          },
        );

        if (supabase != null) {
          final payload = msg.toJson();
          if (supabase!.auth.currentUser == null ||
              supabase!.auth.currentUser!.id != currentUser.id) {
            payload.remove('user_id');
          }
          await supabase!.from('room_messages').insert(payload);
        }
        _updateMessageStatus(msg.id, MessageStatus.sent);
      } catch (e) {
        debugPrint('[ChatController] Error broadcasting message: $e');
        _updateMessageStatus(msg.id, MessageStatus.failed);
      }
    } else {
      _updateMessageStatus(msg.id, MessageStatus.failed);
    }
  }

  /// Sends an emoji reaction burst
  Future<void> sendReaction(String emoji) async {
    _triggerFloatingReaction(emoji);

    final msg = ChatMessage(
      id: const Uuid().v4(),
      roomId: roomId,
      userId: currentUser.id,
      username: currentUser.username,
      avatarUrl: currentUser.avatarUrl,
      content: emoji,
      type: 'emoji_reaction',
      createdAt: DateTime.now(),
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
          },
        );
      } catch (e) {
        debugPrint('[ChatController] Error sending reaction: $e');
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
    _localTypingDebounceTimer?.cancel();
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
