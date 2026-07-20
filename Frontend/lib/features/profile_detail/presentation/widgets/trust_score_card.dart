import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/trust_score_entity.dart';

/// Dark navy hero summary card shown directly under the section tabs —
/// a large gold ring with the overall trust percentage plus a short
/// credibility blurb. The itemized checklist lives further down the
/// page in [VerificationTrustSection]; this card is just the headline.
class TrustScoreCard extends StatelessWidget {
  final TrustScoreEntity trust;

  const TrustScoreCard({super.key, required this.trust});

  String get _credibilityLabel {
    final percent = trust.overallPercent;
    if (percent >= 80) return 'High credibility profile';
    if (percent >= 50) return 'Good credibility profile';
    return 'Building credibility';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: AppSpacing.borderRadiusXl2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trust Score',
                  style: AppTypography.titleLarge.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _credibilityLabel,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.accentGoldLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.base),
          SizedBox(
            height: 84,
            width: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 84,
                  width: 84,
                  child: CircularProgressIndicator(
                    value: trust.overallPercent / 100,
                    strokeWidth: 7,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    color: AppColors.accentGold,
                  ),
                ),
                Text(
                  '${trust.overallPercent}%',
                  style: AppTypography.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
