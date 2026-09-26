import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../room/models/room_model.dart';

class LobbyRepository {
  final SupabaseClient? supabase;
  String? lastError;

  LobbyRepository({this.supabase});

  /// In-memory mock rooms for fallback when offline or Supabase table not created yet
  static final List<RoomModel> _demoRooms = [
    RoomModel(
      id: 'mock-1',
      code: 'WP1001',
      title: 'Nobarin Santai Bareng',
      hostId: 'mock-host-1',
      hostName: 'AdminNobar',
      isPublic: true,
      controlMode: 'collaborative',
      currentMediaType: 'direct_url',
      currentMediaUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      thumbnailUrl: null,
      currentState: 'playing',
      currentPosition: 12.0,
      livekitRoomName: 'room_WP1001',
      createdAt: DateTime.now(),
      participantCount: 3,
    ),
    RoomModel(
      id: 'mock-2',
      code: 'WP2002',
      title: 'Nobarin Film Pendek',
      hostId: 'mock-host-2',
      hostName: 'Cinephile',
      isPublic: true,
      controlMode: 'host_only',
      currentMediaType: 'direct_url',
      currentMediaUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
      thumbnailUrl: null,
      currentState: 'playing',
      currentPosition: 64.0,
      livekitRoomName: 'room_WP2002',
      createdAt: DateTime.now(),
      participantCount: 5,
    ),
  ];

  /// Normalizes room code by extracting from URLs/paths, stripping symbols, and uppercasing
  static String normalizeCode(String input) {
    var raw = input.trim();
    if (raw.isEmpty) return '';

    // Strip zero-width and non-breaking space characters
    raw = raw.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u00A0]'), '');

    // Strip quotes and surrounding punctuation: " ' “ ” ‘ ’ `
    raw = raw.replaceAll(RegExp(r'["\u0027\u201C\u201D\u2018\u2019`]'), '');

    // Extract code from common prefixes like "Kode:", "Code:", "Room:", "Kode room:"
    final prefixMatch = RegExp(
      r'^(?:kode\s*room|room\s*code|kode|code|room)\s*[:=]\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(raw);
    if (prefixMatch != null) {
      raw = prefixMatch.group(1)!.trim();
    }

    // If input is a URL or path (e.g. http://.../room/WP1001 or /rooms/WP1001 or /join/WP1001 or ?room=WP1001)
    final urlMatch = RegExp(
      r'(?:room|rooms|join|r)[\/=]([a-zA-Z0-9_\-\u2013\u2014\u2212]+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (urlMatch != null) {
      raw = urlMatch.group(1)!;
    }

    // Strip leading hash (#) if any
    if (raw.startsWith('#')) {
      raw = raw.substring(1).trim();
    }

    // Normalize all unicode dashes/hyphens to ASCII hyphen
    raw = raw.replaceAll(RegExp(r'[\u2013\u2014\u2212]'), '-');

    // Strip trailing period or comma (e.g. if copied from end of a sentence: "WP1001.")
    raw = raw.replaceAll(RegExp(r'[.,;!]+$'), '');

    return raw.replaceAll('-', '').replaceAll('_', '').replaceAll(RegExp(r'\s+'), '').toUpperCase();
  }

  /// Generates all potential candidate variations of a room code for flexible matching.
  static List<String> getCodeCandidates(String input) {
    var raw = input.trim();
    if (raw.isEmpty) return [];

    // Strip zero-width and non-breaking space characters
    raw = raw.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u00A0]'), '');
    // Strip quotes
    raw = raw.replaceAll(RegExp(r'["\u0027\u201C\u201D\u2018\u2019`]'), '');
    // Normalize unicode dashes to ASCII hyphen
    raw = raw.replaceAll(RegExp(r'[\u2013\u2014\u2212]'), '-');

    final normalized = normalizeCode(raw);
    if (normalized.isEmpty) return [];

    final Set<String> candidates = {};
    candidates.add(normalized);

