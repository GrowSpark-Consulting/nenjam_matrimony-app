import 'package:flutter/material.dart';

import '../../../../core/animations/app_animations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';

/// Floating premium bottom card replacing the plain Back/Continue bar:
/// shows the current milestone label, an estimated-time-remaining string,
/// and the Continue button. Composes the existing
/// [NmGradientButton]/[AppAnimations.buttonPress] — no duplicate button
/// widgets, no provider reads.
///
/// The Back control is a fixed-size icon button rather than a labeled
/// button sharing a flex fraction of the row: giving it a proportional
/// share of the width (the previous `Expanded(flex:1)` design) meant its
/// available width shrank on smaller screens while the button's own theme
/// padding stayed fixed at 24dp/side — on any screen narrower than ~380dp
/// logical width that left too little room for an icon + label and
/// overflowed even in English at 1.0x text scale. Sizing Back to its own
/// compact content and giving Continue the entire remaining width via
/// [Expanded] removes that conflict structurally instead of compressing
/// the label.
class RegistrationStickyBottomBar extends StatelessWidget {
  final String milestoneLabel;
  final String estimatedTimeLabel;
  final String continueLabel;
  final IconData continueIcon;
  final String backLabel;
  final bool showBack;
  final bool isLoading;
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  /// Rendered as a centered text button below Continue only when non-null —
  /// shown for skippable steps (Education, Lifestyle, Family, Horoscope,
  /// Partner Preference). See ProfileWizardPage._isStepSkippable.
  final String? skipLabel;
  final VoidCallback? onSkip;

  /// Shown above the button row when non-null — surfaces *why* Continue is
  /// disabled (missing/incomplete required fields) instead of silently
  /// greying it out with no explanation.
  final String? validationHint;

  /// Collapses the bar to a single action row. Set by the wizard when the
  /// usable body height cannot fit the full bar — a landscape phone with the
  /// keyboard raised leaves ~98dp, against ~164dp for the full layout. The
  /// milestone/estimate and validation lines are dropped and the controls
  /// shrink from 56dp to 48dp; every action (Back, Continue, Skip) survives,
  /// so nothing becomes unreachable.
  final bool compact;

  const RegistrationStickyBottomBar({
    super.key,
    required this.milestoneLabel,
    required this.estimatedTimeLabel,
    required this.continueLabel,
    required this.continueIcon,
    required this.backLabel,
    required this.showBack,
    required this.isLoading,
    this.onBack,
    this.onNext,
    this.skipLabel,
    this.onSkip,
    this.validationHint,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (compact) return _buildCompact(context, isDark);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Expanded (not just Flexible) so it both ellipsizes safely
              // *and* still pushes the time estimate to the row's far
              // edge, preserving the original spaceBetween look.
              Expanded(
                child: Text(
                  milestoneLabel,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  estimatedTimeLabel,
                  textAlign: TextAlign.end,
                  style: AppTypography.labelSmall.copyWith(
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiaryLight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (validationHint != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    validationHint!,
                    style: AppTypography.labelSmall.copyWith(color: AppColors.error),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (showBack) ...[
                Tooltip(
                  message: backLabel,
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: OutlinedButton(
                      onPressed: isLoading ? null : onBack,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: AppAnimations.buttonPress(
                  NmGradientButton(
                    label: continueLabel,
                    icon: continueIcon,
                    isLoading: isLoading,
                    onPressed: isLoading ? null : onNext,
                  ),
                ),
              ),
            ],
          ),
          if (onSkip != null) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: isLoading ? null : onSkip,
                child: Text(
                  skipLabel ?? '',
                  style: AppTypography.labelLarge.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Single-row variant used when vertical space is scarce. Keeps 48dp
  /// touch targets (above the 44dp minimum) while fitting in ~64dp total.
  Widget _buildCompact(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (showBack) ...[
            Tooltip(
              message: backLabel,
              child: SizedBox(
                width: 48,
                height: 48,
                child: OutlinedButton(
                  onPressed: isLoading ? null : onBack,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Icon(Icons.arrow_back_rounded),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: SizedBox(
              height: 48,
              child: NmGradientButton(
                label: continueLabel,
                icon: continueIcon,
                isLoading: isLoading,
                onPressed: isLoading ? null : onNext,
              ),
            ),
          ),
          if (onSkip != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: TextButton(
                onPressed: isLoading ? null : onSkip,
                child: Text(
                  skipLabel ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
