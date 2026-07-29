import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/indicators/nm_score_ring.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl2),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : [
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
          Text('Profile Performance', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _GaugeWidget(
                  label: 'Strength',
                  value: strengthPct / 100,
                  displayText: '$strengthPct%',
                  color: AppColors.faceVerificationGreen,
                  isDark: isDark,
                ),
              ),
              Expanded(
                child: _GaugeWidget(
                  label: 'Visibility',
                  value: visibilityPct / 100,
                  displayText: '$visibilityPct%',
                  color: AppColors.accentGold,
                  isDark: isDark,
                ),
              ),
              Expanded(
                child: _GaugeWidget(
                  label: 'Response',
                  value: 0.5,
                  displayText: responseTime,
                  color: AppColors.primary,
                  isDark: isDark,
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
  final bool isDark;

  const _GaugeWidget({
    required this.label,
    required this.value,
    required this.displayText,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        NmScoreRing(
          value: value,
          displayText: displayText,
          color: color,
          textColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          duration: const Duration(milliseconds: 1200),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }
}
