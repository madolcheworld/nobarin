import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/network/supabase_client.dart';
import '../../auth/domain/user_profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../models/local_video_file.dart';
import '../services/p2p_webrtc_host_streamer.dart';
import '../services/p2p_webrtc_viewer_client.dart';

class P2pStreamController extends ChangeNotifier {
  final String roomId;
  final UserProfile currentUser;
  final SupabaseClient? supabase;
  final RealtimeChannel? sharedChannel;

  P2pWebRtcHostStreamer? _hostStreamer;
  P2pWebRtcViewerClient? _viewerClient;
  bool _isDisposed = false;

  P2pWebRtcHostStreamer? get hostStreamer => _hostStreamer;
  P2pWebRtcViewerClient? get viewerClient => _viewerClient;

  bool get isHostStreaming => _hostStreamer?.isStreaming ?? false;
  bool get isViewerStreaming => _viewerClient?.isConnected ?? false;
  bool get isP2pActive => isHostStreaming || isViewerStreaming;

  LocalVideoFile? get hostFile => _hostStreamer?.currentFile;
  String? get currentVideoTitle =>
      isHostStreaming ? _hostStreamer?.currentFile?.name : _viewerClient?.fileName;

  String get streamUrl {
    if (isHostStreaming && _hostStreamer?.currentFile != null) {
      // Host plays local file path directly (media_kit native zero buffering)
      return _hostStreamer!.currentFile!.path ?? '';
    } else if (_viewerClient != null && _viewerClient!.isConnected) {
      return _viewerClient!.streamUrl;
    }
    return '';
  }

  P2pStreamController({
    required this.roomId,
    required this.currentUser,
    this.supabase,
    this.sharedChannel,
  }) {
    _initServices();
  }

  void _initServices() {
    _hostStreamer = P2pWebRtcHostStreamer(
      roomId: roomId,
      userId: currentUser.id,
      userName: currentUser.username,
      supabase: supabase,
      sharedChannel: sharedChannel,
    );
    _hostStreamer!.addListener(_onStateChanged);

    _viewerClient = P2pWebRtcViewerClient(
      roomId: roomId,
      userId: currentUser.id,
      userName: currentUser.username,
      supabase: supabase,
      sharedChannel: sharedChannel,
    );
    _viewerClient!.addListener(_onStateChanged);

    // Check if another host is already broadcasting
    _viewerClient!.queryActiveStream();
  }

  void _onStateChanged() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// Host starts streaming a chosen local video file
  Future<void> startHostStreaming(LocalVideoFile file) async {
    if (_hostStreamer == null) return;
    await _viewerClient?.disconnect();
    await _hostStreamer!.setLocalVideoFile(file);
  }

  /// Host stops streaming
  Future<void> stopHostStreaming() async {
    if (_hostStreamer == null) return;
    await _hostStreamer!.stopStreaming();
  }

  /// Viewer manually connects or reconnects to host
  Future<void> connectToHost(String hostId) async {
    if (_viewerClient == null) return;
    await _viewerClient!.connectToHost(hostId);
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double s = bytes.toDouble();
    while (s >= 1024 && i < suffixes.length - 1) {
      s /= 1024;
      i++;
    }
    return '${s.toStringAsFixed(s >= 100 ? 0 : 1)} ${suffixes[i]}';
  }

  @override
  void dispose() {
    _isDisposed = true;
    _hostStreamer?.removeListener(_onStateChanged);
    _viewerClient?.removeListener(_onStateChanged);
    _hostStreamer?.dispose();
    _viewerClient?.dispose();
    super.dispose();
  }
}

final p2pStreamControllerProvider = Provider.autoDispose
    .family<P2pStreamController, String>((ref, roomId) {
  final user = ref.watch(authControllerProvider).asData?.value;
  final supabase = SupabaseService().clientOrNull;

  final profile = user ??
      UserProfile(
        id: 'guest_${DateTime.now().millisecondsSinceEpoch}',
        username: 'Guest',
        avatarUrl: 'preset_1',
      );

  final controller = P2pStreamController(
    roomId: roomId,
    currentUser: profile,
    supabase: supabase,
  );
  ref.onDispose(() => controller.dispose());
  return controller;
});
