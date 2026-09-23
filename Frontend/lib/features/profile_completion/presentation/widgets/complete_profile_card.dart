import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../profile_photos/presentation/providers/photo_providers.dart';
import '../../../profile_photos/presentation/widgets/photo_manager_section.dart'
    show kMaxPhotos;
import '../../../registration/presentation/utils/open_edit_profile.dart';
import '../../domain/completion_recommendation.dart';
import '../providers/completion_recommendation_provider.dart';
import '../providers/profile_completeness_provider.dart';
import '../utils/module_copy.dart';

/// Whether this Home card has been closed for the current app session.
///
/// Deliberately NOT persisted anywhere — dismissing this card only hides the
/// nudge; it must never be mistaken for any section being complete, which is
/// exactly what a server-side dismissal (see [pendingDismissalsProvider])
/// would risk implying here. Resets the next time the app is launched, and a
/// tile that is actually completed disappears on its own regardless of this
/// flag (see [CompleteProfileCard]'s empty-cards check).
final completeProfileCardDismissedProvider = StateProvider<bool>((_) => false);

/// One tile's worth of what [CompleteProfileCard] needs to draw and open it.
///
/// A plain view-model rather than reusing [CompletionRecommendation]
/// directly: Photos isn't one of the backend's recommendation cards at all
/// (see the wizardStep-11 comment on [CompleteProfileCard._items]), so the
/// card needs one shape both a real recommendation and the photo count can
/// be turned into.
class _HomeCompletionItem {
  final String key;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HomeCompletionItem({
    required this.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// The compact "Complete Your Profile" reminder for Home/Discover — a header
/// plus a horizontally scrollable row of tappable tiles for whichever of
/// Add Photos, Family Details, Horoscope, Psychology, Partner Preferences and
/// Verification are still incomplete.
///
/// A deliberately smaller sibling of `CompleteProfileSection` (Edit
/// Profile's full card row): the five backend-scored sections read the same
/// [profileCompletenessSnapshotProvider] response that section reads, so the
/// two can never disagree about what's done. Photos is the one exception —
/// see [_items] — sourced from the same [myPhotosProvider] every other photo
/// UI in the app reads, never invented. Laid out as one bordered card rather
/// than individually-bordered tiles, and dismissed as one unit rather than
/// tile by tile.
///
/// Renders nothing when there is nothing to ask for (everything complete, or
/// the whole card was dismissed this session): a finished profile leaves no
/// gap in the feed where this card used to be.
class CompleteProfileCard extends ConsumerWidget {
  const CompleteProfileCard({super.key});

  // Wizard-step destinations, the same stable numbering `profileSectionRoute`
  // and the backend's `RECOMMENDATION_CARDS` already use everywhere else in
  // the app (family/horoscope are Edit Profile sections, psychology/partner
  // preference/verification/photos are pages of their own) — hardcoded here rather than
  // read off a recommendation entry's `wizardStep`, so a tile still knows
  // where to navigate even in the edge case its own entry is missing from
  // the response.
  static const int _wizardStepFamily = 7;
  static const int _wizardStepHoroscope = 8;
  static const int _wizardStepPsychology = 9;
  static const int _wizardStepPartnerPreference = 10;
  static const int _wizardStepPhotos = 11;
  static const int _wizardStepVerification = 12;

  /// Whether [key]'s section is complete, straight off the real backend
  /// signal — never re-derived, never guessed.
  ///
  /// Deliberately NOT `recommendations.where(...)`: a filter silently treats
  /// "this card isn't in the list" the same as "this card is done," which
  /// would hide a tile this card should still be nudging about. Looking each
  /// key up explicitly means a missing or malformed entry reads as
  /// incomplete — the safe default for a reminder card is to keep asking,
  /// not to go quiet.
  bool _isComplete(
    List<CompletionRecommendation> recommendations,
    String key,
  ) => recommendations.any((r) => r.key == key && r.isComplete);

  /// The tiles to offer, in display order: Add Photos (the single biggest
  /// lever on match quality), then Family Details, Horoscope, Psychology,
  /// Partner Preferences, Verification — each evaluated independently
  /// against its own real completion source, not filtered from one shared
  /// list. Verification reads the backend's own `verification` card, which
  /// completes only once every verification weight is earned — the same
  /// signal the percentage is scored from.
  ///
  /// Photos is scored differently from every other tile here on purpose:
  /// the backend's own `photo` recommendation card completes at the first
  /// upload (`photosComplete = photoCount > 0`, the registration-minimum
  /// bar), but this card is asking for a *strong* profile, not a minimum one
  /// — so it keeps nudging up to [kMaxPhotos], read live off
  /// [myPhotosProvider] rather than the backend's binary flag. Both signals
  /// are real backend data; they just answer different questions.
  List<_HomeCompletionItem> _items(
    BuildContext context,
    WidgetRef ref,
    List<CompletionRecommendation> recommendations,
  ) {
    final l10n = AppLocalizations.of(context);
    final photos = ref.watch(myPhotosProvider).valueOrNull;

    _HomeCompletionItem tile(String key, int wizardStep) => _HomeCompletionItem(
      key: key,
      icon: completionCardIcon(key),
      label: completeProfileTileLabel(l10n, key),
      onTap: () => _open(context, ref, wizardStep: wizardStep),
    );

    return [
      if (photos != null && photos.length < kMaxPhotos)
        tile(CompletionCardKeys.photo, _wizardStepPhotos),
      if (!_isComplete(recommendations, CompletionCardKeys.aboutFamily))
        tile(CompletionCardKeys.aboutFamily, _wizardStepFamily),
      if (!_isComplete(recommendations, CompletionCardKeys.horoscope))
        tile(CompletionCardKeys.horoscope, _wizardStepHoroscope),
      if (!_isComplete(recommendations, CompletionCardKeys.psychology))
        tile(CompletionCardKeys.psychology, _wizardStepPsychology),
      if (!_isComplete(recommendations, CompletionCardKeys.partnerPreference))
        tile(
          CompletionCardKeys.partnerPreference,
          _wizardStepPartnerPreference,
        ),
      if (!_isComplete(recommendations, CompletionCardKeys.verification))
        tile(CompletionCardKeys.verification, _wizardStepVerification),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(completeProfileCardDismissedProvider)) {
      return const SizedBox.shrink();
    }

    final completeness = ref
        .watch(profileCompletenessSnapshotProvider)
        .valueOrNull;
    if (completeness == null) return const SizedBox.shrink();

    final items = _items(context, ref, completeness.recommendations);
    if (items.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: Container(
        width: double.infinity,
        // A compact inline nudge between the stories and AI Recommended,
        // not a section of its own — deliberately tighter than the app's
        // usual card padding (AppSpacing.base), which pushed the feed a
        // near-screenful down.
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: AppDecorations.card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.homeCompleteProfileTitle,
                        style: AppTypography.labelLarge.copyWith(
                          color: AppColors.textPrimaryLight,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs2),
                      Text(
                        l10n.homeCompleteProfileSubtitle,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textSecondaryLight,
                          fontWeight: FontWeight.w400,
                        ),
                        // Fits one line in English at this size; the second
                        // is headroom for Tamil and a large text scale
                        // rather than an expected wrap.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Semantics(
                  button: true,
                  label: l10n.homeCompleteProfileDismissTooltip,
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 15,
                      visualDensity: VisualDensity.compact,
                      tooltip: l10n.homeCompleteProfileDismissTooltip,
                      onPressed: () =>
                          ref
                                  .read(
                                    completeProfileCardDismissedProvider
                                        .notifier,
                                  )
                                  .state =
                              true,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textTertiaryLight,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            // Horizontally scrollable rather than Expanded: up to six tiles
            // (Photos + five sections) no longer reliably fit one phone
            // width without cramming, and the card must stay this short
            // regardless of how many tiles there are — a taller card was
            // exactly what made the first version feel like a section
            // rather than a nudge.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.xs),
                    _CompleteProfileTile(
                      key: ValueKey('home-complete-profile-${items[i].key}'),
                      item: items[i],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the section behind a tile and, on return, re-reads completion —
  /// the same round trip `CompleteProfileSection._open` uses, so a section
  /// finished from either card disappears from both. Photos needs no
  /// matching refresh call: [myPhotosProvider] is updated directly by
  /// [PhotosController] the moment a photo is added or removed, so this
  /// card already has the live count by the time the member returns.
  static Future<void> _open(
    BuildContext context,
    WidgetRef ref, {
    required int wizardStep,
  }) async {
    await openEditProfile(context, ref, wizardStep: wizardStep);
    if (!context.mounted) return;
    refreshProfileCompletion(ref);
  }
}

/// One tile — icon, title, tap. No card border of its own (the row shares
/// [CompleteProfileCard]'s single outer card) and no per-tile dismiss: this
/// card is closed as a whole (see [completeProfileCardDismissedProvider]),
/// never one section at a time.
class _CompleteProfileTile extends StatelessWidget {
  final _HomeCompletionItem item;

  const _CompleteProfileTile({super.key, required this.item});

  /// Fixed rather than [Expanded]: the row now scrolls, so each tile keeps
  /// its own natural width instead of splitting whatever space is left.
  /// Wide enough that the longest English word on any tile ("Preferences")
  /// fits one line at this label size — at 72 it was ellipsized.
  static const double _width = 84;

  @override
  Widget build(BuildContext context) {
    final tint = completionCardTint(item.key);
    final tintSurface = completionCardTintSurface(item.key);

    return SizedBox(
      width: _width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: tintSurface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(item.icon, color: tint, size: 17),
                ),
                const SizedBox(height: AppSpacing.xs2),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textPrimaryLight,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
