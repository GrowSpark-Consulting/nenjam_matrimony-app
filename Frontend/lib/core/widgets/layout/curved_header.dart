import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_gradients.dart';
import '../../theme/app_typography.dart';

/// Curved brand header.
///
/// A deep plum panel with an elliptical bottom curvature, a centred accent
/// badge, title, and subtitle.
class NmCurvedHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData badgeIcon;
  final Widget? badgeChild;
  final double minHeight;

  const NmCurvedHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.badgeIcon = Icons.favorite_rounded,
    this.badgeChild,
    this.minHeight = 270,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.elliptical(screenWidth, 80),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Accent circular badge
              Container(
                width: 56,
                height: 56,
                // Gradient fill plus a translucent white ring: a flat
                // magenta disc on the plum panel is barely over 1.5:1 and
                // reads as a smudge rather than a badge.
                decoration: BoxDecoration(
                  gradient: AppGradients.match,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.secondary.withValues(alpha: 0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child:
                      badgeChild ??
                      Icon(badgeIcon, size: 28, color: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              // Title
              Text(
                title,
                style: AppTypography.headlineLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 30,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              // Subtitle
              Text(
                subtitle,
                style: AppTypography.bodyMedium.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
