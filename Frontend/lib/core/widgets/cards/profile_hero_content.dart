import 'package:flutter/material.dart';

import '../../../features/discover/domain/entities/discovery_profile_entity.dart';
import '../../../l10n/app_localizations.dart';
import '../../constants/app_spacing.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_gradients.dart';
import '../../theme/app_typography.dart';
import '../avatars/gender_placeholder.dart';
import '../images/sized_network_photo.dart';

/// The app's single profile-over-photo presentation: full-bleed photo, the
/// top-and-bottom scrim that keeps text legible over it, and the identity
/// block that sits on the bottom of the photo.
///
/// Extracted verbatim from the Matches reel card, which was the only place
/// this treatment existed and is the design reference for it. Matches and
/// Profile Detail now render exactly the same photo, scrim, name, profession
/// and metadata chips from the same code, so the two screens cannot drift
/// apart.
///
/// Presentation only, on purpose. Everything interactive that used to sit
/// next to this in the reel card — the swipe PageView, the right-hand action
/// column (interest/shortlist/share/more), the double-tap heart — stays in
/// Matches. Profile Detail composes these three pieces with nothing else, so
/// it gets the look without inheriting the interaction model or any
/// dependency on Matches state.

/// Full-bleed profile photo, falling back to the branded silhouette when the
/// member has none, the URL fails, or it is still loading.
class NmProfileHeroPhoto extends StatelessWidget {
  final List<String> photoUrls;
  final String gender;

  const NmProfileHeroPhoto({
    super.key,
    required this.photoUrls,
    this.gender = '',
  });

  @override
  Widget build(BuildContext context) {
    if (photoUrls.isEmpty) return _placeholder();
    final url = photoUrls.first;

    if (url.startsWith('http')) {
      return NmSizedNetworkPhoto(
        url: url,
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : _placeholder(),
      );
    }
    return Image.asset(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() => NmGenderPlaceholder(
    gender: gender,
    iconSize: 72,
    backgroundColor: AppColors.primaryDark,
    iconColor: AppColors.primaryLight,
  );
}

/// Dark at the top, clear through the middle, dark at the bottom — so the
/// controls or status bar above and the identity block below both stay
/// readable while the subject's face is left untinted.
class NmProfileHeroScrim extends StatelessWidget {
  const NmProfileHeroScrim({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.photoScrimSoft,
            Colors.transparent,
            AppColors.photoScrimStrong,
          ],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
    );
  }
}

/// [NmProfileHeroInfo] placed on the bottom of a hero photo — the whole
/// positioning strategy, not just the block.
///
/// Shared so both screens get the same style, but the two differ in what
/// space is actually available to them, and copying one screen's constraints
/// onto the other is not the same thing as sharing a design:
///
///  * [reserveActionColumn] — true in the Matches reel, where the right-hand
///    action column needs [actionColumnGutter] of clearance. False in Profile
///    Detail, which has no such column and so gives the block the full width.
///  * [nameMaxLines] — one line in the reel, where a card is glanced at and a
///    long name ellipsizing is fine. Two on Profile Detail, where the name is
///    the point of the screen and truncating it is not acceptable.
///
/// The block is bottom-*aligned* rather than hung off a fixed offset, so it
/// grows upward as the name wraps or the chips take another row and can never
/// be pushed off the bottom of the frame.
///
/// Returns a [Positioned] and must therefore be used directly inside a
/// [Stack].
class NmProfileHeroOverlay extends StatelessWidget {
  final DiscoveryProfileEntity profile;

  /// Whether to keep [actionColumnGutter] clear on the right for an action
  /// column drawn over the same photo.
  final bool reserveActionColumn;

  /// Lines the name may occupy before it has to ellipsize.
  final int nameMaxLines;

  /// Inset to clear below the block, on top of [bottomGap].
  ///
  /// Deliberately passed in rather than read from a [SafeArea] here, because
  /// neither caller can see the value it needs at this point in its tree:
  ///
  ///  * In the Matches reel the card is full-bleed to the physical bottom of
  ///    the screen — the shell's Scaffold sets `extendBody: true` so the
  ///    floating nav pill is drawn OVER it, not above it. The inset to pass is
  ///    the pill's height, which the shell publishes as the page's
  ///    `MediaQuery.padding.bottom`; without it the metadata chips render
  ///    underneath the pill.
  ///  * In Profile Detail the hero also runs to the screen edge and there is a
  ///    system inset to clear — but a [SafeArea] cannot see it: this overlay
  ///    renders inside a [SliverAppBar]'s flexible space, and SliverAppBar
  ///    wraps its header in `MediaQuery.removePadding(removeBottom: true)`, so
  ///    the ambient bottom padding is zero by the time it reaches here. The
  ///    caller reads it from above that boundary and passes it down.
  final double bottomInset;

  /// Optional content stacked directly above the identity block, inside the
  /// same bottom-anchored column.
  ///
  /// Being in the column is the point: it cannot overlap the name, profession
  /// or chips at any screen size or content length, which anchoring it
  /// separately in the [Stack] could not guarantee. Null by default, and when
  /// it is null the tree below is exactly the identity block on its own — so
  /// callers that do not use this slot are unaffected by its existence.
  final Widget? above;

