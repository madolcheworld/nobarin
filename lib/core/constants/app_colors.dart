import 'package:flutter/material.dart';

class AppColors {
  // Atmospheric Void Backgrounds (Deep Cosmic Obsidian)
  static const Color background = Color(0xFF080912); // Deep cosmic void
  static const Color surface = Color(0xFF0F1221); // Midnight indigo surface
  static const Color surfaceElevated = Color(0xFF161B30); // Elevated cards & modals
  static const Color surfaceHighlight = Color(0xFF1F2642); // Active/hover states

  // Neon Rave Accents (Harmonized)
  static const Color primaryNeon = Color(0xFFA855F7); // Electric Violet / Neon Purple
  static const Color primaryNeonDark = Color(0xFF9333EA); // Rich Violet for primary CTAs
  static const Color primaryNeonGlow = Color(0x40A855F7); // Soft glow
  static const Color secondaryNeon = Color(0xFF06B6D4); // Cyber Cyan
  static const Color secondaryNeonGlow = Color(0x3306B6D4);
  static const Color accentPink = Color(0xFFF43F5E); // Hot Rave Pink
  static const Color accentPinkGlow = Color(0x33F43F5E);
  static const Color accentGreen = Color(0xFF10B981); // Emerald Green (Voice Active / Online)
  static const Color accentGreenGlow = Color(0x4010B981);
  static const Color accentYellow = Color(0xFFF59E0B); // Host Crown / Warning
  static const Color accentRed = Color(0xFFEF4444); // Error / Danger

  // Border & Dividers
  static const Color border = Color(0xFF1E253E);
  static const Color borderGlow = Color(0x44A855F7);
  static const Color borderCyanGlow = Color(0x3306B6D4);
  static const Color divider = Color(0xFF181D33);

  // Text (High Contrast & Comfortable Readability)
  static const Color textPrimary = Color(0xFFF8FAFC); // Crisp Off-White
  static const Color textSecondary = Color(0xFF94A3B8); // Slate 400
  static const Color textMuted = Color(0xFF64748B); // Slate 500

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF9333EA), Color(0xFFEC4899)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyanGradient = LinearGradient(
    colors: [secondaryNeon, primaryNeon],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF12162A), Color(0xFF0D101E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF18112E), Color(0xFF0B1124), Color(0xFF080912)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Glass & Elevated
  static final Color surfaceGlass = const Color(0xFF0F1221).withValues(alpha: 0.75);
  static const Color borderLight = Color(0x1FFFFFFF);

  // Platform Brand Colors
  static const Color youtubeRed = Color(0xFFFF0000);
  static const Color googleDriveGreen = Color(0xFF0F9D58);
  static const Color dailymotionBlue = Color(0xFF0066DC);
  static const Color bstationBlue = Color(0xFF00A1D6);

  // Shimmer / Skeleton Loading
  static const Color shimmerBase = Color(0xFF111528);
  static const Color shimmerHighlight = Color(0xFF1D2440);

  // Standardized Glow & Shadow Presets
  static final List<BoxShadow> neonVioletGlow = [
    BoxShadow(
      color: primaryNeon.withValues(alpha: 0.35),
      blurRadius: 18,
      spreadRadius: -2,
    ),
  ];

  static final List<BoxShadow> neonCyanGlow = [
    BoxShadow(
      color: secondaryNeon.withValues(alpha: 0.3),
      blurRadius: 16,
      spreadRadius: -2,
    ),
  ];

  static final List<BoxShadow> voiceActiveGlow = [
    BoxShadow(
      color: accentGreen.withValues(alpha: 0.5),
      blurRadius: 14,
      spreadRadius: 2,
    ),
  ];

  static final List<BoxShadow> atmosphericCardShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.55),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];
}
