import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../chat/controllers/chat_controller.dart';
import '../../chat/presentation/chat_panel_widget.dart';
import '../../chat/presentation/floating_reaction_overlay.dart';
import '../../lobby/presentation/lobby_controller.dart';
import '../../voice/controllers/webrtc_voice_controller.dart';
import '../../voice/presentation/voice_control_bar.dart';
import '../controllers/room_controller.dart';
import '../controllers/sync_controller.dart';
import '../controllers/unified_player_controller.dart';
import '../models/room_model.dart';
import 'widgets/media_source_picker.dart';
import 'widgets/participants_header.dart';
import 'widgets/room_controls_bar.dart';
import 'widgets/unified_player_view.dart';

class RoomScreen extends ConsumerStatefulWidget {
  final String roomCode;
  final RoomModel? initialRoom;

  const RoomScreen({
    super.key,
    required this.roomCode,
    this.initialRoom,
  });

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  RoomModel? _room;
  bool _isLoading = true;
  String? _errorMessage;

  late final UnifiedPlayerController _player;
  SyncController? _syncController;
  RoomController? _roomController;
  ChatController? _chatController;
  WebRtcVoiceController? _voiceController;

  @override
  void initState() {
    super.initState();
    _player = UnifiedPlayerController();
    _fetchAndInitializeRoom();
  }

