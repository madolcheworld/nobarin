/// Base class for all domain and application level failures
sealed class AppFailure {
  final String message;
  final Object? cause;

  const AppFailure(this.message, [this.cause]);

  @override
  String toString() => message;
}

/// Failure due to network connectivity issues or request timeouts
class NetworkFailure extends AppFailure {
  const NetworkFailure([
    super.message = 'Gangguan koneksi internet atau server tidak merespons.',
    super.cause,
  ]);
}

/// Failure during guest login or user profile synchronization
class AuthFailure extends AppFailure {
  const AuthFailure([
    super.message = 'Gagal melakukan autentikasi atau menyimpan profil pengguna.',
    super.cause,
  ]);
}

/// Failure when a requested room does not exist
class RoomNotFoundFailure extends AppFailure {
  final String code;
  RoomNotFoundFailure(this.code, [Object? cause])
      : super('Room dengan kode "$code" tidak ditemukan atau sudah tidak aktif.', cause);
}

/// Failure when a room has been terminated by the host
class RoomClosedFailure extends AppFailure {
  final String reason;
  RoomClosedFailure([
    this.reason = 'Room telah ditutup oleh Host.',
    Object? cause,
  ]) : super(reason, cause);
}

/// Failure during video/audio media loading or playback
class MediaPlaybackFailure extends AppFailure {
  const MediaPlaybackFailure([
    super.message = 'Gagal memutar konten video atau audio.',
    super.cause,
  ]);
}

/// Failure during WebRTC signaling or P2P media stream routing
class WebRtcFailure extends AppFailure {
  const WebRtcFailure([
    super.message = 'Gagal menghubungkan sesi suara atau berbagi layar.',
    super.cause,
  ]);
}

/// Failure when OS device permissions (mic, screen capture) are denied
class PermissionFailure extends AppFailure {
  final String permissionName;
  const PermissionFailure(
    this.permissionName, [
    super.message = 'Izin perangkat diperlukan untuk melanjutkan.',
    super.cause,
  ]);
}

/// Failure occurring inside database or backend queries
class ServerFailure extends AppFailure {
  const ServerFailure([
    super.message = 'Terjadi kesalahan pada server database.',
    super.cause,
  ]);
}
