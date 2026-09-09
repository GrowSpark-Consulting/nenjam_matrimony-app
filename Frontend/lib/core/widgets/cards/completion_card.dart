import 'package:flutter/material.dart';

import '../../constants/app_spacing.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';

/// One compact "Complete Your Profile" recommendation — a tinted icon tile, a
/// short title beneath it, and a dismiss cross.
///
/// Roughly square and deliberately sparse: this is a nudge sitting beside
/// four others in a scrolling row, not a section of its own. Anything longer
/// than the title (the reason the section matters, its completion state)
/// would double the card's height for information the member gets by tapping
/// it, so the fuller description rides along as the semantics label instead —
/// screen readers hear it, the layout doesn't pay for it.
///
/// Presentational only: it neither knows what a card means nor decides
/// whether it belongs here. Visibility is the server's call (see
/// `visibleRecommendations`); this takes the copy it is given and reports the
/// two gestures back.
class NmCompletionCard extends StatelessWidget {
  final IconData icon;

  /// Short label under the icon — "Add photo(s)", "Family Details". Two lines
  /// at most; longer localized strings ellipsize rather than making one card
  /// taller than its neighbours.
  final String title;

  /// The fuller "why". Not painted — see the class comment — but spoken as
  /// part of the card's semantics label.
  final String description;

  /// Tiny label under the title, for the one thing a member can't infer:
  /// that a card is optional. Empty for every scored card, which is most of
  /// them.
  final String badge;

  /// Tint for the icon tile. Always an existing theme color — each card uses
  /// the one its concept is already keyed to elsewhere in the app.
  final Color tint;

  /// The tile's wash behind [tint]. Passed rather than derived so it stays a
  /// real palette token instead of an alpha guess.
  final Color tintSurface;

  /// Opens the page that completes this section. The whole card is the
  /// action — there is no separate button to miss.
  final VoidCallback onTap;

  /// Hides the recommendation. Never deletes anything the member has saved,
  /// which is why it is a cross on the card rather than an action inside it.
  final VoidCallback onDismiss;

  final String dismissTooltip;

  const NmCompletionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.badge,
    required this.tint,
    required this.tintSurface,
    required this.onTap,
    required this.onDismiss,
    required this.dismissTooltip,
  });

  /// Card width. Fits three and a slice of a fourth on a 360dp phone, so the
  /// cut-off card is what tells the member the row scrolls. Height is never
  /// fixed — see [NmCompletionCardRow].
  static const double width = 104;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        // The description the card has no room to paint. Read out after the
        // title, so the spoken card says as much as the old wide one did.
        label: description.isEmpty ? title : '$title. $description',
        child: ExcludeSemantics(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              child: Ink(
                decoration: AppDecorations.card(),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.sm,
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.md,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: tintSurface,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusLg,
                              ),
                            ),
                            child: Icon(icon, color: tint, size: 24),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.textPrimaryLight,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (badge.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              badge,
                              textAlign: TextAlign.center,
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.textTertiaryLight,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Top-right, over the padding rather than inside the
                    // column, so adding it costs the card no height and
                    // never shifts the icon off centre.
                    PositionedDirectional(
                      top: 0,
                      end: 0,
                      child: Semantics(
                        button: true,
                        label: dismissTooltip,
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 14,
                            visualDensity: VisualDensity.compact,
                            tooltip: dismissTooltip,
                            onPressed: onDismiss,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: AppColors.textTertiaryLight,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The horizontally scrolling row the completion cards live in.
///
/// A scroll view wrapping a Row, not a fixed-height `ListView` — the same
/// choice (and the same reason) as Discover's compact profile row: each card
/// sizes itself from its own content, so the row's height becomes the tallest
/// card's natural height. A larger text-scale setting or a longer Tamil
/// string makes the row taller instead of overflowing a guessed box.
///
/// [IntrinsicHeight] is what makes every card match that height, so the one
/// card carrying an "Optional" badge doesn't leave the others short. It is
/// bounded to the handful of cards this row ever holds, never a long list.
class NmCompletionCardRow extends StatelessWidget {
  final List<Widget> cards;

  /// Horizontal padding, so the first and last cards align with the rest of
  /// the page while still scrolling edge to edge.
  final EdgeInsets padding;

  const NmCompletionCardRow({
    super.key,
    required this.cards,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.base),
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: padding,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.md),
              cards[i],
            ],
          ],
        ),
      ),
    );
  }
}
