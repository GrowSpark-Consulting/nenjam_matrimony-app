import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/profile_detail_entity.dart';
import '../../../../l10n/app_localizations.dart';

/// Label/value row list: age, height, marital status, mother tongue,
/// matrimony ID, and distance (when known).
class BasicInformationSection extends StatelessWidget {
  final ProfileDetailEntity detail;

  const BasicInformationSection({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = detail.base;

    final rows = <(String, String)>[
      (l10n.fieldAge, l10n.profileDetailAgeYears(base.age)),
      if (base.height.isNotEmpty) (l10n.fieldHeight, base.height),
      if (detail.maritalStatus.isNotEmpty)
        (l10n.fieldMaritalStatus, detail.maritalStatus),
      if (detail.motherTongue.isNotEmpty)
        (l10n.fieldMotherTongue, detail.motherTongue),
      (l10n.fieldMatrimonyId, base.matrimonyId),
      if (base.distanceKm != null)
        (
          l10n.fieldDistance,
          '${base.distanceKm!.toStringAsFixed(0)} ${l10n.discoverKmAwaySuffix}',
        ),
    ];

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPaddingLarge,
      decoration: AppDecorations.card(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.registrationBasicInfoTitle, style: AppTypography.titleLarge),
          const SizedBox(height: AppSpacing.base),
          ...rows.asMap().entries.map((entry) {
            final isLast = entry.key == rows.length - 1;
            final (label, value) = entry.value;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          label,
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
                          value,
                          textAlign: TextAlign.end,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
