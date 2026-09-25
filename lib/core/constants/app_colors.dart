import 'package:flutter/material.dart';

class AppColors {
  // Atmospheric Void Backgrounds (Deep Cosmic Slate Void)
  static const Color background = Color(0xFF0A0D18); // Deep cosmic slate void
  static const Color surface = Color(0xFF0F1424); // Cosmic slate navy surface
  static const Color surfaceElevated = Color(0xFF151B2E); // Elevated cards & containers
  static const Color surfaceHighlight = Color(0xFF1E2640); // Active/hover states
  static const Color chatBubbleSelf = Color(0xFF2D1F4E); // Self message bubble tint

  // Modern Neon Accents (Tuned for High Contrast on Dark Surfaces)
  static const Color primaryNeon = Color(0xFF9B6BFF); // Vibrant Electric Violet
  static const Color primaryNeonDark = Color(0xFF7C3AED); // Deep Violet for CTA fill
  static const Color primaryNeonLight = Color(0xFFC4B5FD); // Crisp Violet 300 for high-contrast text
  static const Color primaryNeonGlow = Color(0x389B6BFF); // Soft violet aura
  static const Color secondaryNeon = Color(0xFF22D3EE); // Bright Cyber Cyan (8.3:1 contrast)
  static const Color accentPink = Color(0xFFF43F5E); // Hot Neon Pink
  static const Color accentGreen = Color(0xFF34D399); // Vibrant Emerald Green (8.6:1 contrast)
  static const Color accentYellow = Color(0xFFFBBF24); // Warm Gold Amber (9.0:1 contrast)
  static const Color accentRed = Color(0xFFFF6B6B); // High-legibility Coral Red (5.8:1 contrast)

  // Border & Dividers
  static const Color border = Color(0xFF25304D); // Crisp slate border
  static const Color borderGlow = Color(0x4D9B6BFF);
  static const Color divider = Color(0xFF1F2942);
  static const Color borderLight = Color(0x22FFFFFF);

  // Frosted Glass Presets
  static final Color glassFill = const Color(0xFF121829).withValues(alpha: 0.78);
  static final Color glassFillHeavy = const Color(0xFF0F1424).withValues(alpha: 0.92);
  static final Color glassFillLight = Colors.white.withValues(alpha: 0.06);
  static final Color glassBorder = Colors.white.withValues(alpha: 0.14);
  static final Color glassBorderHighlight = Colors.white.withValues(alpha: 0.26);

  // Text (WCAG AA/AAA High Contrast & Comfortable Readability)
  static const Color textPrimary = Color(0xFFFFFFFF); // Pure Crisp White (19.2:1)
  static const Color textSecondary = Color(0xFFCBD5E1); // Slate 300 (11.4:1)
  static const Color textMuted = Color(0xFF94A3B8); // Slate 400 (6.1:1 - legible even at 10-12px)

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

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF181530), Color(0xFF0D1222), Color(0xFF0A0D18)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient comboMegaGradient = LinearGradient(
    colors: [accentPink, accentYellow],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient comboSuperGradient = LinearGradient(
    colors: [accentRed, accentYellow],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Platform & Source Brand Colors (Optimized for Dark UI Legibility)
  static const Color youtubeRed = Color(0xFFFF4E45);
  static const Color dailymotionBlue = Color(0xFF3B9EFF);
  static const Color bstationBlue = Color(0xFF26C6FA);
  static const Color p2pPurple = Color(0xFFA78BFA);

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
}
