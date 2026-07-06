import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';

/// Profile completion progress card.
class NmProfileCompletionCard extends StatelessWidget {
  final int percentage;
  final String nextStep;
  final VoidCallback? onTap;

  const NmProfileCompletionCard({
    super.key,
    required this.percentage,
    this.nextStep = 'Add profile photo',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: AppDecorations.card(isDark: isDark),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Complete Your Profile',
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$percentage%',
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: percentage / 100,
                minHeight: 8,
                backgroundColor: isDark
                    ? AppColors.surfaceVariantDark
                    : AppColors.surfaceVariantLight,
                color: percentage >= 80
                    ? AppColors.success
                    : AppColors.accentGold,
              ),
            ),
            const SizedBox(height: 12),

            // Next step
            Row(
              children: [
                const Icon(Icons.arrow_forward_rounded,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Next: $nextStep',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
