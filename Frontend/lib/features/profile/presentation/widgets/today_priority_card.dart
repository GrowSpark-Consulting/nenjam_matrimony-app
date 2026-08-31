import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

/// A single priority action item shown inside Today's Priorities section.
///
/// Rendered as a white card with a coloured left-accent strip, an icon,
/// title, impact label and a trailing chevron.
class NmTodayPriorityCard extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String impactLabel;
  final VoidCallback? onTap;

  const NmTodayPriorityCard({
    super.key,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.impactLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : AppColors.cardLight,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
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
            border: Border(left: BorderSide(color: accentColor, width: 4)),
          ),
          child: Row(
            children: [
              // Icon container
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(icon, size: 22, color: accentColor),
              ),
              const SizedBox(width: AppSpacing.base),

              // Text block
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.labelLarge.copyWith(
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      impactLabel,
                      style: AppTypography.labelSmall.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // Chevron
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiaryLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section wrapper that holds a list of [NmTodayPriorityCard]s.
///
/// Produces the full "Today's Priorities" section header + items.
class NmTodayPrioritiesSection extends StatelessWidget {
  final List<NmPriorityItem> priorities;

  const NmTodayPrioritiesSection({super.key, required this.priorities});

  /// Default priorities used when no custom list is provided. Takes an
  /// [AppLocalizations] because the copy is translated, so the list can no
  /// longer be a compile-time constant.
  static List<NmPriorityItem> defaultPrioritiesFor(AppLocalizations l10n) => [
    NmPriorityItem(
      icon: Icons.family_restroom_rounded,
      accentColor: AppColors.secondary,
      title: l10n.profileAddFamilyDetails,
      impactLabel: l10n.profilePriorityTrustImpact,
    ),
    NmPriorityItem(
      icon: Icons.add_a_photo_rounded,
      accentColor: AppColors.primary,
      title: l10n.profileAddMorePhotos,
      impactLabel: l10n.profilePriorityVisibilityImpact,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).profileTodaysPriorities,
          style: AppTypography.titleMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        ...priorities.map(
          (p) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: NmTodayPriorityCard(
              icon: p.icon,
              accentColor: p.accentColor,
              title: p.title,
              impactLabel: p.impactLabel,
              onTap: p.onTap,
            ),
          ),
        ),
      ],
    );
  }
}

/// Public data holder for a single priority item.
class NmPriorityItem {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String impactLabel;
  final VoidCallback? onTap;

  const NmPriorityItem({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.impactLabel,
    this.onTap,
  });
}
