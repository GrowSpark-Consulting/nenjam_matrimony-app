import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../core/widgets/feedback/loading_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../../profile/presentation/widgets/partner_preference_card.dart';
import '../../../profile_views/presentation/providers/profile_views_provider.dart';
import '../../domain/entities/profile_detail_entity.dart';
import '../providers/profile_detail_providers.dart';
import '../widgets/about_section.dart';
import '../widgets/basic_information_section.dart';
import '../widgets/compatibility_card_section.dart';
import '../widgets/family_info_section.dart';
import '../widgets/horoscope_section.dart';
import '../widgets/lifestyle_section.dart';
import '../widgets/profile_detail_hero_app_bar.dart';
import '../widgets/profile_detail_section_tab_bar.dart';
import '../widgets/profile_detail_bottom_action_bar.dart';
import '../widgets/profile_photo_gallery_section.dart';
import '../widgets/similar_profiles_section.dart';
import '../widgets/verification_section.dart';

/// Read-only detail view of another member's profile — opened by tapping
/// a profile card from Discover, Matches, Search, or Similar Profiles.
class ProfileDetailPage extends ConsumerStatefulWidget {
  final DiscoveryProfileEntity profile;
  /// The exact Hero tag the tapped card used, when it used a scoped one
  /// (Discover/Matches) — see `ProfileDetailArgs`'s doc comment for why.
  /// Null falls back to the plain `'profile-photo-$id'` scheme.
  final String? heroTag;
  /// Whether the caller already knows this member is blocked — see
  /// `ProfileDetailArgs.isBlocked`'s doc comment.
  ///
  /// Currently unread: the hero's "More" menu, the only thing that branched
  /// on it, was removed along with the rest of the hero controls. Kept on the
  /// constructor because the route still supplies it and the block/unblock
  /// affordance is expected back on this page later.
  final bool isBlocked;

  const ProfileDetailPage({
    super.key,
    required this.profile,
    this.heroTag,
    this.isBlocked = false,
  });

  @override
  ConsumerState<ProfileDetailPage> createState() => _ProfileDetailPageState();
}

class _ProfileDetailPageState extends ConsumerState<ProfileDetailPage> {
  @override
  void initState() {
    super.initState();
    // Opening someone's profile is what "viewed" means — this is the single
    // place the app records it, so every entry point (Discover, Matches,
    // Search, Similar Profiles, a notification tap) is counted exactly once
    // per open. Best-effort and fire-and-forget: `recordProfileView` never
    // throws, and the server itself throttles how often a view turns into a
    // notification for the viewed member.
    unawaited(recordProfileView(ref, widget.profile.id));
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final heroTag = widget.heroTag;
    final detailAsync = ref.watch(profileDetailProvider(profile));

    // Still no `bottomNavigationBar:`. Send Interest and Message are back on
    // this page, but as a bar that floats over the content and only appears
    // once the hero has scrolled away (see _syncActionBar) — so the
    // photograph still gets the whole first screen, and the body still runs
    // edge to edge because nothing permanently reserves space below it.
    return Scaffold(
      body: detailAsync.when(
        data: (detail) => _ProfileDetailScrollView(
          detail: detail,
          heroTag: heroTag,
        ),
        loading: () => const NmLoadingWidget(),
        error: (_, __) => NmErrorWidget(
          onRetry: () => ref.invalidate(profileDetailProvider(profile)),
        ),
      ),
    );
  }
}

/// One long, naturally-scrolling profile:
///
/// full-screen hero photo → about → basic information → photo gallery →
/// section navigation → family → lifestyle → horoscope → compatibility →
/// preferences → verification → similar profiles.
///
/// The hero occupies the entire first viewport, and the member's identity
/// (name/age, profession, and the short profile chips) is overlaid across
/// the bottom of the photo — so the first thing a swipe reveals is the About
/// card, not a card repeating what was still on screen a moment ago.
///
/// The section navigation deliberately sits *between* the two content
/// slivers rather than directly under the hero: everything above it (who
/// this person is, and their photos) is meant to be discovered by scrolling,
/// and only the deeper sections below it are worth jumping to. Being a
/// pinned sliver at that position means it scrolls up with the content and
/// only sticks once the reader has actually reached it.
class _ProfileDetailScrollView extends StatefulWidget {
  final ProfileDetailEntity detail;
  final String? heroTag;

