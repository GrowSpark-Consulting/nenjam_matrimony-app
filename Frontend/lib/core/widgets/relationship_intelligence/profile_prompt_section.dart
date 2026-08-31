import 'package:flutter/material.dart';

import '../../../features/profile_prompts/domain/models/prompt_bank_item.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';
import '../../constants/app_spacing.dart';
import '../../../l10n/app_localizations.dart';

/// Displays a member's Hinge-style profile prompts (question + short
/// answer). Used on the Profile Intelligence hub, `editStep` summaries, and
/// read-only on [ProfilePage] (`editable: false`).
class ProfilePromptSection extends StatelessWidget {
  final List<PromptAnswer> prompts;
  final bool editable;
  final VoidCallback? onEditTap;

  const ProfilePromptSection({
    super.key,
    required this.prompts,
    this.editable = false,
    this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (prompts.isEmpty) {
      if (!editable) return const SizedBox.shrink();
      return GestureDetector(
        onTap: onEditTap,
        child: Container(
          width: double.infinity,
          padding: AppSpacing.cardPaddingLarge,
          decoration: AppDecorations.accentBorder,
          child: Row(
            children: [
              const Icon(
                Icons.add_circle_outline_rounded,
                color: AppColors.secondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).riAddFirstPrompt,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppLocalizations.of(context).profileCompletionGrowthPrompts,
              style: AppTypography.titleMedium,
            ),
            const Spacer(),
            if (editable)
              TextButton.icon(
                onPressed: onEditTap,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(
                  AppLocalizations.of(context).registrationEditButton,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ...prompts.map(
          (p) => Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            padding: AppSpacing.cardPaddingLarge,
            decoration: AppDecorations.card(isDark: isDark),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.format_quote_rounded,
                      color: AppColors.secondary,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        p.promptText,
                        style: AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  p.answerText,
                  style: AppTypography.bodyMedium.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