    if (normalized.startsWith('WP')) {
      final suffix = normalized.substring(2);
      if (suffix.isNotEmpty) {
        candidates.add('WP-$suffix');
        candidates.add(suffix);

        // Keystroke / OCR confusion: '0' vs 'O', '1' vs 'I'/'L'
        final swappedSuffix = suffix
            .replaceAll('O', '0')
            .replaceAll('I', '1')
            .replaceAll('L', '1');
        if (swappedSuffix != suffix) {
          candidates.add('WP$swappedSuffix');
          candidates.add('WP-$swappedSuffix');
          candidates.add(swappedSuffix);
        }
        final letterSwapped = suffix
            .replaceAll('0', 'O')
            .replaceAll('1', 'I');
        if (letterSwapped != suffix) {
          candidates.add('WP$letterSwapped');
          candidates.add('WP-$letterSwapped');
          candidates.add(letterSwapped);
        }
      }
    } else {
      candidates.add('WP$normalized');
      candidates.add('WP-$normalized');

      // Check if normalized has letters followed by digits (e.g. TEST99 -> TEST-99, 99)
      final letterDigitMatch = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(normalized);
      if (letterDigitMatch != null) {
        final prefix = letterDigitMatch.group(1)!;
        final digits = letterDigitMatch.group(2)!;
        candidates.add('$prefix-$digits');
        candidates.add(digits);
      }

      // Keystroke / OCR confusion: '0' vs 'O', '1' vs 'I'/'L'
      final swapped = normalized
          .replaceAll('O', '0')
          .replaceAll('I', '1')
          .replaceAll('L', '1');
      if (swapped != normalized) {
        candidates.add(swapped);
        candidates.add('WP$swapped');
        candidates.add('WP-$swapped');
      }
      final letterSwapped = normalized
          .replaceAll('0', 'O')
          .replaceAll('1', 'I');
      if (letterSwapped != normalized) {
        candidates.add(letterSwapped);
        candidates.add('WP$letterSwapped');
        candidates.add('WP-$letterSwapped');
      }
    }

    // Also include raw trimmed variations if clean
    final cleanRaw = raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (RegExp(r'^[A-Z0-9\-]+$').hasMatch(cleanRaw)) {
      candidates.add(cleanRaw);
    }

