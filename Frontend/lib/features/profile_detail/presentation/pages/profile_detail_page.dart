import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../core/widgets/feedback/loading_widget.dart';
import '../../../../core/widgets/relationship_intelligence/psychology_section.dart';
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

    // No `bottomNavigationBar:` — this page shows no fixed action bar at all
    // any more. Send Interest and Chat live on the feeds this page is opened
    // from; here the photograph gets the whole first screen, and the body
    // runs edge to edge because nothing is reserving space below it.
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
/// psychology → preferences → verification → similar profiles.
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncActiveTabWithScroll);
    _scrollController.addListener(_syncScrollCue);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncActiveTabWithScroll);
    _scrollController.removeListener(_syncScrollCue);
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
      builder: (context, constraints) => _buildScrollView(
        context,
        viewportHeight: constraints.maxHeight,
      ),
    );
  }

  Widget _buildScrollView(
    BuildContext context, {
    required double viewportHeight,
  }) {
    final l10n = AppLocalizations.of(context);
    final detail = widget.detail;
    final base = detail.base;

    // The hero already shows photo #1 full-bleed at the top of the page, so
    // the gallery below is specifically "their *other* photos".
    final additionalPhotos =
        base.photoUrls.isEmpty ? const <String>[] : base.photoUrls.sublist(1);

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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.base,
            AppSpacing.base,
            AppSpacing.base,
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
            child: ProfileDetailSectionTabBar(
              controller: _tabBarScrollController,
              labels: _tabLabels(l10n),
              itemKeys: _tabKeys,
              selectedIndex: _selectedTab,
              onTap: _scrollToSection,
            ),
          ),
        ),

        // ── The deeper sections ──────────────────────────────────────
        SliverPadding(
          // The page reserves no bottom bar, so the only thing the list has
          // to clear at its end is the device's own bottom inset.
          padding: EdgeInsets.fromLTRB(
            AppSpacing.base,
            AppSpacing.md,
            AppSpacing.base,
            AppSpacing.base + MediaQuery.paddingOf(context).bottom,
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
              if (detail.personality != null) ...[
                const SizedBox(height: AppSpacing.md),
                PsychologySection(result: detail.personality!),
              ],
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
