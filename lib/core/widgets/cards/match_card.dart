import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';

/// Match card with compatibility percentage.
class NmMatchCard extends StatelessWidget {
  final String name;
  final String age;
  final String? imageUrl;
  final int matchPercentage;
  final String matchReason;
  final VoidCallback? onTap;

  const NmMatchCard({
    super.key,
    required this.name,
    required this.age,
    this.imageUrl,
    required this.matchPercentage,
    this.matchReason = 'AI Match',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: AppDecorations.card(isDark: isDark),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Image
            SizedBox(
              width: 100,
              height: 120,
              child: imageUrl != null
                  ? Image.network(imageUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(isDark))
                  : _placeholder(isDark),
            ),

            // Details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$name, $age',
                      style: AppTypography.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _CompatibilityBadge(percentage: matchPercentage),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            matchReason,
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
                  ],
                ),
              ),
            ),

            // Arrow
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                Icons.chevron_right_rounded,
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(bool isDark) => Container(
        color: isDark
            ? AppColors.surfaceVariantDark
            : AppColors.surfaceVariantLight,
        child: Icon(
          Icons.person_rounded,
          size: 32,
          color: isDark
              ? AppColors.textTertiaryDark
              : AppColors.textTertiaryLight,
        ),
      );
}

class _CompatibilityBadge extends StatelessWidget {
  final int percentage;
  const _CompatibilityBadge({required this.percentage});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentGoldSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$percentage%',
        style: AppTypography.labelSmall.copyWith(
          color: AppColors.accentGoldDark,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