  const NmProfileHeroOverlay({
    super.key,
    required this.profile,
    this.reserveActionColumn = true,
    this.nameMaxLines = 1,
    this.bottomInset = 0,
    this.above,
  });

  /// Gap between the block and the bottom of the safe area.
  static const double bottomGap = 16;

  /// Right-hand space the reel card's action column occupies.
  static const double actionColumnGutter = 80;

  @override
  Widget build(BuildContext context) {
    final info = NmProfileHeroInfo(
      profile: profile,
      nameMaxLines: nameMaxLines,
    );

    // Anchored by its bottom edge with its height left unbounded, so the
    // block grows UPWARD as the name wraps or the chips take another row.
    // Deliberately not Positioned.fill + Align: that bounds the height to the
    // frame, and on a short viewport (landscape, split screen) the column
    // then overflows and paints an error stripe instead of simply running up
    // over the photo.
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomGap + bottomInset,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.base,
          right: AppSpacing.base +
              (reserveActionColumn ? actionColumnGutter : 0),
        ),
        child: above == null
            ? info
            : Column(
                mainAxisSize: MainAxisSize.min,
                // stretch, not start: the identity block is handed a tight
                // width today and its chip Wrap lays out against it, so a
                // loose one here would silently rewrap the chips.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  above!,
                  const SizedBox(height: AppSpacing.xl),
                  info,
                ],
              ),
      ),
    );
  }
}

/// AI-match badge, name and age, profession, and the metadata chips — the
/// block that sits on the bottom of a hero photo.
///
/// The caller positions it; this widget only sizes itself to its content
/// ([MainAxisSize.min]) so it works equally inside a fixed-height reel card
/// and inside a collapsing sliver hero.
class NmProfileHeroInfo extends StatelessWidget {
  final DiscoveryProfileEntity profile;

  /// Lines the name may occupy before it ellipsizes. See
  /// [NmProfileHeroOverlay.nameMaxLines].
  final int nameMaxLines;

  const NmProfileHeroInfo({
    super.key,
    required this.profile,
    this.nameMaxLines = 1,
  });

  /// Cap on the metadata chips. More than this and the block starts eating
  /// the photograph it is supposed to sit on.
  static const int maxChips = 6;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // AI Match badge
        if (profile.compatibility.aiMatchPercent > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: AppGradients.accent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              boxShadow: [
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: 0.4),
                  blurRadius: 15,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 14,
                  color: AppColors.textOnSecondary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${profile.compatibility.aiMatchPercent}% ${l10n.discoverStatMatchLabel}',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textOnSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 12),

        // Name, age
        Text(
          '${profile.name}, ${profile.age}',
          style: AppTypography.displaySmall.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 36,
            height: 1.0,
            shadows: const [Shadow(blurRadius: 12, color: Colors.black54)],
          ),
          maxLines: nameMaxLines,
          // A backstop, not the expected outcome: at two lines and full
          // width this is past any real name, so Profile Detail shows names
          // in full and only a pathological one would ever reach it.
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 4),

        // Profession
        if (profile.profession.isNotEmpty)
          Text(
            profile.profession,
            style: AppTypography.bodyLarge.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
              shadows: const [Shadow(blurRadius: 8, color: Colors.black45)],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

        const SizedBox(height: 12),

        // Glass chip pills
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _chips(
            profile,
          ).map((chip) => _GlassChip(label: chip.$1, icon: chip.$2)).toList(),
        ),
      ],
    );
  }

  List<(String, IconData?)> _chips(DiscoveryProfileEntity p) {
    final chips = <(String, IconData?)>[];
    if (p.location.isNotEmpty) chips.add((p.location, null));
    if (p.height.isNotEmpty) chips.add((p.height, Icons.height_rounded));
    if (p.religion.isNotEmpty) chips.add((p.religion, null));
    if (p.community.isNotEmpty) chips.add((p.community, null));
    if (p.motherTongue.isNotEmpty) {
      chips.add((p.motherTongue, Icons.translate_rounded));
    }
    if (p.education.isNotEmpty) chips.add((p.education, Icons.school_rounded));
    if (p.maritalStatus.isNotEmpty) {
      chips.add((p.maritalStatus, Icons.favorite_border_rounded));
    }
    if (p.diet.isNotEmpty) chips.add((p.diet, Icons.restaurant_rounded));
    return chips.take(maxChips).toList();
  }
}

class _GlassChip extends StatelessWidget {
  final String label;
  final IconData? icon;

  const _GlassChip({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
          ],
          // Flexible, not a bare Text: this Row is mainAxisSize.min inside a
          // Wrap, so without it the chip sizes to its natural width and a
          // long location or degree overflows the row instead of
          // ellipsizing. Latent in the reel card, where the action column
          // narrows the block enough to hide it.
          Flexible(
            child: Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
