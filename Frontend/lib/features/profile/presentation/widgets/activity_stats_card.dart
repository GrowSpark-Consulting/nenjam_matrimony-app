import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

/// Recent Activity stats card — 2-column grid showing Interests Received
/// and Matches with count-up animation.
class NmActivityStatsCard extends StatelessWidget {
  final int interestsReceived;
  final int matches;
  final VoidCallback? onInterestsTap;
  final VoidCallback? onMatchesTap;

  const NmActivityStatsCard({
    super.key,
    this.interestsReceived = 24,
    this.matches = 8,
    this.onInterestsTap,
    this.onMatchesTap,
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
          Text(AppLocalizations.of(context).profileTodaysActivity, style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.base),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  value: interestsReceived,
                  label: AppLocalizations.of(context).fieldInterests,
                  color: AppColors.liked,
                  isDark: isDark,
                  onTap: onInterestsTap,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatTile(
                  value: matches,
                  label: AppLocalizations.of(context).profileMatchesLabel,
                  color: AppColors.accentGold,
                  isDark: isDark,
                  onTap: onMatchesTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback? onTap;

  const _StatTile({
    required this.value,
    required this.label,
    required this.color,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.base,
          horizontal: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: value),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (_, val, __) => Text(
                '$val',
                style: AppTypography.headlineSmall.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: AppTypography.labelSmall.copyWith(
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiaryLight,
                letterSpacing: 0.8,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
