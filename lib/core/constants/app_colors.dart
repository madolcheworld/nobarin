import 'package:flutter/material.dart';

class AppColors {
  // Atmospheric Void Backgrounds (Deep Cosmic Slate Void)
  static const Color background = Color(0xFF0A0D18); // Deep cosmic slate void
  static const Color surface = Color(0xFF0F1424); // Cosmic slate navy surface
  static const Color surfaceElevated = Color(0xFF151B2E); // Elevated cards & containers
  static const Color surfaceHighlight = Color(0xFF1E2640); // Active/hover states

  // Modern Neon Accents
  static const Color primaryNeon = Color(0xFF8B5CF6); // Electric Violet
  static const Color primaryNeonDark = Color(0xFF7C3AED); // Deep Violet for CTA
  static const Color primaryNeonLight = Color(0xFFA78BFA); // Soft Violet highlight
  static const Color primaryNeonGlow = Color(0x358B5CF6); // Soft violet aura
  static const Color secondaryNeon = Color(0xFF06B6D4); // Cyber Cyan
  static const Color secondaryNeonGlow = Color(0x3006B6D4); // Soft cyan aura
  static const Color accentPink = Color(0xFFF43F5E); // Hot Neon Pink
  static const Color accentPinkGlow = Color(0x30F43F5E);
  static const Color accentGreen = Color(0xFF10B981); // Emerald Green (Voice Active / Online)
  static const Color accentGreenGlow = Color(0x4010B981);
  static const Color accentYellow = Color(0xFFF59E0B); // Host Crown / Warning
  static const Color accentRed = Color(0xFFEF4444); // Error / Danger

  // Border & Dividers
  static const Color border = Color(0xFF1B2338);
  static const Color borderGlow = Color(0x408B5CF6);
  static const Color borderCyanGlow = Color(0x3006B6D4);
  static const Color divider = Color(0xFF182033);
  static const Color borderLight = Color(0x1AFFFFFF);

  // Frosted Glass Presets
  static final Color glassFill = const Color(0xFF121829).withValues(alpha: 0.70);
  static final Color glassFillHeavy = const Color(0xFF0F1424).withValues(alpha: 0.88);
  static final Color glassFillLight = Colors.white.withValues(alpha: 0.05);
  static final Color glassBorder = Colors.white.withValues(alpha: 0.11);
  static final Color glassBorderHighlight = Colors.white.withValues(alpha: 0.22);
  static final Color surfaceGlass = const Color(0xFF0F1424).withValues(alpha: 0.78);

  // Text (High Contrast & Comfortable Readability)
  static const Color textPrimary = Color(0xFFF8FAFC); // Crisp Off-White
  static const Color textSecondary = Color(0xFF94A3B8); // Slate 400
  static const Color textMuted = Color(0xFF64748B); // Slate 500

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyanGradient = LinearGradient(
    colors: [secondaryNeon, primaryNeon],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF141A2D), Color(0xFF0F1424)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient glassCardGradient = LinearGradient(
    colors: [Color(0x18FFFFFF), Color(0x06FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient glassBorderGradient = LinearGradient(
    colors: [Color(0x38FFFFFF), Color(0x0DFFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient neonBorderGradient = LinearGradient(
    colors: [primaryNeon, secondaryNeon],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF181530), Color(0xFF0D1222), Color(0xFF0A0D18)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient dockGradient = LinearGradient(
    colors: [Color(0xF012182B), Color(0xF00D1222)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Platform Brand Colors
  static const Color youtubeRed = Color(0xFFFF0000);
  static const Color googleDriveGreen = Color(0xFF0F9D58);
  static const Color dailymotionBlue = Color(0xFF0066DC);
  static const Color bstationBlue = Color(0xFF00A1D6);

  // Shimmer / Skeleton Loading
  static const Color shimmerBase = Color(0xFF10162A);
  static const Color shimmerHighlight = Color(0xFF1D2644);

  // Standardized Glow & Shadow Presets
  static final List<BoxShadow> neonVioletGlow = [
    BoxShadow(
      color: primaryNeon.withValues(alpha: 0.32),
      blurRadius: 18,
      spreadRadius: -2,
    ),
  ];

  static final List<BoxShadow> neonCyanGlow = [
    BoxShadow(
      color: secondaryNeon.withValues(alpha: 0.28),
      blurRadius: 16,
      spreadRadius: -2,
    ),
  ];

  static final List<BoxShadow> voiceActiveGlow = [
    BoxShadow(
      color: accentGreen.withValues(alpha: 0.50),
      blurRadius: 14,
      spreadRadius: 2,
    ),
  ];

  static final List<BoxShadow> atmosphericCardShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.45),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];

  static final List<BoxShadow> glassDockShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.50),
      blurRadius: 24,
      offset: const Offset(0, -4),
    ),
  ];
}
