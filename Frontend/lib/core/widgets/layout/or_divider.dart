import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Reusable horizontal divider with centered text (e.g., "or continue with").
class NmOrDivider extends StatelessWidget {
  final String label;

  const NmOrDivider({super.key, this.label = 'or continue with'});

  @override
  Widget build(BuildContext context) {
    const dividerColor = AppColors.dividerLight;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider(color: dividerColor, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.textSecondaryLight,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const Expanded(child: Divider(color: dividerColor, thickness: 1)),
        ],
      ),
    );
  }
}