  const _ProfileDetailScrollView({required this.detail, this.heroTag});

  @override
  State<_ProfileDetailScrollView> createState() => _ProfileDetailScrollViewState();
}

class _ProfileDetailScrollViewState extends State<_ProfileDetailScrollView> {
  /// Only the sections that live *below* the navigation are addressable by
  /// it — About and Photos are above it and can no longer be scrolled "to".
  static const _sectionCount = 6;

  final _sectionKeys = List.generate(_sectionCount, (_) => GlobalKey());
  // One key per tab label, mirroring _sectionKeys — lets the active tab's
  // RenderObject be found so it can be centered within the tab bar's own
  // horizontal scroll (see _revealActiveTab) instead of a hardcoded pixel
  // offset.
  final _tabKeys = List.generate(_sectionCount, (_) => GlobalKey());
  final _scrollController = ScrollController();
  // Owned separately from _scrollController so _revealActiveTab can target
  // *only* the tab bar's own horizontal ScrollPosition directly — see that
  // method's doc comment for why the static Scrollable.ensureVisible()
  // helper is deliberately not used here.
  final _tabBarScrollController = ScrollController();
  int _selectedTab = 0;

  // While a tab tap is driving a programmatic scroll, the scroll listener
  // below would otherwise see every section it flies past and thrash
  // _selectedTab through each one before landing on the tapped target —
  // this suppresses that until the programmatic scroll finishes, so manual
  // scrolling is still the only thing driving the sync the rest of the time.
  bool _isProgrammaticScroll = false;

  /// How far the page may move before the "more below" cue is dismissed.
  /// Small enough that any deliberate swipe clears it immediately, large
  /// enough that an overscroll bounce at the top doesn't flicker it.
  static const double _scrollCueDismissThreshold = 8.0;

  bool _showScrollCue = true;

  /// How far down the first viewport the reader must be before the bottom
  /// action bar appears, as a fraction of that viewport.
  ///
  /// The hero is a full-viewport photo with the member's name, age and
  /// profession overlaid across its lower edge. A bar pinned there from the
  /// start would sit on top of exactly that — which is why this page carried
  /// no fixed bar at all. Holding it back until the hero has largely scrolled
  /// away keeps the first screen purely photographic and still puts Interest
  /// and Message within reach the moment the reader is actually reading.
  static const double _actionBarRevealFraction = 0.6;

  /// Dead zone below the reveal point, so a scroll that comes to rest right
  /// on the threshold cannot flicker the bar in and out.
  static const double _actionBarHideMargin = 40.0;

  bool _showActionBar = false;