    return candidates.toList();
  }

  /// Generates a human-friendly 6-character room code (e.g. WP-93X2)
  String generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    final randomPart =
        List.generate(4, (index) => chars[random.nextInt(chars.length)]).join();
    return 'WP$randomPart';
  }

  /// Returns a normalized unique identity key for the host of a room
  static String? extractHostKey(RoomModel room) {
    if (room.hostId != null && room.hostId!.isNotEmpty) {
      return 'id:${room.hostId}';
    }
    final desc = room.description ?? '';
    final idMatch = RegExp(r'\[HOST:[^\]]*id=([^;\]]+)').firstMatch(desc);
    if (idMatch != null && idMatch.group(1) != null && idMatch.group(1)!.isNotEmpty) {
      return 'id:${idMatch.group(1)}';
    }
    final name = room.hostName?.trim();
    if (name != null && name.isNotEmpty) {
      return 'name:${name.toLowerCase()}';
    }
    return null;
  }

  /// Filters a list of rooms so that each host only has at most 1 active room (the newest).
  /// Any older duplicate rooms found are queued for deletion/cleanup in Supabase.
  List<RoomModel> deduplicateRooms(List<RoomModel> rooms) {
    final Set<String> seenHosts = {};
    final Set<String> seenCodes = {};
    final List<RoomModel> deduplicated = [];
    final List<RoomModel> staleDuplicates = [];

    for (final room in rooms) {
      if (room.currentState == 'closed' || !room.isPublic) continue;

      final normalizedCode = normalizeCode(room.code);
      if (seenCodes.contains(normalizedCode)) {
        staleDuplicates.add(room);
        continue;
      }
      seenCodes.add(normalizedCode);

      final hostKey = extractHostKey(room);
      if (hostKey != null) {
        if (seenHosts.contains(hostKey)) {
          staleDuplicates.add(room);
          continue;
        }
        seenHosts.add(hostKey);
      }

      deduplicated.add(room);
    }

    // Background auto-cleanup of stale duplicates in Supabase
    if (staleDuplicates.isNotEmpty && supabase != null) {
      for (final stale in staleDuplicates) {
        deleteRoom(stale.id, code: stale.code).catchError((_) {});
      }
    }

    return deduplicated;
  }

  /// Cleans up any existing active rooms belonging to the same host before creating a new one.
  /// Uses ONLY hostId (never hostName) to prevent accidental deletion of other users' rooms.
  Future<void> cleanupExistingRoomsForHost({
    required String hostId,
    required String hostName,
  }) async {
    if (hostId.isEmpty) return;

    // 1. Remove from local in-memory demo rooms
    _demoRooms.removeWhere((r) {
      if (r.hostId == hostId) return true;
      final desc = r.description ?? '';
      if (desc.contains('id=$hostId')) return true;
      return false;
    });

    // 2. Query and delete/close in Supabase
    if (supabase != null) {
      try {
        final filters = <String>[];
        if (_isValidUuid(hostId)) {
          filters.add('host_id.eq.$hostId');
        }
        filters.add('description.ilike.*id=$hostId*');

        if (filters.isNotEmpty) {
          final res = await supabase!
              .from('rooms')
              .select('id, code')
              .or(filters.join(','))
              .neq('current_state', 'closed')
              .timeout(const Duration(seconds: 4));

          final list = res as List<dynamic>;
          final idsToDelete = <String>[];
          final codesToDelete = <String>[];

          for (final item in list) {
            final existingId = item['id']?.toString();
            final existingCode = item['code']?.toString();
            if (existingId != null) {
              idsToDelete.add(existingId);
              removeLocalRoom(existingId, code: existingCode);
            } else if (existingCode != null) {
              codesToDelete.add(existingCode);
              removeLocalRoom('', code: existingCode);
            }
          }

          // Batch cleanup in Supabase instead of sequential N+1 queries
          if (idsToDelete.isNotEmpty) {
            try {
              await supabase!
                  .from('rooms')
                  .delete()
                  .inFilter('id', idsToDelete)
                  .timeout(const Duration(seconds: 4));
            } catch (_) {
              try {
                await supabase!
                    .from('rooms')
                    .update({'is_public': false, 'current_state': 'closed'})
                    .inFilter('id', idsToDelete)
                    .timeout(const Duration(seconds: 3));
              } catch (_) {}
            }
          }

          if (codesToDelete.isNotEmpty) {
            try {
              await supabase!
                  .from('rooms')
                  .delete()
                  .inFilter('code', codesToDelete)
                  .timeout(const Duration(seconds: 4));
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('[LobbyRepository] Cleanup existing rooms for host error: $e');
      }
    }
  }

  /// Fetches public rooms. Propagates network errors to controller so UI can display retry/error state.
  Future<List<RoomModel>> getPublicRooms() async {
    if (supabase != null) {
      dynamic response;
      try {
        response = await supabase!
            .from('rooms')
            .select('*, profiles(username, avatar_url)')
            .eq('is_public', true)
            .neq('current_state', 'closed')
            .order('created_at', ascending: false)
            .limit(30)
            .timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('[LobbyRepository] getPublicRooms with profiles join failed, retrying plain rooms query: $e');
        // Retry without join in case profiles relation is not configured
        response = await supabase!
            .from('rooms')
            .select('*')
            .eq('is_public', true)
            .neq('current_state', 'closed')
            .order('created_at', ascending: false)
            .limit(30)
            .timeout(const Duration(seconds: 4));
      }

      final List<dynamic> list = response as List<dynamic>;
      final rawRooms = list
          .map((item) => RoomModel.fromJson(item as Map<String, dynamic>))
          .toList();
      return deduplicateRooms(rawRooms);
    }
    return deduplicateRooms(
      _demoRooms.where((r) => r.isPublic && r.currentState != 'closed').toList(),
    );
  }

  /// Creates a new room
  Future<RoomModel> createRoom({
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
    // Proactively cleanup any older rooms by this host before creating a new one
    await cleanupExistingRoomsForHost(hostId: hostId, hostName: hostName);
    final String code = generateRoomCode();
    final String roomId = const Uuid().v4();
    final String livekitRoomName = 'wp_$code';

    final resolvedThumb = initialThumbnailUrl ??
        RoomModel.resolveThumbnail(
          url: initialMediaUrl,
          type: initialMediaType,
        );

    // Embed host metadata and thumbnail in description as a resilient fallback
    final thumbMeta = (resolvedThumb != null && resolvedThumb.isNotEmpty)
        ? ' [THUMB:$resolvedThumb]'
        : '';
    final metaHeader = '[HOST:name=$hostName;id=$hostId]$thumbMeta';
    final dbDescription = (description != null && description.isNotEmpty)
        ? '$metaHeader $description'
        : metaHeader;

    final newRoom = RoomModel(
      id: roomId,
      code: code,
      title: title,
      description: description,
      hostId: hostId,
      hostName: hostName,
      isPublic: isPublic,
      controlMode: controlMode,
      currentMediaType: initialMediaType,
      currentMediaUrl: initialMediaUrl,
      thumbnailUrl: resolvedThumb,
      currentState: 'paused',
      currentPosition: 0.0,
      livekitRoomName: livekitRoomName,
      participantCount: 1,
      createdAt: DateTime.now(),
    );

    // Keep locally in memory for instant lookup
    _demoRooms.insert(0, newRoom);

    if (supabase != null) {
      // Determine if host has an authentic user record in Supabase auth
      String? validHostId;
      if (supabase!.auth.currentUser != null &&
          supabase!.auth.currentUser!.id == hostId) {
        validHostId = hostId;
      }

      final roomPayload = <String, dynamic>{
        'id': roomId,
        'code': code,
        'title': title,
        'description': dbDescription,
        'host_id': validHostId,
        'host_name': hostName,
        'is_public': isPublic,
        'control_mode': controlMode,
        'current_media_type': newRoom.currentMediaType,
        'current_media_url': newRoom.currentMediaUrl,
        if (resolvedThumb != null && resolvedThumb.isNotEmpty)
          'thumbnail_url': resolvedThumb,
        'current_state': 'paused',
        'current_position': 0.0,
        'livekit_room_name': livekitRoomName,
      };

      try {
        await supabase!
            .from('rooms')
            .insert(roomPayload)
            .timeout(const Duration(seconds: 5));
        debugPrint('[LobbyRepository] Room successfully created in Supabase with code: $code');
      } catch (e) {
        debugPrint('[LobbyRepository] Supabase createRoom insert failed: $e');
        // If it failed because optional columns (thumbnail_url or host_name) might not exist, strip and retry
        if (roomPayload.containsKey('thumbnail_url')) {
          roomPayload.remove('thumbnail_url');
        }
        if (roomPayload.containsKey('host_name')) {
          roomPayload.remove('host_name');
        }
        try {
          await supabase!
              .from('rooms')
              .insert(roomPayload)
              .timeout(const Duration(seconds: 5));
          debugPrint('[LobbyRepository] Room successfully created in Supabase without optional columns, code: $code');
        } catch (retryColErr) {
          debugPrint('[LobbyRepository] Supabase retry without optional columns failed: $retryColErr');
        }

        // If it still failed and host_id was not null (e.g. FK violation on profiles), retry with host_id: null
        if (roomPayload['host_id'] != null) {
          try {
            roomPayload['host_id'] = null;
            await supabase!
                .from('rooms')
                .insert(roomPayload)
                .timeout(const Duration(seconds: 5));
            debugPrint('[LobbyRepository] Room successfully created in Supabase with host_id: null, code: $code');
          } catch (retryErr) {
            debugPrint('[LobbyRepository] Supabase createRoom retry with null host_id failed: $retryErr');
          }
        }
      }

      // Add host as participant only if valid in Supabase auth/profiles
      if (validHostId != null) {
        try {
          await supabase!.from('room_participants').insert({
            'room_id': roomId,
            'user_id': validHostId,
            'role': 'host',
          }).timeout(const Duration(seconds: 3));
        } catch (e) {
          debugPrint('[LobbyRepository] Participant insert skipped: $e');
        }
      }
    }

    return newRoom;
  }

  /// Finds room by code with case-insensitivity and prefix tolerance
  Future<RoomModel?> getRoomByCode(String code) async {
    lastError = null;
    final rawTrimmed = code.trim();
    if (rawTrimmed.isEmpty) return null;

    final candidates = getCodeCandidates(rawTrimmed);
    if (candidates.isEmpty) return null;

    if (supabase != null) {
      try {
        // Sanitize candidates to safe alphanumeric + hyphen for PostgREST .or filter
        final validCandidates = candidates
            .where((c) => RegExp(r'^[a-zA-Z0-9\-]+$').hasMatch(c))
            .toSet();

        if (validCandidates.isNotEmpty) {
          final orFilter = validCandidates
              .map((c) => 'code.ilike.$c')
              .join(',');

          dynamic response;
          try {
            response = await supabase!
                .from('rooms')
                .select('*, profiles(username, avatar_url)')
                .or(orFilter)
                .neq('current_state', 'closed')
                .limit(1)
                .timeout(const Duration(seconds: 7));
          } catch (e) {
            debugPrint('[LobbyRepository] Query with profiles join failed: $e');
            try {
              response = await supabase!
                  .from('rooms')
                  .select('*')
                  .or(orFilter)
                  .neq('current_state', 'closed')
                  .limit(1)
                  .timeout(const Duration(seconds: 7));
            } catch (plainErr) {
              debugPrint('[LobbyRepository] Plain rooms or query failed: $plainErr');
            }
          }

          if (response != null) {
            final list = response as List<dynamic>;
            if (list.isNotEmpty) {
              return RoomModel.fromJson(list.first as Map<String, dynamic>);
            }
          }
        }
      } catch (e) {
        lastError = 'Gangguan koneksi saat menghubungi server room.';
        debugPrint('[LobbyRepository] Supabase getRoomByCode fallback: $e');
      }
    }

    // Check demo rooms and local in-memory rooms
    try {
      return _demoRooms.firstWhere((r) {
        if (r.currentState == 'closed') return false;
        final rNorm = normalizeCode(r.code);
        for (final candidate in candidates) {
          if (rNorm == normalizeCode(candidate) ||
              r.code.toUpperCase() == candidate.toUpperCase() ||
              r.code.toLowerCase() == candidate.toLowerCase()) {
            return true;
          }
        }
        return false;
      });
    } catch (_) {
      return null;
    }
  }

  static bool _isValidUuid(String str) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(str);
  }

  /// Removes room from local memory demo rooms list
  static void removeLocalRoom(String roomId, {String? code}) {
    _demoRooms.removeWhere((r) {
      if (r.id == roomId) return true;
      if (code != null &&
          (r.code.toUpperCase() == code.toUpperCase() ||
              normalizeCode(r.code) == normalizeCode(code))) {
        return true;
      }
      return false;
    });
  }

  /// Deletes a room from memory (_demoRooms) and Supabase database
  Future<void> deleteRoom(String roomId, {String? code}) async {
    // 1. Remove from local memory demo rooms
    removeLocalRoom(roomId, code: code);

    // 2. Remove / Close in Supabase database (Double-cleanup: UPDATE is_public: false + DELETE)
    if (supabase != null && !roomId.startsWith('demo-')) {
      try {
        final isUuid = _isValidUuid(roomId);

        // Fallback step 1: UPDATE is_public to false and current_state to 'closed'.
        // This is 100% permitted by existing RLS UPDATE policies, so even if DELETE
        // fails or has no RLS policy yet, the room instantly disappears from getPublicRooms().
        try {
          if (isUuid) {
            await supabase!
                .from('rooms')
                .update({
                  'is_public': false,
                  'current_state': 'closed',
                })
                .eq('id', roomId)
                .timeout(const Duration(seconds: 3));
          } else if (code != null && code.isNotEmpty) {
            await supabase!
                .from('rooms')
                .update({
                  'is_public': false,
                  'current_state': 'closed',
                })
                .eq('code', code)
                .timeout(const Duration(seconds: 3));
          }
        } catch (_) {}

        // Step 2: Delete room. PostgreSQL ON DELETE CASCADE will automatically
        // clean up all associated room_messages, room_participants, and room_queue in 1 atomic query.
        if (isUuid) {
          await supabase!
              .from('rooms')
              .delete()
              .eq('id', roomId)
              .timeout(const Duration(seconds: 3));
        } else if (code != null && code.isNotEmpty) {
          await supabase!
              .from('rooms')
              .delete()
              .eq('code', code)
              .timeout(const Duration(seconds: 3));
        }
        debugPrint('[LobbyRepository] Room $roomId ($code) closed/deleted in Supabase.');
      } catch (e) {
        debugPrint('[LobbyRepository] Supabase deleteRoom failed: $e');
      }
    }
  }
}
