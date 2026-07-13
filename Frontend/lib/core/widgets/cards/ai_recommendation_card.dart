import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../constants/app_spacing.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';

/// AI recommendation card for smart matches.
///
/// Sizes itself from its content — the photo tile is aspect-ratio driven
/// and the text block below it is intrinsically sized (`MainAxisSize.min`
/// on both the outer and inner [Column]), so the card never assumes or
/// requires a fixed overall height from its parent. Callers that need a
/// horizontal rail of these should give the *row*, not the card, room to
/// size itself (see `RecommendationRailSection`) rather than constraining
/// this widget to a guessed pixel height.
class NmAiRecommendationCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final int compatibility;
  final String reason;
  final VoidCallback? onTap;
  final double width;

  const NmAiRecommendationCard({
    super.key,
    required this.name,
    this.imageUrl,
    required this.compatibility,
    required this.reason,
    this.onTap,
    this.width = 180,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        decoration: AppDecorations.card(isDark: isDark),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: isDark
                        ? AppColors.surfaceVariantDark
                        : AppColors.surfaceVariantLight,
                    child: imageUrl != null
                        ? Image.network(imageUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholder(isDark))
                        : _placeholder(isDark),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome,
                              size: 12, color: AppColors.accentGold),
                          const SizedBox(width: 4),
                          Text(
                            l10n.homeAiPickBadge,
                            style: AppTypography.labelSmall.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: AppSpacing.cardPaddingCompact,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppTypography.titleSmall, maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '$compatibility% ${l10n.discoverAiMatchLabel} • $reason',
                    style: AppTypography.labelSmall.copyWith(
                      color: isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiaryLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(bool isDark) => Center(
        child: Icon(Icons.person_rounded, size: 36,
            color: isDark
                ? AppColors.textTertiaryDark
                : AppColors.textTertiaryLight),
      );
}
