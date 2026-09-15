import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Reusable Filter / Selected Chip.
class NmFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final void Function(bool)? onSelected;

  const NmFilterChip({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // Selected is a solid plum fill, unselected a soft lavender one — the
    // two states have to differ in *fill*, not only in border, so the
    // selection is readable at a glance in a dense filter row.
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: onSelected,
      backgroundColor: AppColors.softLavender,
      selectedColor: AppColors.primary,
      checkmarkColor: AppColors.textOnPrimary,
      labelStyle: AppTypography.labelMedium.copyWith(
        color: isSelected
            ? AppColors.textOnPrimary
            : AppColors.primaryDark,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: isSelected
              ? AppColors.primary
              : AppColors.borderLight,
        ),
      ),
    );
  }
}

/// Reusable Removable Input Chip.
class NmRemovableChip extends StatelessWidget {
  final String label;
  final VoidCallback onDeleted;

  const NmRemovableChip({
    super.key,
    required this.label,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label, style: AppTypography.labelMedium),
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      onDeleted: onDeleted,
      backgroundColor: AppColors.softLavender,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}