import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/ai_recommendation_card.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/recommendation_rail_provider.dart';

/// Section 7 — Today's Recommendation, a horizontal rail of alternates to
/// the hero match, reusing the same AI recommendation card as elsewhere.
class RecommendationRailSection extends ConsumerWidget {
  const RecommendationRailSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(recommendationRailProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.nenjamHubRecommendationsTitle,
            style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        async.when(
          data: (profiles) {
            if (profiles.isEmpty) return const SizedBox.shrink();
            // A horizontal SingleChildScrollView wrapping a Row (rather than
            // a ListView pinned to a guessed pixel height) lets each card
            // size itself from its own content — the row's height becomes
            // the tallest card's natural height, so longer localized text
            // or larger text-scale settings simply make the row taller
            // instead of overflowing a fixed box.
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < profiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.md),
                    NmAiRecommendationCard(
                      name: profiles[i].name,
                      imageUrl: profiles[i].photoUrls.isNotEmpty
                          ? profiles[i].photoUrls.first
                          : null,
                      compatibility:
                          profiles[i].compatibility.overallCompatibility,
                      reason: profiles[i].distanceKm != null
                          ? '${profiles[i].distanceKm!.toStringAsFixed(1)} km away'
                          : profiles[i].profession,
                    ),
                  ],
                ],
              ),
            );
          },
          loading: () => const _RecommendationRailShimmer(),
          error: (error, _) => NmErrorWidget(
            onRetry: () => ref.invalidate(recommendationRailProvider),
          ),
        ),
      ],
    );
  }
}

/// Mirrors [NmAiRecommendationCard]'s own shape (aspect-ratio photo tile +
/// two text bars) rather than guessing a pixel height, so the loading state
/// can never drift out of sync with the real card's sizing.
class _RecommendationRailShimmer extends StatelessWidget {
  const _RecommendationRailShimmer();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.md),
            const SizedBox(
              width: 180,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                      aspectRatio: 1, child: NmShimmer(borderRadius: 20)),
                  SizedBox(height: AppSpacing.sm),
                  NmShimmer(width: 120, height: 14),
                  SizedBox(height: AppSpacing.xs),
                  NmShimmer(width: 90, height: 11),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
