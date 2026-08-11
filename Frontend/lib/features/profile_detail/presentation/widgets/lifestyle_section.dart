import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/chips/info_chip.dart';
import '../../domain/entities/lifestyle_info_entity.dart';
import '../../../../l10n/app_localizations.dart';

/// Diet/smoking/drinking/fitness chips + hobbies + a short "about me" note.
class LifestyleSection extends StatelessWidget {
  final LifestyleInfoEntity lifestyle;

  const LifestyleSection({super.key, required this.lifestyle});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final facts = <(IconData, String, String)>[
      if (lifestyle.eatingHabit.isNotEmpty)
        (Icons.restaurant_rounded, 'Diet', lifestyle.eatingHabit),
      if (lifestyle.smoking.isNotEmpty)
        (Icons.smoking_rooms_rounded, 'Smoking', lifestyle.smoking),
      if (lifestyle.drinking.isNotEmpty)
        (Icons.local_bar_rounded, 'Drinking', lifestyle.drinking),
      if (lifestyle.fitness.isNotEmpty)
        (Icons.fitness_center_rounded, 'Physical Activity', lifestyle.fitness),
      if (lifestyle.physicalStatus.isNotEmpty)
        (Icons.accessibility_new_rounded, 'Physical Status', lifestyle.physicalStatus),
    ];

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPaddingLarge,
      decoration: AppDecorations.card(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context).profileDetailTabLifestyle, style: AppTypography.titleLarge),
          const SizedBox(height: AppSpacing.base),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (icon, label, value) in facts)
                NmInfoChip(icon: icon, label: '$label: $value'),
            ],
          ),
          if (lifestyle.hobbies.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.base),
            Text(AppLocalizations.of(context).registrationHobbiesLabel, style: AppTypography.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final hobby in lifestyle.hobbies) NmInfoChip.interest(label: hobby),
              ],
            ),
          ],
          if (lifestyle.aboutMe.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.base),
            Text(
              lifestyle.aboutMe,
              style: AppTypography.bodyMedium.copyWith(color: textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
