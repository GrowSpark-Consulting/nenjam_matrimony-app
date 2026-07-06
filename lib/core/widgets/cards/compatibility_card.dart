import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';

/// AI Compatibility score card comparing values, lifestyle, and horoscope.
class NmCompatibilityCard extends StatelessWidget {
  final int score;
  final String title;
  final List<String> matchingPoints;

  const NmCompatibilityCard({
    super.key,
    required this.score,
    this.title = 'AI Match Compatibility',
    required this.matchingPoints,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.card(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                height: 56,
                width: 56,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: score / 100,
                      strokeWidth: 5,
                      backgroundColor: AppColors.divider,
                      color: AppColors.accentGold,
                    ),
                    Center(
                      child: Text(
                        '$score%',
                        style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w700),
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
                    Text(title, style: AppTypography.titleMedium),
                    const SizedBox(height: 2),
                    Text('Based on 40+ AI lifestyle parameters', style: AppTypography.labelSmall.copyWith(color: AppColors.textTertiaryLight)),
                  ],
                ),
              ),
            ],
          ),
          if (matchingPoints.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            ...matchingPoints.map((point) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
                      const SizedBox(width: 8),
                      Expanded(child: Text(point, style: AppTypography.bodyMedium)),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}
