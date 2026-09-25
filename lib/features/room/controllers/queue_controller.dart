import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../auth/domain/user_profile.dart';
import '../../chat/controllers/chat_controller.dart';
import '../models/queue_item.dart';
import 'sync_controller.dart';

class QueueController extends ChangeNotifier {
  final String roomId;
  final UserProfile currentUser;
  final SyncController syncController;
  final ChatController? chatController;
  final SupabaseClient? supabase;
  final bool Function()? isHostProvider;
  final bool Function()? isCoHostProvider;
  final bool Function()? isCollaborativeProvider;

  List<QueueItem> _items = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _isDisposed = false;
  bool _isPoppingNext = false;
  RealtimeChannel? _realtimeChannel;

  List<QueueItem> get items => List.unmodifiable(_items);
  int get count => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get isHost => isHostProvider?.call() ?? false;
  bool get isCoHost => isCoHostProvider?.call() ?? false;
  bool get isCollaborative => isCollaborativeProvider?.call() ?? false;

  /// Whether current user has permission to manage (reorder, delete) items
  bool get canManageQueue => isHost || isCoHost || isCollaborative;

  /// Whether current user can add items to queue
  bool get canAddToQueue => isHost || isCoHost || isCollaborative;

  QueueController({
    required this.roomId,
    required this.currentUser,
    required this.syncController,
    this.chatController,
    this.supabase,
    this.isHostProvider,
    this.isCoHostProvider,
    this.isCollaborativeProvider,
  }) {
    _initChannel();
    _fetchInitialQueue();
  }

