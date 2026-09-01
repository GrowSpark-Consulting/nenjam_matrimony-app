import 'package:flutter/material.dart';

import '../../constants/app_spacing.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../theme/tokens/app_animation_tokens.dart';
import '../../theme/tokens/app_touch_target.dart';

/// A 2–3 option segmented toggle — e.g. Male/Female. Distinct from
/// [NmFilterChip] rows: exactly one option is always selected-looking
/// (equal-width segments in a single pill), rather than independently
/// selectable chips that can all be off at once.
class NmSegmentedControl<T> extends StatelessWidget {
  final List<T> options;
  final String Function(T) labelBuilder;
  final T? value;
  final ValueChanged<T?> onChanged;

  const NmSegmentedControl({
    super.key,
    required this.options,
    required this.labelBuilder,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppTouchTarget.minSize,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariantLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: _Segment(
                label: labelBuilder(option),
                isSelected: option == value,
                // Tapping the already-selected segment clears the
                // selection — same "tap again to clear" convention the
                // filter sheet's single-select chip groups already use.
                onTap: () => onChanged(option == value ? null : option),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppAnimationTokens.fast,
        curve: AppAnimationTokens.buttonPressCurve,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: isSelected ? Colors.white : AppColors.textSecondaryLight,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
