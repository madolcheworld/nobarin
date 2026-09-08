import 'package:flutter/material.dart';

class AppColors {
  // Backgrounds
  static const Color background = Color(0xFF0B0D17);
  static const Color surface = Color(0xFF141829);
  static const Color surfaceElevated = Color(0xFF1D233A);
  static const Color surfaceHighlight = Color(0xFF28304F);

  // Neon Rave Accents
  static const Color primaryNeon = Color(0xFFA855F7); // Neon Purple
  static const Color primaryNeonGlow = Color(0x66A855F7);
  static const Color secondaryNeon = Color(0xFF06B6D4); // Neon Cyan
  static const Color accentPink = Color(0xFFEC4899); // Neon Pink
  static const Color accentGreen = Color(0xFF10B981); // Neon Green (Voice Active)
  static const Color accentYellow = Color(0xFFF59E0B); // Host Crown / Warning
  static const Color accentRed = Color(0xFFEF4444); // Error / Danger

  // Border & Dividers
  static const Color border = Color(0xFF2E3856);
  static const Color borderGlow = Color(0x44A855F7);
  static const Color divider = Color(0xFF232A42);

  // Text
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryNeon, accentPink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
