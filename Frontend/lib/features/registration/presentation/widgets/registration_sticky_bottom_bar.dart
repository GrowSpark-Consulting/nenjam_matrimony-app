import 'package:flutter/material.dart';

import '../../../../core/animations/app_animations.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';

/// Floating action card pinned to the bottom of each section edit page
/// (ProfileSectionEditPage): a
/// Back control, the primary action, and — when the open section is
/// incomplete — a line saying why the primary action is disabled.
///
/// It used to carry the signup wizard's progress chrome as well (a
/// milestone label, an estimated-time-remaining string and a Skip action).
/// That 13-step flow no longer exists — this bar now serves only the
/// section edit pages' Save — so those went with it rather than
/// lingering as always-null parameters.
///
/// Composes the existing [NmGradientButton]/[AppAnimations.buttonPress] —
/// no duplicate button widgets, no provider reads.
///
/// The Back control is a fixed-size icon button rather than a labeled
/// button sharing a flex fraction of the row: giving it a proportional
/// share of the width (the previous `Expanded(flex:1)` design) meant its
/// available width shrank on smaller screens while the button's own theme
/// padding stayed fixed at 24dp/side — on any screen narrower than ~380dp
/// logical width that left too little room for an icon + label and
/// overflowed even in English at 1.0x text scale. Sizing Back to its own
/// compact content and giving the primary action the entire remaining
/// width via [Expanded] removes that conflict structurally instead of
/// compressing the label.
class RegistrationStickyBottomBar extends StatelessWidget {
  final String continueLabel;
  final IconData continueIcon;
  final String backLabel;
  final bool isLoading;
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  /// Shown above the button row when non-null — surfaces *why* the primary
  /// action is disabled (missing/incomplete required fields) instead of
  /// silently greying it out with no explanation.
  final String? validationHint;

  /// Collapses the bar to a single action row. Set by the edit page when
  /// usable body height cannot fit the full bar — a landscape phone with the
  /// keyboard raised leaves ~98dp, against ~164dp for the full layout. The
  /// validation line is dropped and the controls shrink from 56dp to 48dp;
  /// both actions survive, so nothing becomes unreachable.
  final bool compact;

  const RegistrationStickyBottomBar({
    super.key,
    required this.continueLabel,
    required this.continueIcon,
    required this.backLabel,
    required this.isLoading,
    this.onBack,
    this.onNext,
    this.validationHint,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) return _buildCompact(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      // The bar's surface spans the window; its buttons line up with the
      // centered form above them.
      child: NmContentWidth(
        maxWidth: ContentWidth.form,
        fill: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (validationHint != null) ...[
              Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      validationHint!,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
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
          ],
        ),
      ),
    );
  }

  /// Single-row variant used when vertical space is scarce. Keeps 48dp
  /// touch targets (above the 44dp minimum) while fitting in ~64dp total.
  Widget _buildCompact(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: NmContentWidth(
        maxWidth: ContentWidth.form,
        fill: true,
        child: Row(
          children: [
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
          ],
        ),
      ),
    );
  }
}
