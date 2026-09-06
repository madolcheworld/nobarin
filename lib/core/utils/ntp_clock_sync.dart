import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NtpClockSync {
  static final NtpClockSync _instance = NtpClockSync._internal();
  factory NtpClockSync() => _instance;
  NtpClockSync._internal();

  int _clockOffsetMs = 0;
  bool _isSynchronized = false;

  int get clockOffsetMs => _clockOffsetMs;
  bool get isSynchronized => _isSynchronized;

  /// Sets clock offset directly (useful for tests or manual calibration)
  void setClockOffset(int offsetMs) {
    _clockOffsetMs = offsetMs;
    _isSynchronized = true;
  }

  /// Calculates synchronized current epoch time in milliseconds
  int get synchronizedTimestampMs {
    return DateTime.now().millisecondsSinceEpoch + _clockOffsetMs;
  }

  /// Synchronizes local clock with Supabase server time
  Future<void> syncWithSupabase(SupabaseClient client) async {
    try {
      final int t0 = DateTime.now().millisecondsSinceEpoch;
      // Try get_server_time RPC, fallback to now RPC
      dynamic response = await client
          .rpc('get_server_time')
          .catchError((_) => null);

      response ??= await client
          .rpc('now')
          .catchError((_) => null);

      final int t1 = DateTime.now().millisecondsSinceEpoch;
      final int roundTripTime = t1 - t0;

      if (response != null) {
        final serverDateTime = DateTime.tryParse(response.toString());
        if (serverDateTime != null) {
          final int serverTimeMs = serverDateTime.millisecondsSinceEpoch;
          // Approximate server time when response arrived = serverTime + (roundTrip / 2)
          final int estimatedServerTimeNow = serverTimeMs + (roundTripTime ~/ 2);
          _clockOffsetMs = estimatedServerTimeNow - t1;
          _isSynchronized = true;
          debugPrint(
              '[NtpClockSync] Synced with server. Offset: ${_clockOffsetMs}ms (RTT: ${roundTripTime}ms)');
          return;
        }
      }
      debugPrint('[NtpClockSync] Server time fallback to local clock.');
    } catch (e) {
      debugPrint('[NtpClockSync] Clock sync error: $e');
    }
  }

  /// Reset to zero offset
  void reset() {
    _clockOffsetMs = 0;
    _isSynchronized = false;
  }
}
