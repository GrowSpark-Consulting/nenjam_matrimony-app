import 'package:flutter/material.dart';

import '../../../features/psychology/domain/models/personality_result.dart';
import '../../constants/app_spacing.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';

/// Displays OCEAN Big-Five personality quiz status. When [result.completed]
/// is false and [onTakeQuizTap] is provided, shows a "take the quiz" CTA.
/// When completed, always shows the trait bars — used both right after quiz
/// submission (result screen) and read-only elsewhere (`onTakeQuizTap: null`
/// hides the CTA/retake affordance).
class PsychologySection extends StatelessWidget {
  final PersonalityResult result;
  final VoidCallback? onTakeQuizTap;

  const PsychologySection({
    super.key,
    required this.result,
    this.onTakeQuizTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!result.completed) {
      if (onTakeQuizTap == null) return const SizedBox.shrink();
      return GestureDetector(
        onTap: onTakeQuizTap,
        child: Container(
          width: double.infinity,
          padding: AppSpacing.cardPaddingLarge,
          decoration: AppDecorations.card(isDark: isDark),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: AppSpacing.borderRadiusMd,
                ),
                child: const Icon(Icons.psychology_alt_rounded,
                    color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Discover your personality',
                        style: AppTypography.bodyMedium
                            .copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('3-minute quiz · improves match quality',
                        style: AppTypography.labelSmall.copyWith(
                          color: isDark
                              ? AppColors.textTertiaryDark
                              : AppColors.textTertiaryLight,
                        )),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.accentGold),
            ],
          ),
        ),
      );
    }

    final traits = <String, int>{
      'Openness': result.openness,
      'Conscientiousness': result.conscientiousness,
      'Extraversion': result.extraversion,
      'Agreeableness': result.agreeableness,
      'Emotional Balance': result.emotionalBalance,
    };

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPaddingLarge,
      decoration: AppDecorations.card(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_alt_rounded,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Text('Personality Profile', style: AppTypography.titleSmall),
              const Spacer(),
              if (onTakeQuizTap != null)
                TextButton(
                  onPressed: onTakeQuizTap,
                  child: const Text('Retake'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ...traits.entries.map((entry) {
            final value = entry.value.clamp(0, 100);
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(entry.key, style: AppTypography.labelMedium),
                      Text('$value%', style: AppTypography.labelMedium),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: AppSpacing.borderRadiusFull,
                    child: LinearProgressIndicator(
                      value: value / 100,
                      minHeight: 6,
                      backgroundColor: isDark
                          ? AppColors.surfaceVariantDark
                          : AppColors.surfaceVariantLight,
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.accentGold),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
