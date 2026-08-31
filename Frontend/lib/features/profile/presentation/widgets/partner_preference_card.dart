import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

/// A single preference row (label + value).
class NmPreferenceRow {
  final String label;
  final String value;

  const NmPreferenceRow({required this.label, required this.value});
}

/// Partner Preferences card — key-value list with edit button.
///
/// Shows Age Range, Height, Education, Location, etc.
class NmPartnerPreferenceCard extends StatelessWidget {
  final List<NmPreferenceRow> preferences;
  final VoidCallback? onEditTap;

  const NmPartnerPreferenceCard({
    super.key,
    required this.preferences,
    this.onEditTap,
  });

  /// Default placeholder preferences.
  /// Placeholder rows. Labels are localized (so no longer `const`); the
  /// sample values stay as-is — illustrative data, not UI copy.
  static List<NmPreferenceRow> defaultsFor(AppLocalizations l10n) => [
    NmPreferenceRow(label: l10n.fieldAgeRange, value: '26 - 32'),
    NmPreferenceRow(label: l10n.fieldHeight, value: '5\'4" +'),
    NmPreferenceRow(label: l10n.fieldEducation, value: 'Masters / PhD'),
    NmPreferenceRow(label: l10n.fieldLocation, value: 'Same city'),
  ];

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
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context).partnerPrefPageTitle,
                  style: AppTypography.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onEditTap != null)
                Semantics(
                  label: AppLocalizations.of(context).registrationEditPartnerPrefButton,
                  button: true,
                  child: InkWell(
                    onTap: onEditTap,
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.edit_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Rows
          ...preferences.asMap().entries.map((entry) {
            final isLast = entry.key == preferences.length - 1;
            final pref = entry.value;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          pref.label,
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.textSecondaryLight,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          pref.value,
                          textAlign: TextAlign.end,
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.textPrimaryLight,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  const Divider(
                    height: 1,
                    color: AppColors.dividerLight,
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
