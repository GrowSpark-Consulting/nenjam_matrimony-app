import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';

/// Horoscope compatibility card.
class NmHoroscopeCard extends StatelessWidget {
  final String partnerName;
  final int gunaScore;
  final int maxScore;
  final String summary;
  final VoidCallback? onTap;

  const NmHoroscopeCard({
    super.key,
    required this.partnerName,
    this.gunaScore = 0,
    this.maxScore = 36,
    this.summary = 'Horoscope details will appear here',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = maxScore > 0 ? gunaScore / maxScore : 0.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: AppDecorations.card(isDark: isDark),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    color: AppColors.accentGold, size: 22),
                const SizedBox(width: 8),
                Text('Horoscope Match',
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress,
                        backgroundColor: isDark
                            ? AppColors.surfaceVariantDark
                            : AppColors.surfaceVariantLight,
                        color: AppColors.accentGold,
                        strokeWidth: 6,
                      ),
                      Text(
                        '$gunaScore/$maxScore',
                        style: AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Guna Milan with $partnerName',
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        summary,
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark
                              ? AppColors.textTertiaryDark
                              : AppColors.textTertiaryLight,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
