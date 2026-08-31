import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// One-line encouragement caption shown under the journey header. Keyed by
/// [stepIndex] so it fades in fresh on every step change. The caller
/// resolves the actual text via [motivationCaption] — this widget is purely
/// presentational.
class RegistrationMotivationCaption extends StatelessWidget {
  final int stepIndex;
  final String caption;

  const RegistrationMotivationCaption({
    super.key,
    required this.stepIndex,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Padding(
        key: ValueKey<int>(stepIndex),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          caption,
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(
            fontStyle: FontStyle.italic,
            color: AppColors.textSecondaryLight,
          ),
        ),
      ),
    );
  }
}
