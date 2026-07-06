import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Selectable chip for interests, religion, language, etc.
class NmInfoChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback? onTap;
  final Color? selectedColor;

  const NmInfoChip({
    super.key,
    required this.label,
    this.icon,
    this.isSelected = false,
    this.onTap,
    this.selectedColor,
  });

  /// Interest chip factory.
  const NmInfoChip.interest({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onTap,
  })  : icon = null,
        selectedColor = AppColors.primary;

  /// Religion chip factory.
  const NmInfoChip.religion({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onTap,
  })  : icon = Icons.temple_hindu_rounded,
        selectedColor = AppColors.accentGold;

  /// Language chip factory.
  const NmInfoChip.language({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onTap,
  })  : icon = Icons.translate_rounded,
        selectedColor = AppColors.info;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chipColor = selectedColor ?? AppColors.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? chipColor.withValues(alpha: 0.12)
              : (isDark
                  ? AppColors.surfaceVariantDark
                  : AppColors.surfaceVariantLight),
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: chipColor.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? chipColor
                    : (isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiaryLight),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: isSelected
                    ? chipColor
                    : (isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
