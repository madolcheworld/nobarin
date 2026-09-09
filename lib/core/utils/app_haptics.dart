import 'package:flutter/services.dart';

/// Centralized utility for tactile micro-interactions (haptic feedback).
class AppHaptics {
  /// Subtle tap for button presses, tab switches, and chip filters.
  static void light() {
    HapticFeedback.lightImpact();
  }

  /// Click feel for item selections (avatars, reactions, dropdowns).
  static void selection() {
    HapticFeedback.selectionClick();
  }

  /// Medium feedback for successful actions (send message, create room, toggle mic).
  static void medium() {
    HapticFeedback.mediumImpact();
  }

  /// Strong alert feedback for errors, warnings, or destructive actions.
  static void heavy() {
    HapticFeedback.heavyImpact();
  }
}
