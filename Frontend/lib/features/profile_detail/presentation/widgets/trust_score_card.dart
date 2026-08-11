import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/trust_score_entity.dart';
import '../../../../l10n/app_localizations.dart';

/// Dark navy hero summary card shown directly under the section tabs —
/// a large gold ring with the overall trust percentage plus a short
/// credibility blurb. The itemized checklist lives further down the
/// page in [VerificationTrustSection]; this card is just the headline.
class TrustScoreCard extends StatelessWidget {
  final TrustScoreEntity trust;

  const TrustScoreCard({super.key, required this.trust});

  String _credibilityLabelOf(AppLocalizations l10n) {
    final percent = trust.overallPercent;
    if (percent >= 80) return l10n.trustScoreHighCredibility;
    if (percent >= 50) return l10n.trustScoreGoodCredibility;
    return l10n.trustScoreBuildingCredibility;
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
                  AppLocalizations.of(context).trustScoreTitle,
                  style: AppTypography.titleLarge.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _credibilityLabelOf(AppLocalizations.of(context)),
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
