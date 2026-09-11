import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum AppBadgeStatus { success, warning, error, info, neutral }

/// Modern status badge with color coding and indicator icon/dot
class AppStatusBadge extends StatelessWidget {
  final String label;
  final AppBadgeStatus status;
  final IconData? icon;
  final bool showDot;

  const AppStatusBadge({
    super.key,
    required this.label,
    this.status = AppBadgeStatus.neutral,
    this.icon,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    final (textColor, bgColor, borderColor) = switch (status) {
      AppBadgeStatus.success => (
          AppColors.success,
          AppColors.successContainer,
          AppColors.successBorder,
        ),
      AppBadgeStatus.warning => (
          AppColors.warning,
          AppColors.warningContainer,
          AppColors.warningBorder,
        ),
      AppBadgeStatus.error => (
          AppColors.error,
          AppColors.errorContainer,
          AppColors.errorBorder,
        ),
      AppBadgeStatus.info => (
          AppColors.info,
          AppColors.infoContainer,
          AppColors.infoBorder,
        ),
      AppBadgeStatus.neutral => (
          AppColors.darkTextSecondary,
          AppColors.darkSurfaceHighlight.withValues(alpha: 0.5),
          AppColors.darkBorder,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: textColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 12, color: textColor),
            const SizedBox(width: 5),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: textColor,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
