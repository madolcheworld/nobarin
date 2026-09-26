import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/network/supabase_client.dart';
import '../data/lobby_repository.dart';
import '../../room/controllers/unified_player_controller.dart';
import '../../room/models/room_model.dart';

final lobbyRepositoryProvider = Provider<LobbyRepository>((ref) {
  final client = SupabaseService().clientOrNull;
  return LobbyRepository(supabase: client);
});

class LobbyController extends StateNotifier<AsyncValue<List<RoomModel>>> {
  final LobbyRepository _repository;
  final SupabaseClient? supabase;
  RealtimeChannel? _roomsSubscription;

  String? get lastRepositoryError => _repository.lastError;

  LobbyController(this._repository, {this.supabase})
      : super(const AsyncValue.loading()) {
    refreshRooms();
    _initRealtimeSubscription();
  }

  void _initRealtimeSubscription() {
    final client = supabase;
    if (client == null) return;

    try {
      _roomsSubscription = client
          .channel('public:lobby_rooms')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'rooms',
            callback: (payload) {
              _handlePostgresChange(payload);
            },
          )
          .subscribe();
      debugPrint('[LobbyController] Subscribed to Supabase Realtime rooms changes');
    } catch (e) {
      debugPrint('[LobbyController] Realtime subscription error: $e');
    }
  }

  void _handlePostgresChange(PostgresChangePayload payload) {
    try {
      final event = payload.eventType;
      debugPrint('[LobbyController] Realtime event: $event');

      if (event == PostgresChangeEvent.delete) {
        final oldId = payload.oldRecord['id']?.toString();
        final oldCode = payload.oldRecord['code']?.toString();
        _removeRoomFromState(roomId: oldId, code: oldCode);
      } else if (event == PostgresChangeEvent.update) {
        final newRecord = payload.newRecord;
        final isPublic = newRecord['is_public'] as bool? ?? true;
        final currentState = newRecord['current_state'] as String? ?? '';
        final roomId = newRecord['id']?.toString();
        final code = newRecord['code']?.toString();

        if (!isPublic || currentState == 'closed') {
          _removeRoomFromState(roomId: roomId, code: code);
        } else {
          final updatedRoom = RoomModel.fromJson(newRecord);
          _upsertRoomInState(updatedRoom);
        }
      } else if (event == PostgresChangeEvent.insert) {
        final newRecord = payload.newRecord;
        final isPublic = newRecord['is_public'] as bool? ?? true;
        final currentState = newRecord['current_state'] as String? ?? '';

        if (isPublic && currentState != 'closed') {
          final newRoom = RoomModel.fromJson(newRecord);
          _upsertRoomInState(newRoom);
        }
      }
    } catch (e) {
      debugPrint('[LobbyController] Error handling postgres change: $e');
    }
  }

  void _removeRoomFromState({String? roomId, String? code}) {
    if (roomId == null && code == null) return;
    state.whenData((currentRooms) {
      final updated = currentRooms.where((r) {
        if (roomId != null && r.id == roomId) return false;
        if (code != null &&
            (r.code.toUpperCase() == code.toUpperCase() ||
                LobbyRepository.normalizeCode(r.code) ==
                    LobbyRepository.normalizeCode(code))) {
          return false;
        }
        return true;
      }).toList();
      state = AsyncValue.data(updated);
    });
  }

  void _upsertRoomInState(RoomModel room) {
    state.whenData((currentRooms) {
      final hostKey = LobbyRepository.extractHostKey(room);
      final index = currentRooms.indexWhere((r) =>
          r.id == room.id ||
          r.code.toUpperCase() == room.code.toUpperCase() ||
          LobbyRepository.normalizeCode(r.code) ==
              LobbyRepository.normalizeCode(room.code) ||
          (hostKey != null && LobbyRepository.extractHostKey(r) == hostKey));
      if (index >= 0) {
        final existing = currentRooms[index];
        final effectiveHostName = (room.hostName != null &&
                room.hostName!.isNotEmpty &&
                room.hostName != 'Host')
            ? room.hostName
            : (existing.hostName ?? room.hostName);
        final effectiveThumbnail = (room.thumbnailUrl != null &&
                room.thumbnailUrl!.isNotEmpty)
            ? room.thumbnailUrl
            : existing.thumbnailUrl;
        final mergedRoom = room.copyWith(
          hostName: effectiveHostName,
          thumbnailUrl: effectiveThumbnail,
          participantCount: room.participantCount > 1
              ? room.participantCount
              : existing.participantCount,
        );
        final list = List<RoomModel>.from(currentRooms);
        list[index] = mergedRoom;
        state = AsyncValue.data(list);
      } else {
        state = AsyncValue.data([room, ...currentRooms]);
      }
    });
  }

  /// Marks a room closed and removes it from local memory and lobby state immediately
  void markRoomClosedLocally(String roomId, {String? code}) {
    LobbyRepository.removeLocalRoom(roomId, code: code);
    _removeRoomFromState(roomId: roomId, code: code);
  }

  Future<void> refreshRooms() async {
    // Only transition to loading state if we don't already have data to prevent skeleton shimmer flickering
    if (!state.hasValue) {
      state = const AsyncValue.loading();
    }
    try {
      final rooms = await _repository.getPublicRooms();
      state = AsyncValue.data(rooms);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<RoomModel?> createRoom({
    required String title,
    String? description,
    required String hostId,
    required String hostName,
    bool isPublic = true,
    String controlMode = 'host_only',
    String? initialMediaType,
    String? initialMediaUrl,
    String? initialThumbnailUrl,
  }) async {
    try {
      final room = await _repository.createRoom(
        title: title,
        description: description,
        hostId: hostId,
        hostName: hostName,
        isPublic: isPublic,
        controlMode: controlMode,
        initialMediaType: initialMediaType,
        initialMediaUrl: initialMediaUrl,
        initialThumbnailUrl: initialThumbnailUrl,
      );
      await refreshRooms();
      return room;
    } catch (e) {
      return null;
    }
  }

  Future<RoomModel?> findRoomByCode(String code) async {
    final candidates = LobbyRepository.getCodeCandidates(code);
    final normalized = LobbyRepository.normalizeCode(code);

    // 1. Check if room is already present in current state
    final currentList = state.asData?.value;
    if (currentList != null && currentList.isNotEmpty) {
      for (final r in currentList) {
        if (r.currentState == 'closed') continue;
        final rNorm = LobbyRepository.normalizeCode(r.code);
        if (rNorm == normalized ||
            r.code.toUpperCase() == code.trim().toUpperCase() ||
            candidates.any((c) => rNorm == LobbyRepository.normalizeCode(c))) {
          return r;
        }
      }
    }

    // 2. Fetch from repository
    final room = await _repository.getRoomByCode(code);
    if (room != null && room.currentState != 'closed' && room.isPublic) {
      state.whenData((currentRooms) {
        if (!currentRooms.any((r) => r.id == room.id)) {
          state = AsyncValue.data([room, ...currentRooms]);
        }
      });
    }
    return (room != null && room.currentState != 'closed') ? room : null;
  }

  /// Deletes a room from repository and updates lobby state
  Future<void> deleteRoom(String roomId, {String? code}) async {
    // 1. Instantly remove locally from memory and state
    markRoomClosedLocally(roomId, code: code);

    // 2. Delete/close in repository and Supabase
    try {
      await _repository.deleteRoom(roomId, code: code);
    } catch (e) {
      // Ignored
    }
  }

  @override
  void dispose() {
    final client = supabase;
    if (_roomsSubscription != null && client != null) {
      try {
        client.removeChannel(_roomsSubscription!);
      } catch (_) {}
    }
    super.dispose();
  }
}

final lobbyControllerProvider =
    StateNotifierProvider<LobbyController, AsyncValue<List<RoomModel>>>((ref) {
  final repo = ref.watch(lobbyRepositoryProvider);
  return LobbyController(repo, supabase: repo.supabase);
});

enum LobbyFilterCategory {
  all,
  liveOnly,
  youtube,
  bstation,
  dailymotion,
  googleDrive,
  webBrowser,
  p2pFile,
}

final lobbySearchQueryProvider = StateProvider<String>((ref) => '');

final lobbyFilterCategoryProvider =
    StateProvider<LobbyFilterCategory>((ref) => LobbyFilterCategory.all);

final filteredRoomsProvider = Provider<List<RoomModel>>((ref) {
  final roomsAsync = ref.watch(lobbyControllerProvider);
  final rawQuery = ref.watch(lobbySearchQueryProvider).trim();
  final category = ref.watch(lobbyFilterCategoryProvider);
  final query = rawQuery.toLowerCase();
  final cleanQuery = rawQuery
      .replaceAll('-', '')
      .replaceAll('_', '')
      .replaceAll(RegExp(r'[\u2013\u2014\u2212]'), '')
      .replaceAll(' ', '')
      .toLowerCase();

  return roomsAsync.when(
    data: (rooms) {
      var result = rooms;

      // Filter by category
      if (category == LobbyFilterCategory.liveOnly) {
        result = result.where((r) => r.isPlaying).toList();
      } else if (category == LobbyFilterCategory.youtube) {
        result = result.where((r) => r.currentMediaType == 'youtube').toList();
      } else if (category == LobbyFilterCategory.bstation) {
        result = result
            .where((r) =>
                r.currentMediaType == 'bstation' ||
                r.currentMediaType == 'bilibili')
            .toList();
      } else if (category == LobbyFilterCategory.dailymotion) {
        result = result
            .where((r) => r.currentMediaType == 'dailymotion')
            .toList();
      } else if (category == LobbyFilterCategory.googleDrive) {
        result = result
            .where((r) =>
                r.currentMediaType == 'google_drive' ||
                r.currentMediaType == 'gdrive')
            .toList();
      } else if (category == LobbyFilterCategory.webBrowser) {
        result = result
            .where((r) => r.currentMediaType == 'web_browser')
            .toList();
      } else if (category == LobbyFilterCategory.p2pFile) {
        result = result
            .where((r) =>
                r.currentMediaType == 'direct_url' &&
                (r.currentMediaUrl?.startsWith('p2p://') == true ||
                 UnifiedPlayerController.isLocalFilePath(r.currentMediaUrl ?? '') ||
                 (r.currentMediaUrl != null &&
                  (r.currentMediaUrl!.contains(':8080') ||
                   r.currentMediaUrl!.contains('/stream')))))
            .toList();
      }

      // Filter by search query
      if (query.isEmpty) return result;
      return result.where((room) {
        final titleMatch = room.title.toLowerCase().contains(query);
        final hostMatch = (room.hostName ?? '').toLowerCase().contains(query);
        final rawCode = room.code.toLowerCase();
        final cleanCode = rawCode
            .replaceAll('-', '')
            .replaceAll('_', '')
            .replaceAll(RegExp(r'[\u2013\u2014\u2212]'), '')
            .replaceAll(' ', '');
        final codeMatch = rawCode.contains(query) ||
            cleanCode.contains(cleanQuery) ||
            (cleanQuery.isNotEmpty && cleanCode.endsWith(cleanQuery));
        return titleMatch || hostMatch || codeMatch;
      }).toList();
    },
    loading: () => [],
    error: (_, _) => [],
  );
});
