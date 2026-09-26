import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../utils/app_haptics.dart';

/// Tombol utama (Primary CTA) standar Nobarin dengan gaya Atmospheric Dark & Neon.
/// Menggunakan [AppColors.primaryGradient] (atau gradient kustom) dan [AppColors.neonVioletGlow]
/// saat aktif, serta transisi halus untuk state disabled dan loading.
class NobarinPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final double height;
  final double borderRadius;
  final Gradient? gradient;
  final List<BoxShadow>? glowShadows;
  final double fontSize;
  final EdgeInsetsGeometry? padding;

  const NobarinPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.height = 50,
    this.borderRadius = 14,
    this.gradient,
    this.glowShadows,
    this.fontSize = 14,
    this.padding,
  });

  bool get _isEnabled => onPressed != null && !isLoading;

  @override
  Widget build(BuildContext context) {
    final activeGradient = gradient ?? AppColors.primaryGradient;
    final activeShadows = glowShadows ?? AppColors.neonVioletGlow;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: height,
      decoration: BoxDecoration(
        gradient: _isEnabled ? activeGradient : null,
        color: _isEnabled ? null : AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: _isEnabled
              ? AppColors.primaryNeonLight.withValues(alpha: 0.35)
              : AppColors.border,
          width: 1,
        ),
        boxShadow: _isEnabled ? activeShadows : const [],
      ),
      child: ElevatedButton(
        onPressed: _isEnabled
            ? () {
                AppHaptics.selection();
                onPressed?.call();
              }
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledForegroundColor: AppColors.textMuted,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          minimumSize: Size(0, height),
          padding:
              padding ?? const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: fontSize + 4,
                      color: _isEnabled ? Colors.white : AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: fontSize,
                        letterSpacing: 0.2,
                        color: _isEnabled ? Colors.white : AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Tombol sekunder (Secondary / Outlined) standar Nobarin.
/// Mendukung dua varian:
/// - Default (`isNeutral: false`): Aksen neon (`AppColors.primaryNeonLight`) untuk aksi sekunder utama.
/// - Neutral (`isNeutral: true`): Aksen netral (`AppColors.surfaceHighlight` & `AppColors.glassBorder`) untuk aksi Batal / Kembali.
class NobarinSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isNeutral;
  final double height;
  final double borderRadius;
  final Color? accentColor;
  final double fontSize;
  final EdgeInsetsGeometry? padding;

  const NobarinSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isNeutral = false,
    this.height = 48,
    this.borderRadius = 14,
    this.accentColor,
    this.fontSize = 13.5,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = onPressed != null;
    final Color effectiveAccent = accentColor ?? AppColors.primaryNeonLight;

    final Color bgColor = !isEnabled
        ? AppColors.surfaceHighlight.withValues(alpha: 0.3)
        : isNeutral
            ? AppColors.surfaceHighlight.withValues(alpha: 0.55)
            : effectiveAccent.withValues(alpha: 0.12);

    final Color borderColor = !isEnabled
        ? AppColors.border
        : isNeutral
            ? AppColors.glassBorder
            : effectiveAccent.withValues(alpha: 0.55);

    final Color fgColor = !isEnabled
        ? AppColors.textMuted
        : isNeutral
            ? AppColors.textSecondary
            : Colors.white;

    final Color iconColor = !isEnabled
        ? AppColors.textMuted
        : isNeutral
            ? AppColors.textSecondary
            : effectiveAccent;

    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: isEnabled
            ? () {
                AppHaptics.selection();
                onPressed?.call();
              }
            : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: fgColor,
          disabledForegroundColor: AppColors.textMuted,
          backgroundColor: bgColor,
          minimumSize: Size(0, height),
          padding:
              padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          side: BorderSide(
            color: borderColor,
            width: isNeutral ? 1.0 : 1.25,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: fontSize + 4,
                color: iconColor,
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: fontSize,
                  letterSpacing: 0.15,
                  color: fgColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tombol ikon kotak-membulat seragam untuk navigasi header modal/sheet (seperti Back atau Close).
class NobarinModalIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? iconColor;

  const NobarinModalIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 36,
    this.iconSize = 18,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: AppColors.surfaceHighlight.withValues(alpha: 0.75),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(color: AppColors.glassBorder, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed != null
            ? () {
                AppHaptics.selection();
                onPressed?.call();
              }
            : null,
        borderRadius: BorderRadius.circular(11),
        splashColor: AppColors.primaryNeon.withValues(alpha: 0.18),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: iconSize,
            color: iconColor ?? AppColors.textSecondary,
          ),
        ),
      ),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(
        message: tooltip!,
        child: button,
      );
    }
    return button;
  }
}

/// Tombol chip/pill kecil untuk aksi inline seperti "Ganti" pada kartu ringkasan sumber video.
class NobarinPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? accentColor;

  const NobarinPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppColors.primaryNeonLight;
    return Material(
      color: color.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: 0.38), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed != null
            ? () {
                AppHaptics.selection();
                onPressed?.call();
              }
            : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
