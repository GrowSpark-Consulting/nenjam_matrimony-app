import 'package:flutter/material.dart';

import '../../constants/app_spacing.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';

/// Icon + title + subtitle + chevron row used for "enrich your profile"
/// style navigation cards. Extracted from the Profile Intelligence hub so
/// the Nenjam Relationship Intelligence hub can reuse the same visual
/// without a second near-identical implementation.
class NmIntelligenceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool locked;

  const NmIntelligenceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      borderRadius: AppSpacing.borderRadiusXl,
      child: InkWell(
        borderRadius: AppSpacing.borderRadiusXl,
        onTap: onTap,
        child: Opacity(
          opacity: locked ? 0.6 : 1,
          child: Container(
            width: double.infinity,
            padding: AppSpacing.cardPaddingLarge,
            decoration: AppDecorations.card(isDark: isDark),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.accentGold.withValues(alpha: 0.12),
                    borderRadius: AppSpacing.borderRadiusMd,
                  ),
                  child: Icon(icon, color: AppColors.accentGold),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.bodyLarge.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.labelSmall.copyWith(
                          color: isDark
                              ? AppColors.textTertiaryDark
                              : AppColors.textTertiaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  locked
                      ? Icons.lock_outline_rounded
                      : Icons.chevron_right_rounded,
                  color: isDark
                      ? AppColors.textTertiaryDark
                      : AppColors.textTertiaryLight,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
