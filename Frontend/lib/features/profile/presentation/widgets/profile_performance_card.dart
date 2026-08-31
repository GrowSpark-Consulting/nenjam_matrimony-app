import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/indicators/nm_score_ring.dart';
import '../../../../l10n/app_localizations.dart';

/// Profile Performance card — 3 circular progress gauges:
/// Strength, Visibility, and Response time.
class NmProfilePerformanceCard extends StatelessWidget {
  final int strengthPct;
  final int visibilityPct;
  final String responseTime;

  const NmProfilePerformanceCard({
    super.key,
    this.strengthPct = 82,
    this.visibilityPct = 95,
    this.responseTime = '12h',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).profilePerformanceTitle,
            style: AppTypography.titleMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _GaugeWidget(
                  label: AppLocalizations.of(
                    context,
                  ).profilePerformanceStrength,
                  value: strengthPct / 100,
                  displayText: '$strengthPct%',
                  color: AppColors.faceVerificationGreen,
                ),
              ),
              Expanded(
                child: _GaugeWidget(
                  label: AppLocalizations.of(
                    context,
                  ).profilePerformanceVisibility,
                  value: visibilityPct / 100,
                  displayText: '$visibilityPct%',
                  color: AppColors.secondary,
                ),
              ),
              Expanded(
                child: _GaugeWidget(
                  label: AppLocalizations.of(
                    context,
                  ).profilePerformanceResponse,
                  value: 0.5,
                  displayText: responseTime,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugeWidget extends StatelessWidget {
  final String label;
  final double value;
  final String displayText;
  final Color color;

  const _GaugeWidget({
    required this.label,
    required this.value,
    required this.displayText,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        NmScoreRing(
          value: value,
          displayText: displayText,
          color: color,
          textColor: AppColors.textPrimaryLight,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          duration: const Duration(milliseconds: 1200),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }
}
