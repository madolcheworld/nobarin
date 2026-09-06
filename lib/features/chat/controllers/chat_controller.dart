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

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  final StreamController<FloatingReaction> _reactionsStreamController =
      StreamController<FloatingReaction>.broadcast();
  Stream<FloatingReaction> get reactionsStream =>
      _reactionsStreamController.stream;

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
    // Add welcome system message
    _messages.add(ChatMessage(
      id: const Uuid().v4(),
      roomId: roomId,
      content: 'Selamat datang di Watch Party! Pesan kamu akan muncul di sini.',
      type: 'system',
      createdAt: DateTime.now(),
    ));

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
          _messages.add(message);
          notifyListeners();

          if (message.isReaction) {
            _triggerFloatingReaction(message.content);
          }
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

  /// Sends a chat message
  Future<void> sendMessage(String text) async {
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
    );

    _messages.add(msg);
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
      } catch (e) {
        debugPrint('[ChatController] Error broadcasting message: $e');
      }
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

    final msg = ChatMessage(
      id: const Uuid().v4(),
      roomId: roomId,
      content: clean,
      type: 'system',
      createdAt: DateTime.now(),
    );

    _messages.add(msg);
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
    _reactionsStreamController.close();
    if (_chatChannel != null && supabase != null) {
      supabase!.removeChannel(_chatChannel!);
    }
    super.dispose();
  }
}
