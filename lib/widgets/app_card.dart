import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Reusable polished card with consistent styling and micro-interaction
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final bool elevated;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16.0),
    this.margin,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = AppRadii.lg,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = backgroundColor ??
        (elevated
            ? (isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurface)
            : (isDark ? AppColors.darkSurface : AppColors.lightSurface));

    final border = borderColor ??
        (isDark ? AppColors.darkBorder : AppColors.lightBorder);

    final decoration = BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: border, width: 1.2),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.03),
          blurRadius: elevated ? 16 : 8,
          offset: Offset(0, elevated ? 6 : 2),
        ),
      ],
    );

    if (onTap != null) {
      return Container(
        margin: margin,
        decoration: decoration,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(borderRadius),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(borderRadius),
            child: Padding(
              padding: padding,
              child: child,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: margin,
      decoration: decoration,
      padding: padding,
      child: child,
    );
  }
}
