import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';

/// Discover Opportunities section — horizontally scrollable list of match
/// recommendation cards with name, profession, and compatibility %.
///
/// In the real app these cards would be driven by a provider/cubit.
/// The section is stateless so wiring happens at the page level.
class NmDiscoverOpportunitiesCard extends StatelessWidget {
  final List<NmDiscoverMatch> matches;
  final VoidCallback? onViewAllTap;

  const NmDiscoverOpportunitiesCard({
    super.key,
    required this.matches,
    this.onViewAllTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Expanded(
              child: Text(
                'Discover Opportunities',
                style: AppTypography.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              onTap: onViewAllTap,
              child: Text(
                'View All',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.accentGoldDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // Horizontal scroll of cards. Sized to content (via
        // IntrinsicHeight) rather than a fixed height, so cards never
        // clip when their text grows under large font scaling.
        matches.isEmpty
            ? SizedBox(height: 140, child: _EmptyState(isDark: isDark))
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      for (var i = 0; i < matches.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.md),
                        _MatchCard(match: matches[i], isDark: isDark),
                      ],
                    ],
                  ),
                ),
              ),
      ],
    );
  }
}

/// Individual match card in the discover list.
class _MatchCard extends StatelessWidget {
  final NmDiscoverMatch match;
  final bool isDark;

  const _MatchCard({required this.match, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: match.onTap,
      child: Container(
        width: 168,
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : AppColors.cardLight,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl2),
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.07),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo area
            SizedBox(
              height: 140,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Photo placeholder / image
                  Container(
                    color: isDark
                        ? AppColors.surfaceVariantDark
                        : AppColors.surfaceVariantLight,
                    child: match.imageUrl != null
                        ? Image.network(
                            match.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _PhotoPlaceholder(isDark: isDark),
                          )
                        : _PhotoPlaceholder(isDark: isDark),
                  ),

                  // Gradient overlay + name
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: AppGradients.imageOverlay,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Text(
                          '${match.name}, ${match.age}',
                          style: AppTypography.labelLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Info row
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.work_outline_rounded,
                        size: 12,
                        color: isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiaryLight,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          match.profession,
                          style: AppTypography.labelSmall.copyWith(
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${match.compatibilityPct}% Compatible',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.accentGoldDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  final bool isDark;
  const _PhotoPlaceholder({required this.isDark});

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(
      Icons.person_rounded,
      size: 40,
      color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight,
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final bool isDark;
  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      'No matches yet. Complete your profile to see recommendations.',
      textAlign: TextAlign.center,
      style: AppTypography.bodySmall.copyWith(
        color: isDark
            ? AppColors.textSecondaryDark
            : AppColors.textSecondaryLight,
      ),
    ),
  );
}

/// Public model for a match item passed into [NmDiscoverOpportunitiesCard].
class NmDiscoverMatch {
  final String name;
  final int age;
  final String profession;
  final int compatibilityPct;
  final String? imageUrl;
  final VoidCallback? onTap;

  const NmDiscoverMatch({
    required this.name,
    required this.age,
    required this.profession,
    required this.compatibilityPct,
    this.imageUrl,
    this.onTap,
  });
}