  /// The current viewport height, published by the [LayoutBuilder] in
  /// [build]. The scroll listener runs outside any build, so it cannot read
  /// constraints itself.
  double _viewportHeight = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncActiveTabWithScroll);
    _scrollController.addListener(_syncScrollCue);
    _scrollController.addListener(_syncActionBar);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncActiveTabWithScroll);
    _scrollController.removeListener(_syncScrollCue);
    _scrollController.removeListener(_syncActionBar);
    _scrollController.dispose();
    _tabBarScrollController.dispose();
    super.dispose();
  }

  // The cue has done its job the moment the page moves, so it fades out and
  // stays gone for the rest of the profile — and comes back only on a full
  // return to the top.
  //
  // Deliberately a second listener on the *same* controller rather than a
  // branch inside _syncActiveTabWithScroll: that one suppresses itself while
  // a tab tap drives a programmatic scroll, and the cue must clear then too.
  void _syncScrollCue() {
    if (!mounted || !_scrollController.hasClients) return;
    final shouldShow =
        _scrollController.position.pixels <= _scrollCueDismissThreshold;
    if (shouldShow != _showScrollCue) {
      setState(() => _showScrollCue = shouldShow);
    }
  }

  // Reveals the Interest/Message bar once the hero has scrolled away, and
  // hides it again on the way back up to the photo.
  //
  // A third listener on the same controller, for the same reason _syncScrollCue
  // is a second one: this must also run while a tab tap is driving a
  // programmatic scroll, which _syncActiveTabWithScroll deliberately suppresses
  // itself during.
  void _syncActionBar() {
    if (!mounted || !_scrollController.hasClients || _viewportHeight <= 0) {
      return;
    }
    final pixels = _scrollController.position.pixels;
    final revealAt = _viewportHeight * _actionBarRevealFraction;
    final shouldShow = _showActionBar
        ? pixels > revealAt - _actionBarHideMargin
        : pixels > revealAt;
    if (shouldShow != _showActionBar) {
      setState(() => _showActionBar = shouldShow);
    }
  }

  List<String> _tabLabels(AppLocalizations l10n) => [
        l10n.profileDetailTabFamily,
        l10n.profileDetailTabLifestyle,
        l10n.profileDetailTabHoroscope,
        l10n.profileDetailTabCompatibility,
        l10n.profileDetailTabPreferences,
        l10n.profileDetailTabVerification,
      ];

  Future<void> _scrollToSection(int index) async {
    setState(() => _selectedTab = index);
    _isProgrammaticScroll = true;
    try {
      await _revealSection(index);
      _revealActiveTab(index);
    } finally {
      if (mounted) _isProgrammaticScroll = false;
    }
  }

  /// Scrolls the page to section [index], building that section first when
  /// it is not currently mounted.
  ///
  /// The sections live in a [SliverList], so only the handful near the
  /// viewport exist as elements at any moment — every other section's
  /// [GlobalKey] has a null `currentContext`, and [Scrollable.ensureVisible]
  /// has nothing to aim at. This used to be a bare `if (context != null)`
  /// around the ensureVisible call, which meant tapping *any* tab whose
  /// section was off screen silently did nothing at all: only the section
  /// mounted at rest ever worked. Walk the viewport towards the target in
  /// bounded steps until the sliver builds it, then hand off to
  /// ensureVisible for the final, correctly-aligned landing.
  ///
  /// The walk is deliberately driven through [_scrollController] — the page's
  /// own vertical position — so it can never be confused with the tab bar's
  /// separate horizontal controller.
  Future<void> _revealSection(int index) async {
    const maxSteps = 40;
    for (var step = 0; step <= maxSteps; step++) {
      final sectionContext = _sectionKeys[index].currentContext;
      // `mounted` guards the context itself, not just this State: a step
      // below may have scrolled the section that was found on the previous
      // iteration back out of the tree.
      if (sectionContext != null && sectionContext.mounted) {
        await Scrollable.ensureVisible(
          sectionContext,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: 0.05,
        );
        return;
      }
      if (!mounted || !_scrollController.hasClients) return;

      final position = _scrollController.position;
      final delta =
          position.viewportDimension * 0.8 * _directionToSection(index);
      final target = (position.pixels + delta)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      // Already pinned against that end of the list — stepping again would
      // spin without ever building anything new.
      if ((target - position.pixels).abs() < 1.0) return;
      position.jumpTo(target);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// +1 when section [index] sits below everything currently mounted, -1 when
  /// it sits above. A [SliverList] only ever mounts a contiguous run of
  /// children, so comparing against that run's bounds is enough to know which
  /// way the target lies.
  int _directionToSection(int index) {
    int? lowest;
    int? highest;
    for (var i = 0; i < _sectionKeys.length; i++) {
      if (_sectionKeys[i].currentContext == null) continue;
      lowest ??= i;
      highest = i;
    }
    if (highest == null) return 1;
    if (index < lowest!) return -1;
    return 1;
  }

  // Centers the active tab within the tab bar's own horizontal scroll.
  //
  // Deliberately calls ScrollPosition.ensureVisible() on _tabBarScrollController
  // directly rather than the static Scrollable.ensureVisible() helper this
  // used to call on `tabContext`. That helper walks *every* ancestor
  // Scrollable, not just the nearest one (see its doc comment/source in
  // package:flutter/src/widgets/scrollable.dart) — specifically so a target
  // nested several scroll views deep gets revealed in all of them. But the
  // tab bar lives inside a pinned SliverPersistentHeader, and pinned slivers
  // are trivially "already visible" to the outer scrollable, so the walk's
  // "already visible → align the outer object itself" fallback (see
  // ScrollPosition.ensureVisible's doc comment) handed the outer *vertical*
  // CustomScrollView a request to align the pinned tab bar container at
  // alignment 0.5 — which a pinned sliver's RevealedOffset geometry resolves
  // to 0. Net effect: every time the active tab changed while the user was
  // manually scrolling (_syncActiveTabWithScroll below), the whole page
  // silently snapped back to the top. Targeting this one ScrollPosition
  // directly reproduces the exact same "center the tab" math (it's the same
  // getOffsetToReveal/animateTo call ensureVisible makes internally) without
  // ever consulting an ancestor Scrollable.
  void _revealActiveTab(int index) {
    if (!_tabBarScrollController.hasClients) return;
    final tabRenderObject = _tabKeys[index].currentContext?.findRenderObject();
    if (tabRenderObject == null) return;
    _tabBarScrollController.position.ensureVisible(
      tabRenderObject,
      alignment: 0.5,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  // Scrollspy for the other direction: as the user scrolls the page by
  // hand, whichever section's top edge has crossed up past the pinned
  // header stack (collapsed hero + tab bar) becomes the active tab. Reads
  // actual on-screen section positions via their GlobalKeys rather than
  // any assumed/measured content height, so it stays correct regardless of
  // photo count, text wrapping, or missing/loading data.
  void _syncActiveTabWithScroll() {
    if (_isProgrammaticScroll || !mounted) return;

    // The hero's toolbar collapses to zero height (it holds nothing), so the
    // pinned header stack above a section is just the status bar strip plus
    // the tab bar itself.
    final activationLine = MediaQuery.paddingOf(context).top +
        ProfileDetailSectionTabBar.height;

    var activeIndex = 0;
    for (var i = 0; i < _sectionKeys.length; i++) {
      final renderObject = _sectionKeys[i].currentContext?.findRenderObject();
      if (renderObject is! RenderBox) continue;
      final sectionTop = renderObject.localToGlobal(Offset.zero).dy;
      if (sectionTop <= activationLine) {
        activeIndex = i;
      } else {
        break;
      }
    }

    if (activeIndex != _selectedTab) {
      setState(() => _selectedTab = activeIndex);
      _revealActiveTab(activeIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder rather than MediaQuery: this measures the scroll view's
    // own box, so the hero can be exactly the first screenful of *content*
    // on every phone size rather than the raw screen height.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Published for _syncActionBar, which runs outside build and so has
        // no constraints of its own to measure the hero against.
        _viewportHeight = constraints.maxHeight;

        return Stack(
          children: [
            _buildScrollView(
              context,
              viewportHeight: constraints.maxHeight,
              viewportWidth: constraints.maxWidth,
            ),

            // Floats over the content rather than taking a
            // Scaffold.bottomNavigationBar slot: the hero is meant to run
            // full-bleed to the bottom of the first viewport, which a real
            // bottom-nav slot would permanently shorten. The scroll view
            // reserves matching padding at its end so the last card still
            // clears the bar — see the final SliverPadding.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                // Off-screen but still in the tree during the slide, so it
                // must not swallow taps aimed at the content behind it.
                ignoring: !_showActionBar,
                child: AnimatedSlide(
                  offset: _showActionBar ? Offset.zero : const Offset(0, 1),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _showActionBar ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: ProfileDetailBottomActionBar(detail: widget.detail),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildScrollView(
    BuildContext context, {
    required double viewportHeight,
    required double viewportWidth,
  }) {
    final l10n = AppLocalizations.of(context);
    final detail = widget.detail;
    final base = detail.base;

    // The hero already shows photo #1 full-bleed at the top of the page, so
    // the gallery below is specifically "their *other* photos".
    final additionalPhotos =
        base.photoUrls.isEmpty ? const <String>[] : base.photoUrls.sublist(1);

    // Keeps the single vertical scroll column from stretching across a wide
    // window. The content slivers are inset rather than the scroll view being
    // narrowed, so the hero stays full-bleed, the tab bar stays pinned, and
    // the section keys `_revealSection` walks to are untouched.
    final contentWidth = NmContentWidth.usableWidth(
      availableWidth: viewportWidth,
      horizontalPadding: AppSpacing.base * 2,
      maxWidth: ContentWidth.detail,
    );
    final sideInset = viewportWidth.isFinite
        ? (viewportWidth - contentWidth) / 2
        : AppSpacing.base;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        ProfileDetailHeroAppBar(
          detail: detail,
          heroTag: widget.heroTag,
          heroHeight: viewportHeight,
          showScrollCue: _showScrollCue,
        ),

        // ── About and the details behind it, then their photos ───────
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            sideInset,
            AppSpacing.base,
            sideInset,
            AppSpacing.md,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              AboutSection(detail: detail),
              const SizedBox(height: AppSpacing.md),
              BasicInformationSection(detail: detail),
              const SizedBox(height: AppSpacing.md),
              ProfilePhotoGallerySection(photoUrls: additionalPhotos),
            ]),
          ),
        ),

        // ── Jump-to navigation for everything below ──────────────────
        SliverPersistentHeader(
          pinned: true,
          delegate: ProfileDetailTabBarDelegate(
            // The bar carries its own horizontal padding, so it spans the
            // content plus that padding to keep its first tab aligned with
            // the content's left edge.
            child: NmContentWidth(
              maxWidth: contentWidth + AppSpacing.base * 2,
              child: ProfileDetailSectionTabBar(
                controller: _tabBarScrollController,
                labels: _tabLabels(l10n),
                itemKeys: _tabKeys,
                selectedIndex: _selectedTab,
                onTap: _scrollToSection,
              ),
            ),
          ),
        ),

        // ── The deeper sections ──────────────────────────────────────
        SliverPadding(
          // Room for the floating action bar at the end of the list, so the
          // last card is never left underneath it once it appears.
          // `reservedHeight` already folds in the device's bottom inset.
          padding: EdgeInsets.fromLTRB(
            sideInset,
            AppSpacing.md,
            sideInset,
            AppSpacing.base +
                ProfileDetailBottomActionBar.reservedHeight(context),
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              KeyedSubtree(
                key: _sectionKeys[0],
                child: FamilyInfoSection(family: detail.family),
              ),
              const SizedBox(height: AppSpacing.md),
              KeyedSubtree(
                key: _sectionKeys[1],
                child: LifestyleSection(lifestyle: detail.lifestyle),
              ),
              const SizedBox(height: AppSpacing.md),
              KeyedSubtree(
                key: _sectionKeys[2],
                child: HoroscopeSection(detail: detail),
              ),
              const SizedBox(height: AppSpacing.md),
              KeyedSubtree(
                key: _sectionKeys[3],
                child: CompatibilityCardSection(detail: detail),
              ),
              const SizedBox(height: AppSpacing.md),
              KeyedSubtree(
                key: _sectionKeys[4],
                child: NmPartnerPreferenceCard(
                  preferences: _preferenceRows(detail, l10n),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              KeyedSubtree(
                key: _sectionKeys[5],
                child: VerificationSection(detail: detail),
              ),
              const SizedBox(height: AppSpacing.md),
              SimilarProfilesSection(baseProfile: base),
            ]),
          ),
        ),
      ],
    );
  }

  List<NmPreferenceRow> _preferenceRows(
    ProfileDetailEntity detail,
    AppLocalizations l10n,
  ) {
    final prefs = detail.partnerPreferences;
    return [
      if (prefs.preferredAgeRange.isNotEmpty)
        NmPreferenceRow(label: l10n.fieldAgeRange, value: prefs.preferredAgeRange),
      if (prefs.preferredHeightRange.isNotEmpty)
        NmPreferenceRow(label: l10n.fieldHeight, value: prefs.preferredHeightRange),
      if (prefs.educationPref.isNotEmpty)
        NmPreferenceRow(label: l10n.fieldEducation, value: prefs.educationPref),
      if (prefs.occupationPref.isNotEmpty)
        NmPreferenceRow(label: l10n.fieldOccupation, value: prefs.occupationPref),
      if (prefs.incomePref.isNotEmpty)
        NmPreferenceRow(label: l10n.fieldIncome, value: prefs.incomePref),
      if (prefs.religionPref.isNotEmpty)
        NmPreferenceRow(label: l10n.fieldReligion, value: prefs.religionPref),
      if (prefs.castePref.isNotEmpty)
        NmPreferenceRow(label: l10n.fieldCaste, value: prefs.castePref),
      if (prefs.motherTonguePref.isNotEmpty)
        NmPreferenceRow(label: l10n.fieldMotherTongue, value: prefs.motherTonguePref),
      if (prefs.locationPref.isNotEmpty)
        NmPreferenceRow(label: l10n.fieldLocation, value: prefs.locationPref),
      if (prefs.maritalStatusPref.isNotEmpty)
        NmPreferenceRow(label: l10n.fieldMaritalStatus, value: prefs.maritalStatusPref),
    ];
  }
}
