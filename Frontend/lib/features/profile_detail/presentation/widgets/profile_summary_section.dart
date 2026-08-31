import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/chips/info_chip.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/profile_detail_entity.dart';

/// Compact "who is this" card directly under the hero photo — name,
/// profession, and a chip cloud of the short facts that are already on the
/// entity (location, age, height, marital status, mother tongue, religion,
/// education).
///
/// The hero's own name/location overlay scrolls away with the photo, so
/// repeating them once here is what keeps the identity readable for the rest
/// of the page. Every value is read straight off [ProfileDetailEntity] and
/// omitted when empty — nothing is synthesized.
class ProfileSummarySection extends StatelessWidget {
  final ProfileDetailEntity detail;

  const ProfileSummarySection({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = detail.base;
    final textSecondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    final religion = [
      base.religion,
      base.caste,
    ].where((s) => s.isNotEmpty).join(' · ');

    final facts = <(IconData, String)>[
      if (base.location.isNotEmpty)
        (Icons.location_on_outlined, base.location),
      if (base.age > 0) (Icons.cake_outlined, l10n.profileDetailAgeYears(base.age)),
      if (base.height.isNotEmpty) (Icons.straighten_rounded, base.height),
      if (detail.maritalStatus.isNotEmpty)
        (Icons.favorite_border_rounded, detail.maritalStatus),
      if (detail.motherTongue.isNotEmpty)
        (Icons.translate_rounded, detail.motherTongue),
      if (religion.isNotEmpty) (Icons.temple_hindu_rounded, religion),
      if (base.education.isNotEmpty)
        (Icons.school_outlined, base.education),
    ];

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPaddingLarge,
      decoration: AppDecorations.card(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            base.name,
            style: AppTypography.titleLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (base.profession.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs2),
            Text(
              base.profession,
              style: AppTypography.bodyMedium.copyWith(color: textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (facts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.base),
            // A chip's own Row is mainAxisSize.min, so inside a Wrap it is
            // handed unbounded width and its Flexible/ellipsis never engages
            // — a long location or degree would run off the card at 320px.
            // Capping each chip at the card's own content width is what makes
            // the ellipsis fire instead.
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final (icon, value) in facts)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                      ),
                      child: NmInfoChip(icon: icon, label: value),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
