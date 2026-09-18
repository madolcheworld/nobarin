import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Reusable modern frosted glassmorphic container with configurable blur,
/// translucent backgrounds, hairline borders, and optional neon accents.
class FrostedGlassBox extends StatelessWidget {
  final Widget? child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadiusGeometry borderRadius;
  final double blur;
  final Color? backgroundColor;
  final Gradient? backgroundGradient;
  final Color? borderColor;
  final Gradient? borderGradient;
  final double borderWidth;
  final List<BoxShadow>? boxShadow;
  final VoidCallback? onTap;
  final Clip clipBehavior;

  const FrostedGlassBox({
    super.key,
    this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.blur = 14.0,
    this.backgroundColor,
    this.backgroundGradient,
    this.borderColor,
    this.borderGradient,
    this.borderWidth = 1.0,
    this.boxShadow,
    this.onTap,
    this.clipBehavior = Clip.antiAlias,
  });

  /// Factory preset for interactive cards (e.g., room card)
  factory FrostedGlassBox.card({
    Key? key,
    required Widget child,
    EdgeInsetsGeometry? padding = const EdgeInsets.all(10),
    EdgeInsetsGeometry? margin,
    BorderRadiusGeometry borderRadius = const BorderRadius.all(Radius.circular(16)),
    bool isHighlighted = false,
    Color? highlightColor,
    VoidCallback? onTap,
  }) {
    final activeColor = highlightColor ?? AppColors.primaryNeon;
    return FrostedGlassBox(
      key: key,
      padding: padding,
      margin: margin,
      borderRadius: borderRadius,
      blur: 12.0,
      backgroundColor: isHighlighted
          ? activeColor.withValues(alpha: 0.12)
          : AppColors.glassFill,
      borderColor: isHighlighted
          ? activeColor.withValues(alpha: 0.45)
          : AppColors.glassBorder,
      borderWidth: isHighlighted ? 1.2 : 1.0,
      boxShadow: isHighlighted
          ? [
              BoxShadow(
                color: activeColor.withValues(alpha: 0.25),
                blurRadius: 16,
                spreadRadius: -2,
              ),
              ...AppColors.atmosphericCardShadow,
            ]
          : AppColors.atmosphericCardShadow,
      onTap: onTap,
      child: child,
    );
  }

  /// Factory preset for floating docks and player bars
  factory FrostedGlassBox.dock({
    Key? key,
    required Widget child,
    EdgeInsetsGeometry? padding =
        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    EdgeInsetsGeometry? margin,
    BorderRadiusGeometry borderRadius = const BorderRadius.all(Radius.circular(20)),
    double blur = 18.0,
  }) {
    return FrostedGlassBox(
      key: key,
      padding: padding,
      margin: margin,
      borderRadius: borderRadius,
      blur: blur,
      backgroundColor: AppColors.glassFillHeavy,
      borderGradient: AppColors.glassBorderGradient,
      borderWidth: 1.1,
      boxShadow: AppColors.glassDockShadow,
      child: child,
    );
  }

  /// Factory preset for chips and filter pills
  factory FrostedGlassBox.pill({
    Key? key,
    required Widget child,
    bool isSelected = false,
    Color? activeColor,
    EdgeInsetsGeometry? padding =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    VoidCallback? onTap,
  }) {
    final accent = activeColor ?? AppColors.primaryNeon;
    return FrostedGlassBox(
      key: key,
      padding: padding,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      blur: 10.0,
      backgroundColor: isSelected
          ? accent.withValues(alpha: 0.22)
          : AppColors.glassFillLight,
      borderColor: isSelected ? accent : AppColors.glassBorder,
      borderWidth: isSelected ? 1.3 : 0.9,
      boxShadow: isSelected
          ? [
              BoxShadow(
                color: accent.withValues(alpha: 0.28),
                blurRadius: 12,
                spreadRadius: -1,
              ),
            ]
          : null,
      onTap: onTap,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundGradient == null
            ? (backgroundColor ?? AppColors.glassFill)
            : null,
        gradient: backgroundGradient,
      ),
      child: child,
    );

    // Apply InkWell if interactive
    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius is BorderRadius
              ? (borderRadius as BorderRadius)
              : BorderRadius.circular(16),
          splashColor: AppColors.primaryNeonGlow,
          highlightColor: Colors.white.withValues(alpha: 0.05),
          child: content,
        ),
      );
    }

    final border = Border.all(
      color: borderColor ?? AppColors.glassBorder,
      width: borderWidth,
    );

    Widget glassWidget = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: clipBehavior,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: border,
            ),
            child: content,
          ),
        ),
      ),
    );

    return glassWidget;
  }
}
