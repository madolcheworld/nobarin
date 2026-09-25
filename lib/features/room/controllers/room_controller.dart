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
  final bool isRealtimeConnected;
  final bool isReconnecting;

  const RoomState({
    required this.room,
    this.participants = const [],
    this.isLoading = false,
    this.error,
    this.isRoomClosed = false,
    this.closedReason,
    this.isRealtimeConnected = true,
    this.isReconnecting = false,
  });

  RoomState copyWith({
    RoomModel? room,
    List<UserProfile>? participants,
    bool? isLoading,
    String? error,
    bool? isRoomClosed,
    String? closedReason,
    bool? isRealtimeConnected,
    bool? isReconnecting,
  }) {
    return RoomState(
      room: room ?? this.room,
      participants: participants ?? this.participants,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isRoomClosed: isRoomClosed ?? this.isRoomClosed,
      closedReason: closedReason ?? this.closedReason,
      isRealtimeConnected: isRealtimeConnected ?? this.isRealtimeConnected,
      isReconnecting: isReconnecting ?? this.isReconnecting,
    );
  }
}

class RoomController extends ChangeNotifier {
  final SupabaseClient? supabase;
  final UserProfile _currentUser;
  RealtimeChannel? _presenceChannel;
  bool _hasEstablishedPresence = false;
  bool _hasSeenHost = false;
  bool _isDisposed = false;
  Timer? _hostMissingTimer;
  Timer? _initialHostDiscoveryTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const Duration _hostGracePeriod = Duration(seconds: 10);
  static const Duration _initialHostDiscoveryTimeout = Duration(seconds: 15);

  void Function(String reason)? onRoomClosed;
  void Function(String? newHostId, String? newHostName)? onHostChanged;
  void Function(String username)? onParticipantLeft;
  void Function(String message)? onSystemNotice;
  void Function(String reason)? onKicked;
  void Function()? onForceMuteReceived;
  void Function(String message)? onModerationNotice;

  final Set<String> _coHostUserIds = {};
  final Set<String> _kickedUserIds = {};

