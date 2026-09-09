import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/completion_card.dart';
import '../../../../core/widgets/indicators/nm_gradient_progress_bar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../registration/presentation/utils/open_edit_profile.dart';
import '../../domain/completion_recommendation.dart';
import '../providers/completion_recommendation_provider.dart';
import '../providers/profile_completeness_provider.dart';
import '../utils/module_copy.dart';

/// "Complete Your Profile" — the percentage, a compact progress bar, and the
/// horizontally scrolling recommendation cards.
///
/// The ONE widget both Home and Edit Profile render, on purpose. Both read
/// [profileCompletenessSnapshotProvider], which is built from the single
/// `GET /profiles/draft` response, so the two screens show the same
/// percentage and the same cards by construction rather than by two lists
/// being kept in step by hand. Finish a section from Home and the card is
/// gone from Edit Profile on its next build; dismiss it from Edit Profile and
/// Home loses it too.
///
/// Renders nothing at all when there is nothing to recommend — a member with
/// a finished profile gets no empty box and no congratulation banner.
class CompleteProfileSection extends ConsumerWidget {
  /// Horizontal padding for the header and the card row's first/last card.
  /// Home uses its feed's 16; Edit Profile passes 0 because its own page
  /// padding already supplies the margin.
  final double horizontalPadding;

  /// Space above and below the section, applied ONLY when there is something
  /// to show. Kept inside the widget rather than left to the caller so a
  /// finished profile leaves no gap where the section used to be — a caller
  /// that wrapped this in its own Padding would reserve that space forever.
  final EdgeInsets margin;

  const CompleteProfileSection({
    super.key,
    this.horizontalPadding = AppSpacing.base,
    this.margin = const EdgeInsets.symmetric(vertical: AppSpacing.base),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final completeness = ref
        .watch(profileCompletenessSnapshotProvider)
        .valueOrNull;
    if (completeness == null) return const SizedBox.shrink();

    final pending = ref.watch(pendingDismissalsProvider);
    final cards = completeness.visibleCards(pendingDismissals: pending);
    if (cards.isEmpty) return const SizedBox.shrink();

    final pad = EdgeInsets.symmetric(horizontal: horizontalPadding);

    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: pad,
            child: Text(
              l10n.homeCompleteProfileTitle,
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimaryLight,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: pad,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    // The backend's number, carried through untouched — the
                    // same figure the Profile dashboard and the Profile
                    // Strength screen show. Nothing here recomputes it from
                    // the cards, so hiding or finishing one never moves it
                    // on its own.
                    l10n.completionCardsScoreLabel(completeness.percentage),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondaryLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Compact and inline beside the score rather than a
                // full-width bar: the figure is the message here, the bar
                // only gives it a shape. Same gradient ramp as every other
                // completion bar in the app.
                SizedBox(
                  width: 56,
                  child: NmGradientProgressBar(
                    value: completeness.percentage / 100,
                    height: 8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          NmCompletionCardRow(
            padding: pad,
            cards: [
              for (final card in cards)
                NmCompletionCard(
                  key: ValueKey('completion-card-${card.key}'),
                  icon: completionCardIcon(card.key),
                  title: completionCardTitle(l10n, card.key),
                  description: completionCardBody(l10n, card.key),
                  badge: completionCardBadge(l10n, card),
                  tint: completionCardTint(card.key),
                  tintSurface: completionCardTintSurface(card.key),
                  dismissTooltip: l10n.completionCardDismissTooltip,
                  onTap: () => _open(context, ref, card),
                  onDismiss: () => _dismiss(context, ref, card),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Opens the page that completes this section.
  ///
  /// Routes through [openEditProfile] with the card's `wizardStep`, so both
  /// screens land on exactly the same page via the one route table
  /// (`profileSectionRoute`) the app already has — family and horoscope are
  /// Edit Profile sections, psychology and verification are pages of their
  /// own, and none of that is decided here.
  ///
  /// Nothing is marked complete on the way back: the section's own save is
  /// what makes it complete, and the refresh below simply re-reads what the
  /// backend now says. A member who opens a card and backs out unchanged
  /// still sees it.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    CompletionRecommendation card,
  ) async {
    await openEditProfile(context, ref, wizardStep: card.wizardStep);
    if (!context.mounted) return;
    refreshProfileCompletion(ref);
  }

  Future<void> _dismiss(
    BuildContext context,
    WidgetRef ref,
    CompletionRecommendation card,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await ref
        .read(pendingDismissalsProvider.notifier)
        .dismiss(card.key);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          ok ? l10n.completionCardDismissed : l10n.completionCardDismissFailed,
        ),
      ),
    );
  }
}
