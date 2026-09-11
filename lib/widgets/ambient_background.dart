import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Ambient subtle glowing background for CompanAI (White + Yellow Theme)
class AmbientBackground extends StatelessWidget {
  final Widget child;
  final bool showGlows;

  const AmbientBackground({
    super.key,
    required this.child,
    this.showGlows = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // Background Base Color
        Positioned.fill(
          child: Container(
            color: isDark
                ? AppColors.darkBackground
                : AppColors.lightBackground,
          ),
        ),

        // Glowing Orbs
        if (showGlows) ...[
          // Top Left Electric Cyber Yellow Aura
          Positioned(
            top: -120,
            left: -80,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isDark ? AppColors.primary : AppColors.primaryLight)
                        .withValues(alpha: isDark ? 0.20 : 0.08),
                    (isDark ? AppColors.primary : AppColors.primaryLight)
                        .withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Right Pure White / Warm Amber Aura
          Positioned(
            bottom: 20,
            right: -100,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isDark ? Colors.white : AppColors.accentGold)
                        .withValues(alpha: isDark ? 0.10 : 0.06),
                    (isDark ? Colors.white : AppColors.accentGold)
                        .withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          // Backdrop Blur Layer to smoothly diffuse orbs
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
              child: const SizedBox.expand(),
            ),
          ),
        ],

        // Content
        Positioned.fill(child: child),
      ],
    );
  }
}
