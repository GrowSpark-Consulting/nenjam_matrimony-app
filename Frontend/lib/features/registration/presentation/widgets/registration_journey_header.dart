import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../utils/registration_milestones.dart';

/// Replaces the old "Step X of Y" + raw percentage bar with a warm,
/// milestone-based journey timeline. Purely presentational — takes plain
/// ints/callbacks, never reads [registrationProvider] itself. Rendered at
/// the top of the wizard's body (no system [AppBar] is used) so the back
/// button and Save & Exit action live inside this widget.
class RegistrationJourneyHeader extends StatelessWidget {
  final int stepIndex;
  final int totalSteps;
  final VoidCallback onBack;
  final VoidCallback? onSaveExit;

  const RegistrationJourneyHeader({
    super.key,
    required this.stepIndex,
    required this.totalSteps,
    required this.onBack,
    this.onSaveExit,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentMilestone = milestoneForStep(stepIndex);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const Spacer(),
                if (onSaveExit != null)
                  TextButton(
                    onPressed: onSaveExit,
                    child: Text(
                      l10n.registrationSaveExit,
                      style: AppTypography.labelLarge
                          .copyWith(color: AppColors.primary),
                    ),
                  ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: List.generate(RegistrationMilestone.values.length, (i) {
                final milestone = RegistrationMilestone.values[i];
                final isDone = milestone.index < currentMilestone.index;
                final isCurrent = milestone == currentMilestone;
                final (emoji, label) = milestoneEmojiAndLabel(l10n, milestone);

                return Expanded(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          if (i > 0)
                            Expanded(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 400),
                                height: 2,
                                color: isDone || isCurrent
                                    ? AppColors.primary
                                    : (isDark
                                        ? AppColors.surfaceVariantDark
                                        : AppColors.surfaceVariantLight),
                              ),
                            ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOut,
                            width: isCurrent ? 32 : 26,
                            height: isCurrent ? 32 : 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDone
                                  ? AppColors.primary
                                  : isCurrent
                                      ? AppColors.primary.withValues(alpha: 0.15)
                                      : (isDark
                                          ? AppColors.surfaceVariantDark
                                          : AppColors.surfaceVariantLight),
                              border: isCurrent
                                  ? Border.all(color: AppColors.primary, width: 2)
                                  : null,
                            ),
                            child: isDone
                                ? const Icon(Icons.check_rounded,
                                    size: 14, color: Colors.white)
                                : Text(emoji, style: const TextStyle(fontSize: 13)),
                          ),
                          if (i < RegistrationMilestone.values.length - 1)
                            Expanded(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 400),
                                height: 2,
                                color: isDone
                                    ? AppColors.primary
                                    : (isDark
                                        ? AppColors.surfaceVariantDark
                                        : AppColors.surfaceVariantLight),
                              ),
                            ),
                        ],
                      ),
                      if (isCurrent) ...[
                        const SizedBox(height: 6),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
