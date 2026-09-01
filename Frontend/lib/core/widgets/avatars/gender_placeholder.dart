import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// "No photo yet" placeholder — a bust silhouette on a soft background,
/// using the built-in gender-specific Material icons when [gender] is
/// known ('Male' / 'Female') so male and female profiles get a visually
/// distinct fallback instead of one generic person icon. Falls back to a
/// gender-neutral silhouette when [gender] is empty/unrecognized.
class NmGenderPlaceholder extends StatelessWidget {
  final String gender;
  final double iconSize;
  final Color? backgroundColor;
  final Color? iconColor;

  const NmGenderPlaceholder({
    super.key,
    this.gender = '',
    this.iconSize = 48,
    this.backgroundColor,
    this.iconColor,
  });

  IconData get _icon => switch (gender) {
    'Male' => Icons.man_rounded,
    'Female' => Icons.woman_rounded,
    _ => Icons.person_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      color:
          backgroundColor ??
          AppColors.surfaceVariantLight,
      alignment: Alignment.center,
      child: Icon(
        _icon,
        size: iconSize,
        color:
            iconColor ??
            AppColors.textTertiaryLight,
      ),
    );
  }
}
