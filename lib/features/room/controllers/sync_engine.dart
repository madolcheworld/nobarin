import '../../../core/utils/ntp_clock_sync.dart';
import '../models/sync_payload.dart';

class SyncEngine {
  final NtpClockSync _clockSync;

  SyncEngine({NtpClockSync? clockSync})
      : _clockSync = clockSync ?? NtpClockSync();

  /// Calculates the real-time target position in seconds of the video
  double calculateTargetPosition(
    SyncPayload payload, [
    int? currentTimestampMs,
  ]) {
    final int now = currentTimestampMs ?? _clockSync.synchronizedTimestampMs;
    return payload.calculateTargetPosition(now);
  }

  /// Calculates drift (absolute difference) between current video position and host target position
  double calculateDrift(
    SyncPayload payload,
    double currentLocalPositionSeconds, [
    int? currentTimestampMs,
  ]) {
    final int now = currentTimestampMs ?? _clockSync.synchronizedTimestampMs;
    return payload.calculateDrift(currentLocalPositionSeconds, now);
  }

  /// Determines appropriate drift correction action according to Section 3 of plan.md
  DriftAction evaluateCorrection(
    SyncPayload payload,
    double currentLocalPositionSeconds, [
    int? currentTimestampMs,
  ]) {
    final int now = currentTimestampMs ?? _clockSync.synchronizedTimestampMs;
    return payload.evaluateCorrection(currentLocalPositionSeconds, now);
  }

  /// Returns recommended playback speed for micro-adjustments
  /// - Lagging behind -> 1.06x
  /// - Ahead -> 0.94x
  /// - In sync -> 1.0x
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
}
