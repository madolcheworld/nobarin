import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Precision Network Time Protocol (NTP) Clock Synchronization engine
/// utilizing Cristian's Algorithm with multi-probe burst sampling, outlier filtering,
/// and hardware monotonic clock anchoring for jitter-free reference time.
class NtpClockSync {
  static final NtpClockSync _instance = NtpClockSync._internal();
  factory NtpClockSync() => _instance;
  NtpClockSync._internal();

  @visibleForTesting
  NtpClockSync.custom({int offsetMs = 0}) : _clockOffsetMs = offsetMs;

  int _clockOffsetMs = 0;
  int? _monotonicAnchorEpochMs;
  final Stopwatch _monotonicStopwatch = Stopwatch();

  int _bestRttMs = 0;
  int _errorBoundMs = 0;
  DateTime? _lastSyncTime;
  Timer? _periodicSyncTimer;
  bool _isSyncing = false;

  /// Measured clock offset between server and local clock in milliseconds
  int get clockOffsetMs => _clockOffsetMs;

  /// Lowest Round-Trip Time (RTT) observed in the latest sync burst
  int get bestRttMs => _bestRttMs;

  /// Theoretical maximum error bound: ±(minRTT / 2)
  int get errorBoundMs => _errorBoundMs;

  /// Timestamp of the last successful synchronization
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Whether the clock has been synchronized with the server
  bool get isCalibrated => _lastSyncTime != null || _monotonicAnchorEpochMs != null;

  /// Sets clock offset directly (useful for tests or manual calibration).
  /// Calling this also resets the monotonic anchor.
  void setClockOffset(int offsetMs) {
    _clockOffsetMs = offsetMs;
    _monotonicAnchorEpochMs = null;
    _monotonicStopwatch.stop();
    _monotonicStopwatch.reset();
  }

  /// Calculates synchronized current epoch time in milliseconds.
  /// If calibrated via [syncWithSupabase], it uses the device's hardware monotonic
  /// [Stopwatch] anchored to the calibrated server epoch, rendering it immune to
  /// OS wall-clock jumps or cellular tower time corrections.
  int get synchronizedTimestampMs {
    if (_monotonicAnchorEpochMs != null && _monotonicStopwatch.isRunning) {
      return _monotonicAnchorEpochMs! + _monotonicStopwatch.elapsedMilliseconds;
    }
    return DateTime.now().millisecondsSinceEpoch + _clockOffsetMs;
  }

  /// Synchronizes local clock with Supabase server time using Cristian's Algorithm.
  /// Executes a burst of [probeCount] probes, discards high-RTT outliers, and selects
  /// the probe with the minimum RTT for minimal queuing delay and maximum symmetry.
  Future<void> syncWithSupabase(
    SupabaseClient client, {
    int probeCount = 5,
  }) async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final List<_ProbeResult> results = [];

      for (int i = 0; i < probeCount; i++) {
        final int t0 = DateTime.now().millisecondsSinceEpoch;

        // Try get_server_time RPC, fallback to now RPC
        dynamic response = await client
            .rpc('get_server_time')
            .catchError((_) => null);

        response ??= await client
            .rpc('now')
            .catchError((_) => null);

        final int t1 = DateTime.now().millisecondsSinceEpoch;
        final int rtt = max(1, t1 - t0);

        if (response != null) {
          var timeStr = response.toString().trim();
          if (!timeStr.endsWith('Z') &&
              !timeStr.contains('+') &&
              !RegExp(r'-\d{2}:\d{2}$').hasMatch(timeStr)) {
            timeStr = '${timeStr}Z';
          }
          final serverDateTime = DateTime.tryParse(timeStr);
          if (serverDateTime != null) {
            final int serverTimeMs = serverDateTime.millisecondsSinceEpoch;
            final int estimatedServerTimeNow = serverTimeMs + (rtt ~/ 2);
            final int offset = estimatedServerTimeNow - t1;

            results.add(_ProbeResult(
              rtt: rtt,
              offset: offset,
              serverEstimatedNow: estimatedServerTimeNow,
            ));
          }
        }

        // Brief delay between probes (except last probe) to allow network stabilization
        if (i < probeCount - 1 && probeCount > 1) {
          await Future.delayed(const Duration(milliseconds: 60));
        }
      }

      if (results.isNotEmpty) {
        // Sort by RTT ascending to find the probe with lowest propagation delay
        results.sort((a, b) => a.rtt.compareTo(b.rtt));

        // Filter out high-latency outliers (greater than 1.8x minimum RTT if multiple probes)
        final minRtt = results.first.rtt;
        final validProbes = results.where((p) => p.rtt <= max(minRtt * 1.8, minRtt + 50)).toList();

        // Best probe is the one with the smallest RTT
        final best = validProbes.isNotEmpty ? validProbes.first : results.first;

        _bestRttMs = best.rtt;
        _errorBoundMs = best.rtt ~/ 2;
        _clockOffsetMs = best.offset;

        // Anchor hardware monotonic stopwatch to prevent OS clock jumps
        _monotonicAnchorEpochMs = best.serverEstimatedNow;
        _monotonicStopwatch.reset();
        _monotonicStopwatch.start();

        _lastSyncTime = DateTime.now();

        debugPrint(
          '[NtpClockSync] Calibrated via Cristian\'s Algorithm (${results.length} probes). '
          'Offset: ${_clockOffsetMs}ms, Min RTT: ${_bestRttMs}ms, Precision: ±${_errorBoundMs}ms',
        );
        return;
      }

      debugPrint('[NtpClockSync] Server time fallback to local clock.');
    } catch (e) {
      debugPrint('[NtpClockSync] Clock sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Starts background periodic re-synchronization to account for physical oscillator drift.
  void startPeriodicSync(
    SupabaseClient client, {
    Duration interval = const Duration(minutes: 10),
  }) {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(interval, (_) {
      syncWithSupabase(client, probeCount: 3);
    });
  }

  /// Stops periodic re-synchronization
  void stopPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }
}

class _ProbeResult {
  final int rtt;
  final int offset;
  final int serverEstimatedNow;

  const _ProbeResult({
    required this.rtt,
    required this.offset,
    required this.serverEstimatedNow,
  });
}
