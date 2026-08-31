import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/cards/profile_hero_content.dart';
import '../../domain/entities/profile_detail_entity.dart';

/// Full-bleed collapsing hero for the Profile Detail page.
///
/// Renders the member's photo, scrim and identity block with
/// [NmProfileHeroPhoto], [NmProfileHeroScrim] and [NmProfileHeroInfo] — the
/// same three widgets the Matches reel card is built from, so the two screens
/// show a profile identically by construction rather than by two teams
/// agreeing on numbers. Everything specific to this screen lives here: the
/// sliver, the viewport-height sizing, and the bottom inset.
///
/// Deliberately carries **no controls at all**. It used to own a back button,
/// a shortlist toggle, share, and a "More" (block/report) menu, plus a bottom
/// action bar for Send Interest and Chat; Matches' own right-hand action
/// column is likewise not borrowed along with its presentation. Every one of
/// those actions still exists on the feeds this page is opened from
/// (Discover, Matches, Search). Back is left to the platform: the Android
/// system back gesture/button and the iOS edge swipe both pop this route
/// without anything being drawn for them.
class ProfileDetailHeroAppBar extends StatelessWidget {
  final ProfileDetailEntity detail;

  /// The scoped Hero tag the tapped card used (Discover/Matches), when
  /// applicable — see `ProfileDetailArgs`'s doc comment for why those two
  /// screens need a scoped tag instead of the plain `'profile-photo-$id'`
  /// one. Null falls back to that plain scheme (Search/Similar
  /// Profiles/Shortlisted, or a direct/deep link).
  final String? heroTag;

  /// Height the expanded hero should occupy — the page passes its scroll
  /// viewport's own height (measured with a [LayoutBuilder]) so the photo
  /// fills exactly the first screenful on every device size.
  ///
  /// Null falls back to a measurement from [MediaQuery] for any caller that
  /// isn't inside such a [LayoutBuilder].
  final double? heroHeight;

  /// Whether the "there is more below" chevron is showing.
  ///
  /// Driven by the page's existing scroll position: true only while the page
  /// is at (or within a few pixels of) the top. The cue stays in the tree
  /// either way and fades, so revealing it can never shift the identity block
  /// underneath it.
  final bool showScrollCue;

  const ProfileDetailHeroAppBar({
    super.key,
    required this.detail,
    this.heroTag,
    this.heroHeight,
    this.showScrollCue = false,
  });

  @override
  Widget build(BuildContext context) {
    final base = detail.base;
    final effectiveHeroTag = heroTag ?? 'profile-photo-${base.id}';

    // The photo *is* the first screen, so the hero should end up exactly as
    // tall as the scroll viewport the page measured for it.
    //
    // Note what SliverAppBar does with this number: with primary: true its
    // delegate reports `maxExtent = topPadding + expandedHeight`, adding the
    // status-bar inset on top of whatever is passed. Handing it the whole
    // viewport therefore built a box a status bar TALLER than the screen,
    // and since the identity block is bottom-aligned inside that box, the
    // bottom of it — the last row of chips — was laid out below the
    // viewport and clipped. Subtracting the inset here is what makes
    // maxExtent come back out as the viewport height exactly.
    //
    // Only the top inset: the hero deliberately runs to the physical bottom
    // of the screen, and the overlay's own SafeArea holds its text clear of
    // the system navigation bar.
    final mediaQuery = MediaQuery.of(context);
    final viewportHeight = heroHeight ?? mediaQuery.size.height;
    final expandedHeight = (viewportHeight - mediaQuery.padding.top)
        .clamp(280.0, double.infinity);

    return SliverAppBar(
      expandedHeight: expandedHeight,
      pinned: true,
      stretch: true,
      // Nothing is drawn in the toolbar any more, so it collapses to just the
      // status-bar strip rather than an empty 56px plum bar. Keeping it
      // pinned at that height is what stops the section navigation below from
      // pinning underneath the status bar.
      toolbarHeight: 0,
      automaticallyImplyLeading: false,
      backgroundColor: AppColors.primary,
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: effectiveHeroTag,
              child: NmProfileHeroPhoto(
                photoUrls: base.photoUrls,
                gender: base.gender,
              ),
            ),
            const NmProfileHeroScrim(),
            // The reel card's own overlay, with the two things that are
            // properties of *that* screen rather than of the design turned
            // off: there is no action column here to keep clear, so the
            // block takes the full width, and the name gets room to wrap
            // rather than ellipsizing — on the screen devoted to one person,
            // seeing their whole name matters more than a tidy single line.
            // Three lines is past any real name at this width (the longest
            // in the seed data takes two), so the cap is only a guard against
            // pathological input rather than something users meet.
            NmProfileHeroOverlay(
              profile: base,
              reserveActionColumn: false,
              nameMaxLines: 3,
              // Read out here, above the SliverAppBar: it strips the bottom
              // padding from its header's MediaQuery, so nothing inside the
              // flexible space can see the system navigation bar on its own.
              bottomInset: mediaQuery.padding.bottom,
              // In the overlay's own column rather than free-floating in the
              // Stack, so it can never land on the name or the chips however
              // long they run.
              above: _ScrollDiscoveryCue(visible: showScrollCue),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pair of softly drifting chevrons: the whole of the "this page continues
/// below" affordance.
///
/// The first viewport is a photograph with no other UI on it, which is the
/// look that was asked for but gives a first-time reader nothing to suggest
/// About is a swipe away. Deliberately wordless and low-contrast — an
/// instruction banner would undo the point of a clean hero.
class _ScrollDiscoveryCue extends StatefulWidget {
  final bool visible;

  const _ScrollDiscoveryCue({required this.visible});

  @override
  State<_ScrollDiscoveryCue> createState() => _ScrollDiscoveryCueState();
}

class _ScrollDiscoveryCueState extends State<_ScrollDiscoveryCue>
    with SingleTickerProviderStateMixin {
  /// Small enough to read as a drift rather than a bounce.
  static const double _travel = 7;
  static const Duration _fade = Duration(milliseconds: 260);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  late final Animation<double> _drift = Tween<double>(
    begin: 0,
    end: _travel,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    if (widget.visible) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_ScrollDiscoveryCue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    // Idle rather than spinning invisibly once the reader has scrolled past.
    if (widget.visible) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: _fade,
        curve: Curves.easeOut,
        child: Center(
          child: AnimatedBuilder(
            animation: _drift,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _drift.value),
              child: child,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Chevron(alpha: 0.75),
                // Pulled up so the two read as one double-chevron rather than
                // as two separate arrows; a negative SizedBox is not a thing.
                Transform.translate(
                  offset: const Offset(0, -12),
                  child: const _Chevron(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  final double alpha;

  const _Chevron({required this.alpha});

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.keyboard_arrow_down_rounded,
      size: 26,
      color: Colors.white.withValues(alpha: alpha),
      // The scrim is weakest this far up the photo, so the cue carries its
      // own shadow to stay legible over a bright one.
      shadows: const [Shadow(blurRadius: 8, color: Colors.black45)],
    );
  }
}
