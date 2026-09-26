import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../utils/app_haptics.dart';

/// Vertical interactive card used inside [VideoSourceGrid] for selecting
/// a video platform or streaming source (YouTube, Bstation, Web Browser, etc.).
class VideoSourceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBackgroundColor;
  final Color accentColor;
  final String? badgeText;
  final VoidCallback onTap;

  const VideoSourceCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBackgroundColor,
    required this.accentColor,
    required this.onTap,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AppHaptics.selection();
          onTap();
        },
        borderRadius: BorderRadius.circular(18),
        splashColor: accentColor.withValues(alpha: 0.18),
        highlightColor: accentColor.withValues(alpha: 0.08),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accentColor.withValues(alpha: 0.20),
                AppColors.surfaceElevated,
                AppColors.surface,
              ],
              stops: const [0.0, 0.58, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.48),
              width: 1.25,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Row: Brand Icon Squircle + Optional Pill Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: iconBackgroundColor,
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [
                        BoxShadow(
                          color: iconBackgroundColor.withValues(alpha: 0.42),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        icon,
                        color: iconColor,
                        size: 22,
                      ),
                    ),
                  ),
                  if (badgeText != null)
                    Flexible(
                      child: Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.45),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          badgeText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: accentColor,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Bottom Section: Title + Subtitle + Harmonized Circular Action Pill
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.38),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 13,
                            color: accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                      height: 1.28,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Responsive 2-column (or 3-column on wide screens) grid layout for [VideoSourceCard]s.
/// Uses [IntrinsicHeight] per row so cards in the same row always match height cleanly.
class VideoSourceGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;

  const VideoSourceGrid({
    super.key,
    required this.children,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final int crossAxisCount = constraints.maxWidth >= 560 ? 3 : 2;
        final List<Widget> rows = [];

        for (int i = 0; i < children.length; i += crossAxisCount) {
          final int end = (i + crossAxisCount < children.length)
              ? i + crossAxisCount
              : children.length;
          final rowItems = children.sublist(i, end);

          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int j = 0; j < crossAxisCount; j++) ...[
                    if (j > 0) SizedBox(width: spacing),
                    Expanded(
                      child: j < rowItems.length
                          ? rowItems[j]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );

          if (end < children.length) {
            rows.add(SizedBox(height: spacing));
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

/// Wide featured card used at the bottom of the grid for live/special actions
/// such as "Mirror Layar / Bagikan Layar".
class VideoSourceFeatureCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBackgroundColor;
  final Color accentColor;
  final String? badgeText;
  final IconData trailingIcon;
  final VoidCallback onTap;

  const VideoSourceFeatureCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBackgroundColor,
    required this.accentColor,
    required this.onTap,
    this.badgeText,
    this.trailingIcon = Icons.arrow_forward_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AppHaptics.selection();
          onTap();
        },
        borderRadius: BorderRadius.circular(18),
        splashColor: accentColor.withValues(alpha: 0.18),
        highlightColor: accentColor.withValues(alpha: 0.08),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accentColor.withValues(alpha: 0.20),
                AppColors.surfaceElevated,
                AppColors.surface,
              ],
              stops: const [0.0, 0.65, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.5),
              width: 1.25,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.26),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBackgroundColor,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(
                      color: iconBackgroundColor.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (badgeText != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: accentColor.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Text(
                              badgeText!,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: accentColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Icon(
                    trailingIcon,
                    size: 15,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
