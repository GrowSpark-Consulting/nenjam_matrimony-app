import 'package:flutter/material.dart';

import '../../../../core/animations/app_animations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';

/// Small, non-intrusive helper tip card shown once per wizard step (e.g.
/// "Your age is only used to improve compatibility."). Informative, not
/// a validation message — purely decorative copy.
class RegistrationHelperTip extends StatelessWidget {
  final String text;

  const RegistrationHelperTip({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return AppAnimations.fade(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: AppDecorations.cardSubtle(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.lightbulb_outline_rounded,
              size: 18,
              color: AppColors.secondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ),
          ],
        ),
      ),
      delay: const Duration(milliseconds: 150),
    );
  }
}
