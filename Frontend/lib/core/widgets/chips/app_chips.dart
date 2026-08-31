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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Selected is a solid plum fill, unselected a soft lavender one — the
    // two states have to differ in *fill*, not only in border, so the
    // selection is readable at a glance in a dense filter row.
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: onSelected,
      backgroundColor: isDark
          ? AppColors.surfaceVariantDark
          : AppColors.softLavender,
      selectedColor: isDark
          ? AppColors.primaryContainerDark
          : AppColors.primary,
      checkmarkColor: isDark
          ? AppColors.primaryOnDark
          : AppColors.textOnPrimary,
      labelStyle: AppTypography.labelMedium.copyWith(
        color: isSelected
            ? (isDark ? AppColors.primaryOnDark : AppColors.textOnPrimary)
            : (isDark ? AppColors.textSecondaryDark : AppColors.primaryDark),
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: isSelected
              ? AppColors.primary
              : (isDark ? AppColors.borderDark : AppColors.borderLight),
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
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.surfaceVariantDark
          : AppColors.softLavender,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}

/// Occupation Chip.
class NmOccupationChip extends StatelessWidget {
  final String label;
  const NmOccupationChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return _BaseChip(
      label: label,
      icon: Icons.work_outline_rounded,
      color: AppColors.info,
    );
  }
}

/// Interest Chip.
class NmInterestChip extends StatelessWidget {
  final String label;
  const NmInterestChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return _BaseChip(
      label: label,
      icon: Icons.favorite_border_rounded,
      color: AppColors.liked,
    );
  }
}

/// Verified Chip.
class NmVerifiedChip extends StatelessWidget {
  final String label;
  const NmVerifiedChip({super.key, this.label = 'Verified'});

  @override
  Widget build(BuildContext context) {
    return _BaseChip(
      label: label,
      icon: Icons.verified_rounded,
      color: AppColors.verifiedBlue,
      isFilled: true,
    );
  }
}

/// Premium Chip.
class NmPremiumChip extends StatelessWidget {
  final String label;
  const NmPremiumChip({super.key, this.label = 'Premium'});

  @override
  Widget build(BuildContext context) {
    return _BaseChip(
      label: label,
      icon: Icons.workspace_premium_rounded,
      color: AppColors.secondary,
      isFilled: true,
    );
  }
}

/// Religion Chip.
class NmReligionChip extends StatelessWidget {
  final String label;
  const NmReligionChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return _BaseChip(
      label: label,
      icon: Icons.temple_hindu_outlined,
      color: AppColors.warning,
    );
  }
}

/// Language Chip.
class NmLanguageChip extends StatelessWidget {
  final String label;
  const NmLanguageChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return _BaseChip(
      label: label,
      icon: Icons.translate_rounded,
      color: AppColors.success,
    );
  }
}

class _BaseChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isFilled;

  const _BaseChip({
    required this.label,
    required this.icon,
    required this.color,
    this.isFilled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isFilled ? color : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: isFilled
            ? null
            : Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isFilled ? Colors.white : color),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: isFilled ? Colors.white : color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
