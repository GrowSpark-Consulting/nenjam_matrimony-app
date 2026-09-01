import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/avatars/gender_placeholder.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/widgets/images/sized_network_photo.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Expanded(
              child: Text(
                AppLocalizations.of(context).profileDiscoverOpportunities,
                style: AppTypography.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Flexible, not a bare Text: "View All" is one short word in
            // English but "அனைத்தையும் காண்க" in Tamil, which at large text
            // scales on a 320dp screen is wider than the space the Expanded
            // title leaves — unconstrained it overflowed the Row by ~145px.
            Flexible(
              child: GestureDetector(
                onTap: onViewAllTap,
                child: Text(
                  AppLocalizations.of(context).discoverViewAllButton,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.secondaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
            ? const SizedBox(height: 140, child: _EmptyState())
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      for (var i = 0; i < matches.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.md),
                        _MatchCard(match: matches[i]),
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

  const _MatchCard({required this.match});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: match.onTap,
      child: Container(
        width: 168,
        decoration: BoxDecoration(
          color: AppColors.cardLight,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl2),
          boxShadow: [
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
                    color: AppColors.surfaceVariantLight,
                    child: match.imageUrl != null
                        ? NmSizedNetworkPhoto(
                            url: match.imageUrl!,
                            errorBuilder: (_, __, ___) => NmGenderPlaceholder(
                              gender: match.gender,
                              iconSize: 40,
                            ),
                          )
                        : NmGenderPlaceholder(
                            gender: match.gender,
                            iconSize: 40,
                          ),
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
                      const Icon(
                        Icons.work_outline_rounded,
                        size: 12,
                        color: AppColors.textTertiaryLight,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          match.profession,
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.textSecondaryLight,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(
                      context,
                    ).profileCompatiblePercent(match.compatibilityPct),
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.secondaryDark,
                      fontWeight: FontWeight.w700,
                    ),
                    // "85% Compatible" is one line in English but wraps in
                    // Tamil inside this fixed-width (168dp) card.
                    maxLines: 2,
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
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      AppLocalizations.of(context).profileNoRecommendations,
      textAlign: TextAlign.center,
      style: AppTypography.bodySmall.copyWith(
        color: AppColors.textSecondaryLight,
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

  /// 'Male' / 'Female' / '' — picks the gender-aware placeholder icon
  /// when [imageUrl] is null/fails to load.
  final String gender;
  final VoidCallback? onTap;

  const NmDiscoverMatch({
    required this.name,
    required this.age,
    required this.profession,
    required this.compatibilityPct,
    this.imageUrl,
    this.gender = '',
    this.onTap,
  });
}
