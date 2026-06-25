import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Badge size variants.
enum NmBadgeSize { small, medium, large }

/// Premium gold badge.
class NmPremiumBadge extends StatelessWidget {
  final NmBadgeSize size;
  final bool showLabel;

  const NmPremiumBadge({
    super.key,
    this.size = NmBadgeSize.medium,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = switch (size) {
      NmBadgeSize.small => 14.0,
      NmBadgeSize.medium => 18.0,
      NmBadgeSize.large => 22.0,
    };

    final padding = switch (size) {
      NmBadgeSize.small => const EdgeInsets.all(4.0),
      NmBadgeSize.medium => const EdgeInsets.all(6.0),
      NmBadgeSize.large => const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    };

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.accentGold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_rounded,
              size: iconSize, color: AppColors.accentGold),
          if (showLabel) ...[
            const SizedBox(width: 4),
            Text(
              'Premium',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.accentGoldDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
