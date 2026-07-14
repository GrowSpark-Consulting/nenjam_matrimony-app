import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

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
  static List<NmPreferenceRow> get defaults => const [
    NmPreferenceRow(label: 'Age Range', value: '26 - 32'),
    NmPreferenceRow(label: 'Height', value: '5\'4" +'),
    NmPreferenceRow(label: 'Education', value: 'Masters / PhD'),
    NmPreferenceRow(label: 'Location', value: 'Same city'),
  ];

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
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  'Partner Preferences',
                  style: AppTypography.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onEditTap != null)
                Semantics(
                  label: 'Edit partner preferences',
                  button: true,
                  child: InkWell(
                    onTap: onEditTap,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.edit_rounded,
                        size: 18,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.primary,
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
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          pref.value,
                          textAlign: TextAlign.end,
                          style: AppTypography.labelMedium.copyWith(
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Divider(
                    height: 1,
                    color: isDark
                        ? AppColors.dividerDark
                        : AppColors.dividerLight,
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
