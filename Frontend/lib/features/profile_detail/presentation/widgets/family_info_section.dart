import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/family_info_entity.dart';
import '../../../../l10n/app_localizations.dart';

/// Father/mother, family type/values/status, and siblings — nothing in
/// the existing widget library models family background, so this is new.
class FamilyInfoSection extends StatelessWidget {
  final FamilyInfoEntity family;

  const FamilyInfoSection({super.key, required this.family});

  @override
  Widget build(BuildContext context) {
    const textSecondary = AppColors.textSecondaryLight;

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPaddingLarge,
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).profileDetailFamilyInfo,
            style: AppTypography.titleLarge,
          ),
          const SizedBox(height: AppSpacing.base),
          Wrap(
            spacing: AppSpacing.base,
            runSpacing: AppSpacing.base,
            children: [
              if (family.familyType.isNotEmpty)
                _Tile(
                  label: AppLocalizations.of(
                    context,
                  ).registrationFamilyTypeLabel,
                  value: family.familyType,
                ),
              if (family.familyValues.isNotEmpty)
                _Tile(
                  label: AppLocalizations.of(
                    context,
                  ).registrationFamilyValuesLabel,
                  value: family.familyValues,
                ),
              if (family.familyStatus.isNotEmpty)
                _Tile(
                  label: AppLocalizations.of(
                    context,
                  ).registrationFamilyStatusLabel,
                  value: family.familyStatus,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          const Divider(
            height: 1,
            color: AppColors.dividerLight,
          ),
          const SizedBox(height: AppSpacing.base),
          if (family.fatherName.isNotEmpty ||
              family.fatherOccupation.isNotEmpty)
            _PersonRow(
              icon: Icons.man_rounded,
              name: family.fatherName,
              occupation: family.fatherOccupation,
              textSecondary: textSecondary,
            ),
          if (family.motherName.isNotEmpty ||
              family.motherOccupation.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _PersonRow(
              icon: Icons.woman_rounded,
              name: family.motherName,
              occupation: family.motherOccupation,
              textSecondary: textSecondary,
            ),
          ],
          if (family.brothers > 0 || family.sisters > 0) ...[
            const SizedBox(height: AppSpacing.base),
            Row(
              children: [
                const Icon(
                  Icons.groups_rounded,
                  size: 20,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).profileDetailSiblingsLine(
                      AppLocalizations.of(
                        context,
                      ).profileDetailSiblingsBrothers(family.brothers),
                      AppLocalizations.of(
                        context,
                      ).profileDetailSiblingsSisters(family.sisters),
                    ),
                    style: AppTypography.bodyMedium.copyWith(
                      color: textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;

  const _Tile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textTertiaryLight,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final IconData icon;
  final String name;
  final String occupation;
  final Color textSecondary;

  const _PersonRow({
    required this.icon,
    required this.name,
    required this.occupation,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: AppSpacing.borderRadiusMd,
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (name.isNotEmpty) Text(name, style: AppTypography.labelLarge),
              if (occupation.isNotEmpty)
                Text(
                  occupation,
                  style: AppTypography.bodySmall.copyWith(color: textSecondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
