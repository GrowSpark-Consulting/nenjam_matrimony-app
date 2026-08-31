import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../utils/registration_milestones.dart';

/// Replaces the old "Step X of Y" + raw percentage bar with a warm,
/// milestone-based journey timeline. Purely presentational — takes plain
/// ints, never reads [registrationProvider] itself. Rendered at the top of
/// the wizard's body (no system [AppBar], no back arrow, no Save & Exit —
/// backward navigation is handled entirely by the system back gesture via
/// ProfileWizardPage's PopScope).
class RegistrationJourneyHeader extends StatelessWidget {
  final int stepIndex;
  final int totalSteps;

  const RegistrationJourneyHeader({
    super.key,
    required this.stepIndex,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentMilestone = milestoneForStep(stepIndex);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
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
                                    : AppColors.surfaceVariantLight,
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
                                      : AppColors.surfaceVariantLight,
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
                                    : AppColors.surfaceVariantLight,
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