  void _initChannel() {
    if (supabase == null) return;
    try {
      final channelName = 'room_queue_$roomId';
      _realtimeChannel = supabase!.channel(channelName);

      _realtimeChannel!.onBroadcast(
        event: 'QUEUE_SYNC',
        callback: (Map<String, dynamic> payloadMap) {
          if (_isDisposed) return;
          _handleRemoteSync(payloadMap);
        },
      );

      _realtimeChannel!.onBroadcast(
        event: 'QUEUE_REQUEST',
        callback: (_) {
          if (_isDisposed) return;
          if (isHost && _items.isNotEmpty) {
            _broadcastQueueSync();
          }
        },
      );

      _realtimeChannel!.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          if (!isHost) {
            _requestRemoteQueue();
          }
        }
      });
    } catch (e) {
      debugPrint('[QueueController] Error subscribing to queue channel: $e');
    }
  }

  Future<void> _fetchInitialQueue() async {
    if (supabase == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      final response = await supabase!
          .from('room_queue')
          .select()
          .eq('room_id', roomId)
          .order('order_index', ascending: true);

      if (!_isDisposed) {
        final List<QueueItem> loaded = (response as List)
            .map((e) => QueueItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (loaded.isNotEmpty || _items.isEmpty) {
          _items = loaded;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[QueueController] Non-fatal initial queue fetch error: $e');
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void _requestRemoteQueue() {
    if (_realtimeChannel == null) return;
    try {
      _realtimeChannel!.sendBroadcastMessage(
        event: 'QUEUE_REQUEST',
        payload: {'requester_id': currentUser.id},
      );
    } catch (_) {}
  }

  void _handleRemoteSync(Map<String, dynamic> payload) {
    try {
      final senderId = payload['sender_id'] as String?;
      if (senderId == currentUser.id) return;

      final rawList = payload['items'] as List?;
      if (rawList != null) {
        _items = rawList
            .map((e) => QueueItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[QueueController] Error handling remote queue sync: $e');
    }
  }

  Future<void> _broadcastQueueSync() async {
    if (_realtimeChannel == null) return;
    try {
      await _realtimeChannel!.sendBroadcastMessage(
        event: 'QUEUE_SYNC',
        payload: {
          'sender_id': currentUser.id,
          'items': _items.map((i) => i.toJson()).toList(),
        },
      );
    } catch (e) {
      debugPrint('[QueueController] Broadcast queue failed: $e');
    }
  }

  /// Adds a new media item to the end of the queue
  Future<void> addToQueue({
    required String mediaType,
    required String mediaUrl,
    required String title,
    String? thumbnailUrl,
  }) async {
    if (!canAddToQueue) return;

    final newItem = QueueItem(
      id: const Uuid().v4(),
      roomId: roomId,
      mediaType: mediaType,
      mediaUrl: mediaUrl,
      title: title.trim().isEmpty ? 'Video' : title.trim(),
      thumbnailUrl: thumbnailUrl,
      addedByUserId: currentUser.id,
      addedByUserName: currentUser.username,
      orderIndex: _items.length,
      createdAt: DateTime.now(),
    );

    _items.add(newItem);
    notifyListeners();
    _broadcastQueueSync();

    // Notify room in chat
    chatController?.sendSystemMessage(
      '${currentUser.username} menambahkan "${newItem.title}" ke antrean.',
    );

    // Persist to database if available
    if (supabase != null) {
      try {
        await supabase!.from('room_queue').insert(newItem.toJson());
      } catch (e) {
        debugPrint('[QueueController] Database insert queue error (non-fatal): $e');
      }
    }
  }

  /// Removes an item from the queue by ID
  Future<void> removeFromQueue(String itemId) async {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1) return;

    final item = _items[index];
    final bool canDelete = isHost ||
        (isCollaborative && item.addedByUserId == currentUser.id) ||
        isCollaborative;
    if (!canDelete) return;

    _items.removeAt(index);
    for (int i = 0; i < _items.length; i++) {
      _items[i] = _items[i].copyWith(orderIndex: i);
    }
    notifyListeners();
    _broadcastQueueSync();

    if (supabase != null) {
      try {
        await supabase!.from('room_queue').delete().eq('id', itemId);
      } catch (e) {
        debugPrint('[QueueController] Database delete queue error (non-fatal): $e');
      }
    }
  }

  /// Reorders items in the queue (drag & drop)
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (!canManageQueue) return;
    if (oldIndex < 0 || oldIndex >= _items.length) return;
    if (newIndex < 0 || newIndex >= _items.length) return;
    if (oldIndex == newIndex) return;

    final item = _items.removeAt(oldIndex);
    _items.insert(newIndex, item);

    for (int i = 0; i < _items.length; i++) {
      _items[i] = _items[i].copyWith(orderIndex: i);
    }
    notifyListeners();
    _broadcastQueueSync();

    if (supabase != null) {
      try {
        for (final q in _items) {
          await supabase!
              .from('room_queue')
              .update({'order_index': q.orderIndex})
              .eq('id', q.id);
        }
      } catch (e) {
        debugPrint('[QueueController] Database reorder error (non-fatal): $e');
      }
    }
  }

  /// Pops the next item from the queue and immediately starts playback
  Future<void> playNext() async {
    if (_isPoppingNext || _items.isEmpty) return;
    _isPoppingNext = true;
    try {
      final nextItem = _items.removeAt(0);

      for (int i = 0; i < _items.length; i++) {
        _items[i] = _items[i].copyWith(orderIndex: i);
      }
      notifyListeners();
      _broadcastQueueSync();

      if (supabase != null) {
        try {
          await supabase!.from('room_queue').delete().eq('id', nextItem.id);
        } catch (_) {}
      }

      chatController?.sendSystemMessage(
        'Memutar "${nextItem.title}" dari antrean.',
      );

      await syncController.requestChangeMedia(
        nextItem.mediaType,
        nextItem.mediaUrl,
      );
    } finally {
      _isPoppingNext = false;
    }
  }

  /// Directly plays a specific queue item and removes it from the queue
  Future<void> playItem(QueueItem item) async {
    _items.removeWhere((i) => i.id == item.id);
    for (int i = 0; i < _items.length; i++) {
      _items[i] = _items[i].copyWith(orderIndex: i);
    }
    notifyListeners();
    _broadcastQueueSync();

    if (supabase != null) {
      try {
        await supabase!.from('room_queue').delete().eq('id', item.id);
      } catch (_) {}
    }

    chatController?.sendSystemMessage(
      '${currentUser.username} memutar "${item.title}" dari antrean.',
    );

    await syncController.requestChangeMedia(
      item.mediaType,
      item.mediaUrl,
    );
  }

  /// Clears all queue items
  Future<void> clearQueue() async {
    if (!canManageQueue) return;
    _items.clear();
    notifyListeners();
    _broadcastQueueSync();

    if (supabase != null) {
      try {
        await supabase!.from('room_queue').delete().eq('room_id', roomId);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    if (_realtimeChannel != null && supabase != null) {
      supabase!.removeChannel(_realtimeChannel!);
    }
    super.dispose();
  }
}
