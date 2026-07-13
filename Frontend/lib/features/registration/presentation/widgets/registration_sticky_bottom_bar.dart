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
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
        ],
      ),
    );
  }
}
