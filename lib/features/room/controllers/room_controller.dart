import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/domain/user_profile.dart';
import '../models/room_model.dart';

class RoomState {
  final RoomModel room;
  final List<UserProfile> participants;
  final bool isLoading;
  final String? error;
  final bool isRoomClosed;
  final String? closedReason;

  const RoomState({
    required this.room,
    this.participants = const [],
    this.isLoading = false,
    this.error,
    this.isRoomClosed = false,
    this.closedReason,
  });

  RoomState copyWith({
    RoomModel? room,
    List<UserProfile>? participants,
    bool? isLoading,
    String? error,
    bool? isRoomClosed,
    String? closedReason,
  }) {
    return RoomState(
      room: room ?? this.room,
      participants: participants ?? this.participants,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isRoomClosed: isRoomClosed ?? this.isRoomClosed,
      closedReason: closedReason ?? this.closedReason,
    );
  }
}

class RoomController extends ChangeNotifier {
  final SupabaseClient? supabase;
  final UserProfile _currentUser;
  RealtimeChannel? _presenceChannel;
  bool _hasEstablishedPresence = false;
  bool _hasSeenHost = false;
  Timer? _hostMissingTimer;
  Timer? _initialHostDiscoveryTimer;
  static const Duration _hostGracePeriod = Duration(seconds: 10);
  static const Duration _initialHostDiscoveryTimeout = Duration(seconds: 15);

  void Function(String reason)? onRoomClosed;
  void Function(String? newHostId, String? newHostName)? onHostChanged;

  String? _detectedHostId;
  String? _detectedHostName;

  RoomState _state;
  RoomState get state => _state;
  RoomState get currentState => _state;
  RoomModel get currentRoom => _state.room;
  UserProfile get currentUser => _currentUser;
  bool get isHost {
    if (_state.room.hostId != null &&
        _state.room.hostId!.isNotEmpty &&
        _state.room.hostId == _currentUser.id) {
      return true;
    }
    if (_state.room.hostName != null &&
        _state.room.hostName!.isNotEmpty &&
        _state.room.hostName != 'Host' &&
        _state.room.hostName == _currentUser.username) {
      return true;
    }

    final bool hasExplicitHost = (_state.room.hostId != null && _state.room.hostId!.isNotEmpty) ||
        (_state.room.hostName != null &&
            _state.room.hostName!.isNotEmpty &&
            _state.room.hostName != 'Host');

    if (!hasExplicitHost) {
      if (_detectedHostId != null && _detectedHostId != _currentUser.id) {
        return false;
      }
      if (_detectedHostName != null &&
          _detectedHostName != 'Host' &&
          _detectedHostName != _currentUser.username) {
        return false;
      }
      if (_currentUser.username == 'Host') {
        return false;
      }
      return true;
    }

    return false;
  }
  bool get isRoomClosed => _state.isRoomClosed;

  RoomController({
    required RoomModel initialRoom,
    required UserProfile currentUser,
    this.supabase,
  })  : _currentUser = currentUser,
        _state = RoomState(
          room: initialRoom,
          participants: [currentUser],
        ) {
    if (isHost) {
      _hasSeenHost = true;
    }
    _initPresence();
  }

