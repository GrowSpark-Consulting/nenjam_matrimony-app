import 'package:flutter/material.dart';

import '../../../features/astro/domain/models/compatibility_result.dart';
import '../../constants/app_spacing.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';

/// Circular compatibility score + a card per contributing factor (e.g.
/// Nakshatra Match, Rasi Match, Dosham Match, Personality Match). Used on
/// the Horoscope Matching page to preview what a compatibility result
/// looks like.
class CompatibilityResultWidget extends StatelessWidget {
  final CompatibilityResult result;

  const CompatibilityResultWidget({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: AppSpacing.cardPaddingLarge,
          decoration: AppDecorations.premiumCard,
          child: Column(
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: result.score / 100,
                      strokeWidth: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.accentLight,
                      ),
                    ),
                    Text(
                      '${result.score}%',
                      style: AppTypography.titleLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                result.matchLabel,
                style: AppTypography.titleMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (result.factors.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.base),
          ...result.factors.map(
            (factor) => Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: AppSpacing.cardPaddingCompact,
              decoration: AppDecorations.card(),
              child: Row(
                children: [
                  Expanded(
                    child: Text(factor.label, style: AppTypography.bodyMedium),
                  ),
                  Text(
                    '${factor.score}/${factor.maxScore}',
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.scoreAstrology,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