  Set<String> _knownParticipantKeys = {};
  Map<String, String> _knownParticipantNames = {};

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
        _state.room.hostName!.trim().toLowerCase() ==
            _currentUser.username.trim().toLowerCase()) {
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
          _detectedHostName!.trim().toLowerCase() !=
              _currentUser.username.trim().toLowerCase()) {
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

  Set<String> get coHostUserIds => Set.unmodifiable(_coHostUserIds);
  Set<String> get kickedUserIds => Set.unmodifiable(_kickedUserIds);

  bool isCoHost(String userId) => _coHostUserIds.contains(userId);

  bool isUserHost(String userId) {
    if (_state.room.hostId != null && _state.room.hostId!.isNotEmpty) {
      return _state.room.hostId == userId;
    }
    if (_state.room.hostName != null &&
        _state.room.hostName!.isNotEmpty &&
        _state.room.hostName != 'Host') {
      return _state.room.hostName == userId;
    }
    return false;
  }

  bool get isCurrentUserCoHost =>
      _coHostUserIds.contains(_currentUser.id) ||
      _coHostUserIds.contains(_currentUser.username);

  bool get canControlMedia =>
      isHost || isCurrentUserCoHost || _state.room.isCollaborative;

  bool canModerateUser(String targetUserId) {
    if (targetUserId == _currentUser.id || targetUserId == _currentUser.username) {
      return false;
    }
    if (isHost) {
      return true;
    }
    if (isCurrentUserCoHost) {
      final isTargetHost = isUserHost(targetUserId) ||
          (_state.room.hostName != null &&
              _state.room.hostName != 'Host' &&
              _state.room.hostName == targetUserId);
      final isTargetCoHost = isCoHost(targetUserId);
      return !isTargetHost && !isTargetCoHost;
    }
    return false;
  }

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

      _presenceChannel!.onBroadcast(
        event: 'KICK_PARTICIPANT',
        callback: (payload) {
          final data = (payload['payload'] is Map)
              ? Map<String, dynamic>.from(payload['payload'] as Map)
              : payload;
          handleKickParticipant(data);
        },
      );

      _presenceChannel!.onBroadcast(
        event: 'FORCE_MUTE_PARTICIPANT',
        callback: (payload) {
          final data = (payload['payload'] is Map)
              ? Map<String, dynamic>.from(payload['payload'] as Map)
              : payload;
          handleForceMuteParticipant(data);
        },
      );

      _presenceChannel!.onBroadcast(
        event: 'CO_HOST_UPDATED',
        callback: (payload) {
          final data = (payload['payload'] is Map)
              ? Map<String, dynamic>.from(payload['payload'] as Map)
              : payload;
          handleCoHostUpdated(data);
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
            final isUserCoHost = payload['is_co_host'] == true || payload['role'] == 'co_host';
            if (isUserHost && username != 'Host') {
              detectedHostId = userId;
              detectedHostName = username;
            }
            if (isUserCoHost && userId.isNotEmpty) {
              _coHostUserIds.add(userId);
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

        // Always ensure currentUser is included even before presence echo, excluding kicked users
        final uniqueMap = <String, UserProfile>{
          if (_currentUser.id.isNotEmpty && !_kickedUserIds.contains(_currentUser.id))
            _currentUser.id: _currentUser,
          for (var u in activeUsers)
            if (!_kickedUserIds.contains(u.id) && !_kickedUserIds.contains(u.username))
              (u.id.isNotEmpty ? u.id : u.username): u,
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

        final currentKeys = uniqueMap.keys.toSet();

        // Identify departed participants after presence has been established
        if (_hasEstablishedPresence) {
          final departedKeys = _knownParticipantKeys.difference(currentKeys);
          for (final departedKey in departedKeys) {
            if (departedKey == _currentUser.id ||
                departedKey == _currentUser.username) {
              continue;
            }

            final departedName = _knownParticipantNames[departedKey];
            if (departedName != null &&
                departedName.isNotEmpty &&
                departedName != 'Host') {
              // Elect reporter to prevent multiple clients broadcasting duplicate messages:
              // Prefer Host, or the active participant with the lowest ID
              final sortedRemaining = uniqueMap.values.toList()
                ..sort((a, b) => a.id.compareTo(b.id));
              final isElectedReporter = isHost ||
                  (sortedRemaining.isNotEmpty &&
                      sortedRemaining.first.id == _currentUser.id);

              if (isElectedReporter) {
                onParticipantLeft?.call(departedName);
              }
            }
          }
        }

        _knownParticipantKeys = currentKeys;
        _knownParticipantNames = {
          for (var u in uniqueMap.values)
            (u.id.isNotEmpty ? u.id : u.username): u.username,
        };

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
                  final currentHostId = _state.room.hostId;
                  final currentHostName = _state.room.hostName;
                  final remaining = _state.participants.where((u) =>
                      u.id != currentHostId &&
                      u.username != currentHostName &&
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
          _reconnectAttempts = 0;
          _state = _state.copyWith(
            isRealtimeConnected: true,
            isReconnecting: false,
          );
          notifyListeners();
          final res = await _presenceChannel!.track({
            'user_id': _currentUser.id,
            'username': _currentUser.username,
            'avatar_url': _currentUser.avatarUrl,
            'is_guest': _currentUser.isGuest,
            'is_host': isHost,
            'is_co_host': isCurrentUserCoHost,
            'role': isHost ? 'host' : (isCurrentUserCoHost ? 'co_host' : 'viewer'),
          });
          debugPrint('[RoomController] Presence track response: $res');
        } else if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) {
          _state = _state.copyWith(
            isRealtimeConnected: false,
            isReconnecting: true,
          );
          notifyListeners();
          _schedulePresenceReconnect();
        }
      });
    } catch (e) {
      debugPrint('[RoomController] Error setting up presence: $e');
      _state = _state.copyWith(
        isRealtimeConnected: false,
        isReconnecting: true,
      );
      notifyListeners();
      _schedulePresenceReconnect();
    }
  }

  void _schedulePresenceReconnect() {
    if (_isDisposed || _reconnectTimer?.isActive == true) return;
    _reconnectAttempts++;
    final delaySeconds = (_reconnectAttempts * 2).clamp(2, 10);
    debugPrint(
        '[RoomController] Scheduling presence reconnect in ${delaySeconds}s (attempt $_reconnectAttempts)...');
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!_isDisposed) {
        reconnectPresence();
      }
    });
  }

  /// Re-establishes connection to Supabase presence channel
  Future<void> reconnectPresence() async {
    if (_isDisposed || supabase == null) return;
    debugPrint('[RoomController] Reconnecting presence channel...');
    try {
      if (_presenceChannel != null) {
        try {
          await _presenceChannel!.untrack();
          await supabase!.removeChannel(_presenceChannel!);
        } catch (_) {}
        _presenceChannel = null;
      }
      _initPresence();
    } catch (e) {
      debugPrint('[RoomController] Reconnect presence failed: $e');
      _schedulePresenceReconnect();
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
    final hostNotice = (prevHostName != null &&
            prevHostName.isNotEmpty &&
            prevHostName != 'Host')
        ? '$prevHostName (Host) keluar. 👑 ${newHost.username} sekarang menjadi Host room ini!'
        : '👑 ${newHost.username} sekarang menjadi Host room ini!';

    if (chatController != null) {
      try {
        await chatController.sendSystemMessage(hostNotice);
      } catch (_) {}
    } else {
      onSystemNotice?.call(hostNotice);
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

        // Step 2: Delete room. PostgreSQL ON DELETE CASCADE will automatically
        // clean up all associated room_messages, room_participants, and room_queue in 1 atomic query.
        if (isUuid) {
          await supabase!
              .from('rooms')
              .delete()
              .eq('id', _state.room.id)
              .timeout(const Duration(seconds: 3));
        } else if (_state.room.code.isNotEmpty) {
          await supabase!
              .from('rooms')
              .delete()
              .eq('code', _state.room.code)
              .timeout(const Duration(seconds: 3));
        }
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

  /// Handles incoming KICK_PARTICIPANT broadcast event
  @visibleForTesting
  void handleKickParticipant(Map<String, dynamic> data) {
    final targetId = data['target_user_id'] as String?;
    final targetName = data['target_username'] as String?;
    final reason = data['reason'] as String? ?? 'Kamu telah dikeluarkan dari room.';

    if (targetId == _currentUser.id ||
        (targetName != null && targetName == _currentUser.username)) {
      _state = _state.copyWith(
        isRoomClosed: true,
        closedReason: reason,
      );
      notifyListeners();
      onKicked?.call(reason);
    } else if (targetId != null || targetName != null) {
      if (targetId != null) _kickedUserIds.add(targetId);
      if (targetName != null) _kickedUserIds.add(targetName);
      final updated = _state.participants
          .where((p) => p.id != targetId && p.username != targetName)
          .toList();
      _state = _state.copyWith(
        participants: updated,
        room: _state.room.copyWith(participantCount: updated.length),
      );
      notifyListeners();
      final displayName = targetName ?? 'Peserta';
      onModerationNotice?.call('$displayName telah dikeluarkan dari room.');
    }
  }

  /// Handles incoming FORCE_MUTE_PARTICIPANT broadcast event
  @visibleForTesting
  void handleForceMuteParticipant(Map<String, dynamic> data) {
    final targetId = data['target_user_id'] as String?;
    final targetName = data['target_username'] as String?;

    if (targetId == _currentUser.id ||
        (targetName != null && targetName == _currentUser.username)) {
      onForceMuteReceived?.call();
    } else {
      final displayName = targetName ?? 'Peserta';
      onModerationNotice?.call('Mikrofon $displayName telah dimatikan.');
    }
  }

  /// Handles incoming CO_HOST_UPDATED broadcast event
  @visibleForTesting
  void handleCoHostUpdated(Map<String, dynamic> data) {
    final targetId = data['target_user_id'] as String?;
    final targetName = data['target_username'] as String? ?? 'Peserta';
    final isCoHostVal = data['is_co_host'] as bool? ?? false;

    if (targetId != null) {
      if (isCoHostVal) {
        _coHostUserIds.add(targetId);
        onModerationNotice?.call('⭐ $targetName sekarang menjadi Co-Host.');
      } else {
        _coHostUserIds.remove(targetId);
        onModerationNotice?.call('👤 $targetName tidak lagi menjadi Co-Host.');
      }
      notifyListeners();
    }
  }

  /// Kicks a participant from the room (Host or Co-Host only)
  Future<void> kickParticipant(UserProfile target, {String? reason, dynamic chatController}) async {
    if (!canModerateUser(target.id) && !canModerateUser(target.username)) return;

    _kickedUserIds.add(target.id);
    _kickedUserIds.add(target.username);
    final effectiveReason = reason ?? 'Dikeluarkan dari room oleh ${currentUser.username}.';

    // Broadcast KICK_PARTICIPANT
    try {
      if (_presenceChannel != null) {
        await _presenceChannel!.sendBroadcastMessage(
          event: 'KICK_PARTICIPANT',
          payload: {
            'room_id': _state.room.id,
            'code': _state.room.code,
            'target_user_id': target.id,
            'target_username': target.username,
            'by_user_id': currentUser.id,
            'by_username': currentUser.username,
            'reason': effectiveReason,
          },
        );
      }
    } catch (e) {
      debugPrint('[RoomController] Error broadcasting KICK_PARTICIPANT: $e');
    }

    final updated = _state.participants
        .where((p) => p.id != target.id && p.username != target.username)
        .toList();
    _state = _state.copyWith(
      participants: updated,
      room: _state.room.copyWith(participantCount: updated.length),
    );
    notifyListeners();

    try {
      chatController?.sendSystemMessage(
        '🚫 ${target.username} dikeluarkan dari room oleh ${currentUser.username}.',
      );
    } catch (_) {}
  }

  /// Force mutes a participant\'s microphone (Host or Co-Host only)
  Future<void> forceMuteParticipant(UserProfile target, {dynamic chatController}) async {
    if (!canModerateUser(target.id) && !canModerateUser(target.username)) return;

    try {
      if (_presenceChannel != null) {
        await _presenceChannel!.sendBroadcastMessage(
          event: 'FORCE_MUTE_PARTICIPANT',
          payload: {
            'room_id': _state.room.id,
            'code': _state.room.code,
            'target_user_id': target.id,
            'target_username': target.username,
            'by_user_id': currentUser.id,
            'by_username': currentUser.username,
          },
        );
      }
    } catch (e) {
      debugPrint('[RoomController] Error broadcasting FORCE_MUTE_PARTICIPANT: $e');
    }

    try {
      chatController?.sendSystemMessage(
        '🔇 Mikrofon ${target.username} dimatikan oleh ${currentUser.username}.',
      );
    } catch (_) {}
  }

  /// Toggles Co-Host role for a participant (Host only)
  Future<void> toggleCoHost(UserProfile target, {dynamic chatController}) async {
    if (!isHost) return;

    final isTargetCurrentlyCoHost = isCoHost(target.id);
    final newCoHostState = !isTargetCurrentlyCoHost;

    if (newCoHostState) {
      _coHostUserIds.add(target.id);
    } else {
      _coHostUserIds.remove(target.id);
    }
    notifyListeners();

    try {
      if (_presenceChannel != null) {
        await _presenceChannel!.sendBroadcastMessage(
          event: 'CO_HOST_UPDATED',
          payload: {
            'room_id': _state.room.id,
            'code': _state.room.code,
            'target_user_id': target.id,
            'target_username': target.username,
            'is_co_host': newCoHostState,
            'by_user_id': currentUser.id,
            'by_username': currentUser.username,
          },
        );
      }
    } catch (e) {
      debugPrint('[RoomController] Error broadcasting CO_HOST_UPDATED: $e');
    }

    try {
      chatController?.sendSystemMessage(
        newCoHostState
            ? '⭐ ${target.username} sekarang menjadi Co-Host.'
            : '👤 ${target.username} tidak lagi menjadi Co-Host.',
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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