  static bool _isValidUuid(String str) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(str);
  }

  void _initPresence() {
    if (supabase == null) return;

    if (!isHost) {
      _initialHostDiscoveryTimer = Timer(_initialHostDiscoveryTimeout, () async {
        if (!_hasSeenHost && !_state.isRoomClosed) {
          final participants = _state.participants.toList();
          if (participants.isNotEmpty) {
            participants.sort((a, b) => a.id.compareTo(b.id));
            final nextHost = participants.first;
            debugPrint(
                '[RoomController] Initial host not seen. Electing next host: ${nextHost.username}');
            if (_currentUser.id == nextHost.id ||
                _currentUser.username == nextHost.username) {
              await promoteToHost(nextHost);
            } else {
              _detectedHostId = nextHost.id;
              _detectedHostName = nextHost.username;
              _hasSeenHost = true;
              _state = _state.copyWith(
                room: _state.room.copyWith(
                  hostId: nextHost.id,
                  hostName: nextHost.username,
                ),
              );
              notifyListeners();
              onHostChanged?.call(nextHost.id, nextHost.username);
            }
          } else {
            const reason = 'Host tidak ditemukan atau telah keluar dari room.';
            _state = _state.copyWith(
              isRoomClosed: true,
              closedReason: reason,
            );
            notifyListeners();
            onRoomClosed?.call(reason);
          }
        }
      });
    }

    try {
      final channelName = 'presence_${_state.room.id}';
      _presenceChannel = supabase!.channel(
        channelName,
        opts: RealtimeChannelConfig(
          key: _currentUser.id,
          enabled: true,
        ),
      );

      _presenceChannel!.onBroadcast(
        event: 'HOST_CHANGED',
        callback: (payload) {
          final data = (payload['payload'] is Map)
              ? Map<String, dynamic>.from(payload['payload'] as Map)
              : payload;
          final roomId = data['room_id'] as String?;
          final roomCode = data['code'] as String?;
          if (roomId == _state.room.id ||
              (roomCode != null && roomCode == _state.room.code)) {
            final newHostId = data['new_host_id'] as String?;
            final newHostName = data['new_host_name'] as String?;
            if (newHostId != null || newHostName != null) {
              debugPrint(
                  '[RoomController] HOST_CHANGED: new host is $newHostName ($newHostId)');
              _detectedHostId = newHostId;
              _detectedHostName = newHostName;
              _hasSeenHost = true;
              _hostMissingTimer?.cancel();
              _hostMissingTimer = null;
              _initialHostDiscoveryTimer?.cancel();
              _initialHostDiscoveryTimer = null;

              _state = _state.copyWith(
                room: _state.room.copyWith(
                  hostId: newHostId ?? _state.room.hostId,
                  hostName: newHostName ?? _state.room.hostName,
                ),
              );

              if (isHost && _presenceChannel != null) {
                () async {
                  try {
                    await _presenceChannel!.track({
                      'user_id': _currentUser.id,
                      'username': _currentUser.username,
                      'avatar_url': _currentUser.avatarUrl,
                      'is_guest': _currentUser.isGuest,
                      'is_host': true,
                      'role': 'host',
                    });
                  } catch (_) {}
                }();
              }

              notifyListeners();
              onHostChanged?.call(newHostId, newHostName);
            }
          }
        },
      );

      _presenceChannel!.onBroadcast(
        event: 'ROOM_CLOSED',
        callback: (payload) {
          final data = (payload['payload'] is Map)
              ? Map<String, dynamic>.from(payload['payload'] as Map)
              : payload;
          final roomId = data['room_id'] as String?;
          final roomCode = data['code'] as String?;
          if (roomId == _state.room.id ||
              (roomCode != null && roomCode == _state.room.code)) {
            _hostMissingTimer?.cancel();
            _hostMissingTimer = null;
            _initialHostDiscoveryTimer?.cancel();
            _initialHostDiscoveryTimer = null;
            final reason = data['reason'] as String? ??
                'Host telah keluar dari room. Room ditutup.';
            _state = _state.copyWith(isRoomClosed: true, closedReason: reason);
            notifyListeners();
            onRoomClosed?.call(reason);
          }
        },
      );

      void handlePresenceUpdate() {
        final presenceState = _presenceChannel!.presenceState();
        final List<UserProfile> activeUsers = [];
        String? detectedHostId;
        String? detectedHostName;

        for (final single in presenceState) {
          for (final presence in single.presences) {
            final raw = presence.payload;
            final payload = (raw['payload'] is Map)
                ? Map<String, dynamic>.from(raw['payload'] as Map)
                : raw;
            final userId = payload['user_id'] as String? ?? single.key;
            final username = payload['username'] as String? ?? 'Guest';
            final isUserHost = payload['is_host'] == true || payload['role'] == 'host';
            if (isUserHost && username != 'Host') {
              detectedHostId = userId;
              detectedHostName = username;
            }
            activeUsers.add(UserProfile(
              id: userId,
              username: username,
              avatarUrl: payload['avatar_url'] as String? ?? '🦊',
              isGuest: payload['is_guest'] as bool? ?? true,
            ));
          }
        }

        _detectedHostId = detectedHostId;
        _detectedHostName = detectedHostName;

        // Always ensure currentUser is included even before presence echo
        final uniqueMap = <String, UserProfile>{
          if (_currentUser.id.isNotEmpty) _currentUser.id: _currentUser,
          for (var u in activeUsers) (u.id.isNotEmpty ? u.id : u.username): u,
        };

        debugPrint(
            '[RoomController] handlePresenceUpdate: presenceState has ${presenceState.length} items, uniqueMap count: ${uniqueMap.length}, active: ${uniqueMap.values.map((u) => u.username).toList()}');

        // If guest detects host info from presence that wasn't previously resolved, update room state
        RoomModel currentRoomModel = _state.room;
        if (!isHost && (detectedHostId != null || detectedHostName != null)) {
          bool needsUpdate = false;
          String? newHostId = currentRoomModel.hostId;
          String? newHostName = currentRoomModel.hostName;

          if ((newHostId == null || newHostId.isEmpty) && detectedHostId != null) {
            newHostId = detectedHostId;
            needsUpdate = true;
          }
          if ((newHostName == null || newHostName == 'Host') && detectedHostName != null) {
            newHostName = detectedHostName;
            needsUpdate = true;
          }
          if (needsUpdate) {
            currentRoomModel = currentRoomModel.copyWith(
              hostId: newHostId,
              hostName: newHostName,
            );
          }
        }

        _state = _state.copyWith(
          participants: uniqueMap.values.toList(),
          room: currentRoomModel.copyWith(
            participantCount: uniqueMap.length,
          ),
        );
        notifyListeners();

        // Host detection & grace period logic
        if (isHost) {
          _hasSeenHost = true;
          _initialHostDiscoveryTimer?.cancel();
          _initialHostDiscoveryTimer = null;
          _hostMissingTimer?.cancel();
          _hostMissingTimer = null;
        } else {
          final hostId = _state.room.hostId;
          final hostName = _state.room.hostName;

          final bool hasHost = activeUsers.any((u) =>
              (detectedHostId != null && u.id == detectedHostId) ||
              (detectedHostName != null && u.username == detectedHostName) ||
              (hostId != null && hostId.isNotEmpty && u.id == hostId) ||
              (hostName != null &&
                  hostName.isNotEmpty &&
                  hostName != 'Host' &&
                  u.username == hostName));

          if (hasHost) {
            _hasSeenHost = true;
            _initialHostDiscoveryTimer?.cancel();
            _initialHostDiscoveryTimer = null;
            // Cancel any pending grace period timer because host is active
            if (_hostMissingTimer != null) {
              _hostMissingTimer?.cancel();
              _hostMissingTimer = null;
              debugPrint('[RoomController] Host detected active in presence; cancelled grace period timer.');
            }
          } else if (_hasEstablishedPresence && _hasSeenHost && !_state.isRoomClosed) {
            // Host was previously seen, but is now missing!
            // Start grace period before handover to prevent false drops on network jitter.
            if (_hostMissingTimer == null) {
              debugPrint('[RoomController] Host missing from presence. Starting 10s grace period...');
              _hostMissingTimer = Timer(_hostGracePeriod, () async {
                _hostMissingTimer = null;
                if (!_state.isRoomClosed) {
                  final remaining = uniqueMap.values.where((u) =>
                      u.id != hostId &&
                      u.username != hostName &&
                      u.id != detectedHostId &&
                      u.username != detectedHostName).toList();
                  if (remaining.isNotEmpty) {
                    remaining.sort((a, b) => a.id.compareTo(b.id));
                    final newHost = remaining.first;
                    debugPrint(
                        '[RoomController] Host missing after grace period. Handing over to: ${newHost.username}');
                    if (_currentUser.id == newHost.id ||
                        _currentUser.username == newHost.username) {
                      await promoteToHost(newHost);
                    } else {
                      _detectedHostId = newHost.id;
                      _detectedHostName = newHost.username;
                      _hasSeenHost = true;
                      _state = _state.copyWith(
                        room: _state.room.copyWith(
                          hostId: newHost.id,
                          hostName: newHost.username,
                        ),
                      );
                      notifyListeners();
                      onHostChanged?.call(newHost.id, newHost.username);
                    }
                  } else {
                    const reason =
                        'Host telah meninggalkan room dan tidak ada peserta lain.';
                    _state = _state.copyWith(
                      isRoomClosed: true,
                      closedReason: reason,
                    );
                    notifyListeners();
                    onRoomClosed?.call(reason);
                  }
                }
              });
            }
          }
        }

        _hasEstablishedPresence = true;
      }

      _presenceChannel!.onPresenceSync((_) => handlePresenceUpdate());
      _presenceChannel!.onPresenceJoin((_) => handlePresenceUpdate());
      _presenceChannel!.onPresenceLeave((_) => handlePresenceUpdate());

      _presenceChannel!.subscribe((status, error) async {
        debugPrint(
            '[RoomController] Presence channel subscribe status: $status (error: $error)');
        if (status == RealtimeSubscribeStatus.subscribed) {
          final res = await _presenceChannel!.track({
            'user_id': _currentUser.id,
            'username': _currentUser.username,
            'avatar_url': _currentUser.avatarUrl,
            'is_guest': _currentUser.isGuest,
            'is_host': isHost,
            'role': isHost ? 'host' : 'viewer',
          });
          debugPrint('[RoomController] Presence track response: $res');
        }
      });
    } catch (e) {
      debugPrint('[RoomController] Error setting up presence: $e');
    }
  }

  /// Promotes a participant to be the new host of this room.
  /// Updates local state, Supabase database, sends broadcast to all clients,
  /// and announces it in chat if [chatController] is provided.
  Future<void> promoteToHost(UserProfile newHost, {dynamic chatController}) async {
    debugPrint('[RoomController] Promoting ${newHost.username} (${newHost.id}) to host...');
    _detectedHostId = newHost.id;
    _detectedHostName = newHost.username;
    _hasSeenHost = true;
    _hostMissingTimer?.cancel();
    _hostMissingTimer = null;
    _initialHostDiscoveryTimer?.cancel();
    _initialHostDiscoveryTimer = null;

    final prevHostName = _state.room.hostName;

    _state = _state.copyWith(
      room: _state.room.copyWith(
        hostId: newHost.id,
        hostName: newHost.username,
      ),
    );

    // Update in Supabase database
    if (supabase != null && !_state.room.id.startsWith('demo-')) {
      try {
        final isUuid = _isValidUuid(_state.room.id);
        if (isUuid) {
          await supabase!
              .from('rooms')
              .update({
                'host_id': newHost.id,
                'host_name': newHost.username,
              })
              .eq('id', _state.room.id)
              .timeout(const Duration(seconds: 3));
        } else if (_state.room.code.isNotEmpty) {
          await supabase!
              .from('rooms')
              .update({
                'host_id': newHost.id,
                'host_name': newHost.username,
              })
              .eq('code', _state.room.code)
              .timeout(const Duration(seconds: 3));
        }
      } catch (e) {
        debugPrint('[RoomController] Error updating host in Supabase: $e');
      }
    }

    // Broadcast HOST_CHANGED to all participants
    if (_presenceChannel != null && supabase != null) {
      try {
        await _presenceChannel!.sendBroadcastMessage(
          event: 'HOST_CHANGED',
          payload: {
            'room_id': _state.room.id,
            'code': _state.room.code,
            'new_host_id': newHost.id,
            'new_host_name': newHost.username,
            'previous_host': prevHostName,
          },
        );
      } catch (e) {
        debugPrint('[RoomController] Error broadcasting HOST_CHANGED: $e');
      }
    }

    // If currentUser is the newly promoted host, update presence role to host
    if (isHost && _presenceChannel != null) {
      try {
        await _presenceChannel!.track({
          'user_id': _currentUser.id,
          'username': _currentUser.username,
          'avatar_url': _currentUser.avatarUrl,
          'is_guest': _currentUser.isGuest,
          'is_host': true,
          'role': 'host',
        });
      } catch (_) {}
    }

    // Optional chat notification
    if (chatController != null) {
      try {
        await chatController.sendSystemMessage(
          '👑 ${newHost.username} sekarang menjadi Host room ini!',
        );
      } catch (_) {}
    }

    notifyListeners();
    onHostChanged?.call(newHost.id, newHost.username);
  }

  /// Transfers host role to [nextHost] and cleans up current user's presence so they can leave gracefully
  /// without closing/deleting the room.
  Future<void> transferHostAndLeave({
    required UserProfile nextHost,
    dynamic chatController,
  }) async {
    _hostMissingTimer?.cancel();
    _hostMissingTimer = null;
    _initialHostDiscoveryTimer?.cancel();
    _initialHostDiscoveryTimer = null;

    // Send system message that old host is leaving and handing over
    if (chatController != null) {
      try {
        await chatController.sendSystemMessage(
          '${_currentUser.username} (Host) keluar. 👑 ${nextHost.username} sekarang menjadi Host!',
        );
      } catch (_) {}
    }

    // Promote nextHost and notify all participants
    await promoteToHost(nextHost);

    // Untrack presence and clean up channel for leaving user
    if (_presenceChannel != null && supabase != null) {
      try {
        await _presenceChannel!.untrack();
        supabase!.removeChannel(_presenceChannel!);
        _presenceChannel = null;
      } catch (e) {
        debugPrint('[RoomController] Error untracking presence on leave: $e');
      }
    }
  }

  /// Update control mode (Host only vs Collaborative)
  Future<void> setControlMode(String mode) async {
    if (!isHost) return;

    final updated = _state.room.copyWith(controlMode: mode);
    _state = _state.copyWith(room: updated);
    notifyListeners();

    if (supabase != null) {
      try {
        await supabase!
            .from('rooms')
            .update({'control_mode': mode})
            .eq('id', _state.room.id);
      } catch (e) {
        debugPrint('[RoomController] Error updating control mode: $e');
      }
    }
  }

  /// Closes and deletes the room if current user is the host
  Future<void> closeOrDeleteRoom() async {
    if (!isHost) return;

    _hostMissingTimer?.cancel();
    _hostMissingTimer = null;
    _initialHostDiscoveryTimer?.cancel();
    _initialHostDiscoveryTimer = null;

    if (_presenceChannel != null && supabase != null) {
      try {
        await _presenceChannel!.sendBroadcastMessage(
          event: 'ROOM_CLOSED',
          payload: {
            'room_id': _state.room.id,
            'code': _state.room.code,
            'reason':
                'Host (${_currentUser.username}) telah keluar dari room. Room ditutup.',
          },
        );
      } catch (e) {
        debugPrint('[RoomController] Error broadcasting ROOM_CLOSED: $e');
      }
    }

    if (supabase != null && !_state.room.id.startsWith('demo-')) {
      try {
        final isUuid = _isValidUuid(_state.room.id);
        // Fallback step 1: UPDATE is_public: false and current_state: 'closed'
        try {
          if (isUuid) {
            await supabase!
                .from('rooms')
                .update({
                  'is_public': false,
                  'current_state': 'closed',
                })
                .eq('id', _state.room.id)
                .timeout(const Duration(seconds: 3));
          } else if (_state.room.code.isNotEmpty) {
            await supabase!
                .from('rooms')
                .update({
                  'is_public': false,
                  'current_state': 'closed',
                })
                .eq('code', _state.room.code)
                .timeout(const Duration(seconds: 3));
          }
        } catch (_) {}

        // Parallel cleanup for participants, messages, and room
        await Future.wait([
          if (isUuid)
            supabase!
                .from('room_participants')
                .delete()
                .eq('room_id', _state.room.id)
                .timeout(const Duration(seconds: 2))
                .then((_) {}, onError: (_) {}),
          if (isUuid)
            supabase!
                .from('room_messages')
                .delete()
                .eq('room_id', _state.room.id)
                .timeout(const Duration(seconds: 2))
                .then((_) {}, onError: (_) {}),
          if (isUuid)
            supabase!
                .from('rooms')
                .delete()
                .eq('id', _state.room.id)
                .timeout(const Duration(seconds: 3))
                .then((_) {}, onError: (_) {})
          else if (_state.room.code.isNotEmpty)
            supabase!
                .from('rooms')
                .delete()
                .eq('code', _state.room.code)
                .timeout(const Duration(seconds: 3))
                .then((_) {}, onError: (_) {}),
        ]);
      } catch (e) {
        debugPrint('[RoomController] Error deleting room from Supabase: $e');
      }
    }

    _state = _state.copyWith(
      isRoomClosed: true,
      closedReason: 'Room telah ditutup oleh Host.',
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _hostMissingTimer?.cancel();
    _hostMissingTimer = null;
    _initialHostDiscoveryTimer?.cancel();
    _initialHostDiscoveryTimer = null;
    if (_presenceChannel != null && supabase != null) {
      _presenceChannel!.untrack();
      supabase!.removeChannel(_presenceChannel!);
    }
    super.dispose();
  }
}
