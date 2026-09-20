import '../../../core/utils/ntp_clock_sync.dart';
import '../models/sync_payload.dart';

/// High-Precision Video Synchronization Engine
/// Implements state-aware drift detection, Exponential Moving Average (EMA) low-pass filtering,
/// multi-tier proportional slewing (pitch-safe micro-speed adjustments), and seek cooldown guards.
class SyncEngine {
  final NtpClockSync _clockSync;

  // Low-Pass Filter (EMA) state
  double? _smoothedDriftSeconds;
  static const double defaultFilterAlpha = 0.35;

  // Seek Cooldown Guard
  DateTime? _lastSeekTime;
  static const Duration defaultSeekCooldown = Duration(milliseconds: 1500);

  SyncEngine({NtpClockSync? clockSync})
      : _clockSync = clockSync ?? NtpClockSync();

  NtpClockSync get clockSync => _clockSync;

  /// Calculates the real-time target position in seconds of the video,
  /// factoring in clock offset, transmission delay, and playback speed.
  double calculateTargetPosition(
    SyncPayload payload, [
    int? currentTimestampMs,
    double? maxDurationSeconds,
  ]) {
    final int now = currentTimestampMs ?? _clockSync.synchronizedTimestampMs;
    return payload.calculateTargetPosition(now, maxDurationSeconds);
  }

  /// Calculates signed drift (target - local).
  /// Positive means client is lagging behind host; Negative means client is ahead of host.
  double calculateSignedDrift(
    SyncPayload payload,
    double currentLocalPositionSeconds, [
    int? currentTimestampMs,
    double? maxDurationSeconds,
  ]) {
    final int now = currentTimestampMs ?? _clockSync.synchronizedTimestampMs;
    return payload.calculateSignedDrift(currentLocalPositionSeconds, now, maxDurationSeconds);
  }

  /// Calculates drift (absolute difference) between current video position and host target position.
  double calculateDrift(
    SyncPayload payload,
    double currentLocalPositionSeconds, [
    int? currentTimestampMs,
    double? maxDurationSeconds,
  ]) {
    return calculateSignedDrift(
      payload,
      currentLocalPositionSeconds,
      currentTimestampMs,
      maxDurationSeconds,
    ).abs();
  }

  /// Applies an Exponential Moving Average (EMA) low-pass filter to smooth out
  /// single-frame decoding or UI rendering timing spikes.
  double applyLowPassFilter(double rawDriftSeconds, {double alpha = defaultFilterAlpha}) {
    if (_smoothedDriftSeconds == null) {
      _smoothedDriftSeconds = rawDriftSeconds;
    } else {
      _smoothedDriftSeconds = (alpha * rawDriftSeconds) + ((1.0 - alpha) * _smoothedDriftSeconds!);
    }
    return _smoothedDriftSeconds!;
  }

  /// Resets the low-pass filter (e.g., after a hard seek or media change).
  void resetFilter() {
    _smoothedDriftSeconds = null;
  }

  /// Determines appropriate drift correction action according to Section 3 of plan.md
  /// and enhanced state-aware rules (paused videos seek directly rather than micro-slewing).
  DriftAction evaluateCorrection(
    SyncPayload payload,
    double currentLocalPositionSeconds, [
    int? currentTimestampMs,
    double? maxDurationSeconds,
  ]) {
    final int now = currentTimestampMs ?? _clockSync.synchronizedTimestampMs;
    return payload.evaluateCorrection(currentLocalPositionSeconds, now, maxDurationSeconds);
  }

  /// Standard recommended playback speed for basic micro-adjustments:
  /// - Lagging behind -> 1.06x
  /// - Ahead -> 0.94x
  /// - In sync / Hard Seek -> 1.0x
  double getRecommendedSpeed(DriftAction action) {
    switch (action) {
      case DriftAction.microSpeedUp:
        return 1.06;
      case DriftAction.microSlowDown:
        return 0.94;
      case DriftAction.noAction:
      case DriftAction.hardSeek:
        return 1.0;
    }
  }

  /// Multi-tier proportional playback speed calculator for smooth, imperceptible slewing.
  /// Tier 0 (< 80ms): 1.0x (In-sync deadband)
  /// Tier 1 (80ms - 350ms): 1.025x / 0.975x (Ultra-fine, 100% imperceptible pitch)
  /// Tier 2 (350ms - 1000ms): 1.05x / 0.95x (Moderate slew)
  /// Tier 3 (1000ms - 1800ms): 1.08x / 0.92x (Catch-up slew)
  /// Tier 4 (>= 1800ms): Hard seek
  double calculateAdaptiveSpeed({
    required SyncPayload payload,
    required double currentLocalPositionSeconds,
    int? currentTimestampMs,
    double? maxDurationSeconds,
    bool isYouTube = false,
    double currentSpeed = 1.0,
  }) {
    if (payload.state != 'playing') {
      return 1.0;
    }

    final signedDrift = calculateSignedDrift(
      payload,
      currentLocalPositionSeconds,
      currentTimestampMs,
      maxDurationSeconds,
    );
    final absDrift = signedDrift.abs();

    // YouTube IFrame API only supports discrete rates [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    if (isYouTube) {
      if (absDrift < 0.4) {
        return 1.0;
      }
      if (absDrift < 1.8) {
        return signedDrift > 0 ? 1.25 : 0.75;
      }
      return 1.0; // Handled via hard seek
    }

    // Direct Video (MediaKit / HTML5 Video) continuous proportional slewing
    // Hysteresis deadband: if already slewing, keep slewing until drift < 0.04s (40ms).
    // If at normal speed, only engage slewing when drift >= 0.08s (80ms).
    final minThreshold = (currentSpeed != 1.0) ? 0.04 : 0.08;
    if (absDrift < minThreshold) {
      return 1.0;
    } else if (absDrift < 0.35) {
      return signedDrift > 0 ? 1.025 : 0.975;
    } else if (absDrift < 1.0) {
      return signedDrift > 0 ? 1.05 : 0.95;
    } else if (absDrift < 1.8) {
      return signedDrift > 0 ? 1.08 : 0.92;
    }

    return 1.0; // Desync >= 1.8s triggers hard seek instead of slewing
  }

  /// Records that a seek action was executed, initializing the seek cooldown window.
  void recordSeek() {
    _lastSeekTime = DateTime.now();
    resetFilter();
  }

  /// Checks if a hard seek is currently in cooldown to prevent "buffering death loops".
  bool isSeekInCooldown([Duration cooldown = defaultSeekCooldown]) {
    if (_lastSeekTime == null) return false;
    return DateTime.now().difference(_lastSeekTime!) < cooldown;
  }
}
