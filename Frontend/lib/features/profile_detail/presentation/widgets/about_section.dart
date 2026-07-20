import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/chips/info_chip.dart';
import '../../domain/entities/profile_detail_entity.dart';

/// Bio paragraph + a 4-tile stat grid (Profession / Education / Height /
/// Religion) + an interests chip cloud + a short core-values list —
/// mirrors the design reference's bento "About" card.
class AboutSection extends StatelessWidget {
  final ProfileDetailEntity detail;

  const AboutSection({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = detail.base;
    final textSecondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPaddingLarge,
      decoration: AppDecorations.card(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('About', style: AppTypography.titleLarge),
          if (detail.bio != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              detail.bio!,
              style: AppTypography.bodyMedium.copyWith(
                color: textSecondary,
                height: 1.6,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.base),
          Container(
            padding: const EdgeInsets.only(top: AppSpacing.base),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? AppColors.dividerDark
                      : AppColors.dividerLight,
                ),
              ),
            ),
            child: Wrap(
              runSpacing: AppSpacing.base,
              children: [
                _StatTile(label: 'Profession', value: base.profession),
                _StatTile(label: 'Education', value: base.education),
                _StatTile(label: 'Height', value: base.height),
                _StatTile(
                  label: 'Religion',
                  value: [
                    base.religion,
                    base.caste,
                  ].where((s) => s.isNotEmpty).join(' · '),
                ),
              ],
            ),
          ),
          if (detail.interests.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.base),
            Text('Interests', style: AppTypography.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final interest in detail.interests)
                  NmInfoChip.interest(label: interest),
              ],
            ),
          ],
          if (detail.coreValues.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.base),
            Text('Core Values', style: AppTypography.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            ...detail.coreValues.map(
              (value) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: AppColors.accentGold,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(value, style: AppTypography.bodyMedium),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTypography.labelSmall.copyWith(
              color: isDark
                  ? AppColors.textTertiaryDark
                  : AppColors.textTertiaryLight,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value.isNotEmpty ? value : '—',
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