  Future<void> _fetchAndInitializeRoom() async {
    var user = ref.read(authControllerProvider).asData?.value;
    if (user == null && ref.read(authControllerProvider).isLoading) {
      await ref.read(authControllerProvider.notifier).loadInitialProfile();
      user = ref.read(authControllerProvider).asData?.value;
    }

    if (user == null) {
      if (mounted) context.go('/?room=${widget.roomCode}');
      return;
    }

    RoomModel? room = widget.initialRoom;
    room ??= await ref
        .read(lobbyControllerProvider.notifier)
        .findRoomByCode(widget.roomCode);

    if (!mounted) return;

    if (room == null || room.currentState == 'closed') {
      setState(() {
        _isLoading = false;
        _errorMessage = room?.currentState == 'closed'
            ? 'Room dengan kode "${widget.roomCode}" telah ditutup oleh Host.'
            : 'Room dengan kode "${widget.roomCode}" tidak ditemukan.';
      });
      return;
    }

    setState(() {
      _room = room;
      _isLoading = false;
    });

    SupabaseClient? supabase;
    try {
      supabase = Supabase.instance.client;
    } catch (_) {}

    try {
      _roomController = RoomController(
        initialRoom: room,
        currentUser: user,
        supabase: supabase,
      );

      _syncController = SyncController(
        room: room,
        currentUser: user,
        player: _player,
        supabase: supabase,
        isHostProvider: () => _roomController?.isHost ?? false,
      );

      _roomController!.onRoomClosed = (reason) {
        if (!mounted) return;
        // Dismiss any open confirmation or modal dialogs before navigating
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(reason)),
              ],
            ),
            backgroundColor: AppColors.accentRed,
            duration: const Duration(seconds: 4),
          ),
        );
        ref.read(lobbyControllerProvider.notifier).refreshRooms();
        context.go('/lobby');
      };

      _chatController = ChatController(
        roomId: room.id,
        currentUser: user,
        supabase: supabase,
      );

      _voiceController = WebRtcVoiceController(
        roomId: room.id,
        userId: user.id,
        userName: user.username,
        playerController: _player,
        supabase: supabase,
        iceConfiguration: ApiConstants.rtcIceConfiguration,
      );

      _voiceController!.connect();

      _chatController!.sendSystemMessage(
        '${user.username} bergabung ke dalam room.',
      );

      _roomController!.addListener(_onControllerUpdated);
      _voiceController!.addListener(_onControllerUpdated);

      // Initial media load
      if (room.currentMediaUrl != null && room.currentMediaUrl!.isNotEmpty) {
        _player.loadMedia(
          room.currentMediaType ?? 'direct_url',
          room.currentMediaUrl!,
          autoPlay: room.isPlaying,
          startSeconds: room.currentPosition,
        );
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('[RoomScreen] Non-fatal controller initialization error: $e');
    }
  }

  bool _isHandlingRoomClosed = false;

  void _onControllerUpdated() {
    if (mounted) {
      if (_roomController != null && _syncController != null) {
        final currentRoom = _roomController!.currentRoom;
        if (_room != currentRoom) {
          _room = currentRoom;
          _syncController!.updateRoom(currentRoom);
        }
      }

      if (_roomController != null &&
          _roomController!.isRoomClosed &&
          !_roomController!.isHost &&
          !_isHandlingRoomClosed) {
        _isHandlingRoomClosed = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final reason = _roomController?.state.closedReason ??
                'Room telah ditutup oleh host.';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(reason),
                backgroundColor: AppColors.accentRed,
                duration: const Duration(seconds: 4),
              ),
            );
            ref.read(lobbyControllerProvider.notifier).refreshRooms();
            context.go('/lobby');
          }
        });
        return;
      }

      debugPrint(
          '[RoomScreen] _onControllerUpdated: participants=${_roomController?.state.participants.length}');
      setState(() {});
    }
  }

  @override
  void dispose() {
    _roomController?.removeListener(_onControllerUpdated);
    _voiceController?.removeListener(_onControllerUpdated);
    _player.dispose();
    _syncController?.dispose();

    // Auto-close room if host leaves unexpectedly (e.g. browser back button, URL navigation)
    if (_roomController != null &&
        _roomController!.isHost &&
        !_roomController!.isRoomClosed &&
        _room != null) {
      _roomController!.closeOrDeleteRoom();
      try {
        ref.read(lobbyControllerProvider.notifier).deleteRoom(
              _room!.id,
              code: _room!.code,
            );
      } catch (_) {}
    }

    _roomController?.dispose();
    _chatController?.dispose();
    _voiceController?.dispose();
    super.dispose();
  }

  void _openMediaPicker() {
    if (_syncController == null) return;
    showDialog(
      context: context,
      builder: (_) => MediaSourcePicker(
        syncController: _syncController!,
        chatController: _chatController,
      ),
    );
  }

  Future<void> _handleExitRoom() async {
    // If YouTube player is in fullscreen, exit fullscreen first
    if (_player.ytController?.value.fullScreenOption.enabled == true) {
      _player.ytController?.exitFullScreen();
    }

    final navigator = GoRouter.of(context);
    final shouldLeave = await _onWillPop();
    if (shouldLeave && mounted) {
      await _cleanupAndLeave();
      if (mounted) {
        ref.read(lobbyControllerProvider.notifier).refreshRooms();
        navigator.go('/lobby');
      }
    }
  }

  Future<void> _cleanupAndLeave() async {
    final user = ref.read(authControllerProvider).asData?.value;
    final isHost = _roomController?.isHost ??
        (_room?.hostId != null &&
            _room?.hostId!.isNotEmpty == true &&
            (_room?.hostId == user?.id ||
                _room?.hostId == _roomController?.currentUser.id)) ||
        (user != null &&
            _room?.hostName != null &&
            _room?.hostName!.isNotEmpty == true &&
            _room?.hostName != 'Host' &&
            _room?.hostName == user.username);

    if (isHost && _room != null) {
      // 1. Broadcast ROOM_CLOSED and delete from Supabase via RoomController
      await _roomController?.closeOrDeleteRoom();

      // 2. Delete room from LobbyController and LobbyRepository (removes from _demoRooms and DB)
      await ref.read(lobbyControllerProvider.notifier).deleteRoom(
            _room!.id,
            code: _room!.code,
          );
    }

    // Send chat leave system message
    if (user != null && _chatController != null) {
      try {
        await _chatController!.sendSystemMessage(
          isHost
              ? '${user.username} (Host) keluar dan menutup room.'
              : '${user.username} meninggalkan room.',
        );
      } catch (_) {}
    }

    // Disconnect voice
    _voiceController?.disconnect();
  }

  Future<bool> _onWillPop() async {
    // If room is already marked closed (e.g. host closed it or kicked), bypass dialog
    if (_roomController?.isRoomClosed == true) {
      return true;
    }

    final user = ref.read(authControllerProvider).asData?.value;
    final isHost = _roomController?.isHost ??
        (_room?.hostId != null &&
            _room?.hostId!.isNotEmpty == true &&
            (_room?.hostId == user?.id ||
                _room?.hostId == _roomController?.currentUser.id)) ||
        (user != null &&
            _room?.hostName != null &&
            _room?.hostName!.isNotEmpty == true &&
            _room?.hostName != 'Host' &&
            _room?.hostName == user.username);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isHost ? 'Tutup & Hapus Room?' : 'Keluar dari Room?'),
        content: Text(
          isHost
              ? 'Sebagai host, meninggalkan room akan menghapus room publik ini dan mengeluarkan semua peserta ke lobby. Yakin ingin keluar?'
              : 'Apakah kamu yakin ingin meninggalkan watch party ini?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentRed,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(isHost ? 'Tutup Room' : 'Keluar'),
          ),
        ],
      ),
    );
    return confirm ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryNeon),
        ),
      );
    }

    if (_roomController?.isRoomClosed == true && !_roomController!.isHost) {
      return Scaffold(
        appBar: AppBar(title: const Text('Watch Party')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 54, color: AppColors.primaryNeon),
                const SizedBox(height: 16),
                Text(
                  _roomController?.state.closedReason ??
                      'Room telah ditutup oleh Host.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => context.go('/lobby'),
                  child: const Text('Kembali ke Lobby'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_errorMessage != null || _room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Watch Party')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 54, color: AppColors.accentRed),
                const SizedBox(height: 16),
                Text(
                  _errorMessage ?? 'Terjadi kesalahan',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => context.go('/lobby'),
                  child: const Text('Kembali ke Lobby'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final authProfile = ref.watch(authControllerProvider).asData?.value;
    final currentRoom = _roomController?.state.room ?? _room!;
    final participants = _roomController?.state.participants ??
        (authProfile != null ? [authProfile] : const []);
    final speakingIds = _voiceController?.activeSpeakerIds ?? {};
    final mutedIds = _voiceController?.mutedUserIds ?? {};
    final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        _handleExitRoom();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _handleExitRoom,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentRoom.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryNeon.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      currentRoom.code,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryNeon,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    currentRoom.isHostOnly
                        ? '👑 Host Only'
                        : '🤝 Collaborative',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.exit_to_app_rounded),
              tooltip: 'Keluar dari Room',
              onPressed: _handleExitRoom,
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 850;

            if (isDesktop) {
              // Desktop / Landscape layout: Large video on left, Sidebar on right
              return Row(
                children: [
                  // Left: Video & Controls
                  Expanded(
                    flex: 7,
                    child: Column(
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              UnifiedPlayerView(
                                player: _player,
                                syncController: _syncController!,
                                onOpenMediaPicker: _openMediaPicker,
                                onExit: _handleExitRoom,
                                title: currentRoom.title,
                                showTopBar: false,
                              ),
                              if (_chatController != null)
                                FloatingReactionOverlay(
                                  chatController: _chatController!,
                                ),
                            ],
                          ),
                        ),
                        RoomControlsBar(
                          syncController: _syncController!,
                          player: _player,
                          roomController: _roomController!,
                          onOpenMediaPicker: _openMediaPicker,
                        ),
                      ],
                    ),
                  ),

                  const VerticalDivider(width: 1, color: AppColors.border),

                  // Right Sidebar: Participants + Chat + Voice Bar
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        ParticipantsHeader(
                          participants: participants,
                          hostId: currentRoom.hostId,
                          hostName: currentRoom.hostName,
                          speakingUserIds: speakingIds,
                          mutedUserIds: mutedIds,
                        ),
                        Expanded(
                          child: _chatController != null
                              ? ChatPanelWidget(
                                  chatController: _chatController!,
                                )
                              : const SizedBox.shrink(),
                        ),
                        if (_voiceController != null)
                          VoiceControlBar(
                            voiceController: _voiceController!,
                          ),
                      ],
                    ),
                  ),
                ],
              );
            }

            // Mobile Portrait Layout: Top video, Middle controls & participants, Bottom chat
            return Column(
              children: [
                // Top Video with Floating Reactions
                Stack(
                  children: [
                    UnifiedPlayerView(
                      player: _player,
                      syncController: _syncController!,
                      onOpenMediaPicker: _openMediaPicker,
                      onExit: _handleExitRoom,
                      title: currentRoom.title,
                      showTopBar: false,
                    ),
                    if (_chatController != null)
                      Positioned.fill(
                        child: FloatingReactionOverlay(
                          chatController: _chatController!,
                        ),
                      ),
                  ],
                ),

                // Controls Bar
                RoomControlsBar(
                  syncController: _syncController!,
                  player: _player,
                  roomController: _roomController!,
                  onOpenMediaPicker: _openMediaPicker,
                ),

                // Participants Header
                ParticipantsHeader(
                  participants: participants,
                  hostId: currentRoom.hostId,
                  hostName: currentRoom.hostName,
                  speakingUserIds: speakingIds,
                  mutedUserIds: mutedIds,
                ),

                // Chat Panel (fills rest of screen)
                Expanded(
                  child: _chatController != null
                      ? ChatPanelWidget(
                          key: const ValueKey('chat_panel'),
                          chatController: _chatController!,
                        )
                      : const SizedBox.shrink(),
                ),

                // Bottom VoIP Voice Control Bar (hidden while soft keyboard is active)
                if (_voiceController != null && !isKeyboardOpen)
                  VoiceControlBar(
                    voiceController: _voiceController!,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
