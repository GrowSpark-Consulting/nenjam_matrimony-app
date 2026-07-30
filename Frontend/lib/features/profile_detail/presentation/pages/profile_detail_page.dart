import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../core/widgets/feedback/loading_widget.dart';
import '../../../../core/widgets/relationship_intelligence/psychology_section.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../../profile/presentation/widgets/partner_preference_card.dart';
import '../../../profile/presentation/widgets/photo_gallery_card.dart';
import '../../domain/entities/profile_detail_entity.dart';
import '../providers/profile_detail_providers.dart';
import '../widgets/about_section.dart';
import '../widgets/basic_information_section.dart';
import '../widgets/compatibility_card_section.dart';
import '../widgets/family_info_section.dart';
import '../widgets/horoscope_section.dart';
import '../widgets/lifestyle_section.dart';
import '../widgets/profile_detail_bottom_action_bar.dart';
import '../widgets/profile_detail_hero_app_bar.dart';
import '../widgets/profile_detail_section_tab_bar.dart';
import '../widgets/profile_photo_viewer_page.dart';
import '../widgets/similar_profiles_section.dart';
import '../widgets/timeline_section.dart';
import '../widgets/trust_score_card.dart';
import '../widgets/verification_trust_section.dart';

/// Read-only detail view of another member's profile — opened by tapping
/// a profile card from Discover, Matches, Search, or Similar Profiles.
class ProfileDetailPage extends ConsumerWidget {
  final DiscoveryProfileEntity profile;
  /// The exact Hero tag the tapped card used, when it used a scoped one
  /// (Discover/Matches) — see `ProfileDetailArgs`'s doc comment for why.
  /// Null falls back to the plain `'profile-photo-$id'` scheme.
  final String? heroTag;
  /// Whether the caller already knows this member is blocked — see
  /// `ProfileDetailArgs.isBlocked`'s doc comment. Drives whether the hero
  /// app bar's "More" menu offers Block or Unblock.
  final bool isBlocked;

  const ProfileDetailPage({
    super.key,
    required this.profile,
    this.heroTag,
    this.isBlocked = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(profileDetailProvider(profile));

    return Scaffold(
      body: detailAsync.when(
        data: (detail) => _ProfileDetailScrollView(
          detail: detail,
          heroTag: heroTag,
          isBlocked: isBlocked,
        ),
        loading: () => const NmLoadingWidget(),
        error: (_, __) => NmErrorWidget(
          onRetry: () => ref.invalidate(profileDetailProvider(profile)),
        ),
      ),
      bottomNavigationBar: detailAsync.maybeWhen(
        data: (detail) => ProfileDetailBottomActionBar(detail: detail),
        orElse: () => null,
      ),
    );
  }
}

class _ProfileDetailScrollView extends StatefulWidget {
  final ProfileDetailEntity detail;
  final String? heroTag;
  final bool isBlocked;

  const _ProfileDetailScrollView({
    required this.detail,
    this.heroTag,
    this.isBlocked = false,
  });

  @override
  State<_ProfileDetailScrollView> createState() => _ProfileDetailScrollViewState();
}

class _ProfileDetailScrollViewState extends State<_ProfileDetailScrollView> {
  static const _sectionCount = 8;

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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncActiveTabWithScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncActiveTabWithScroll);
    _scrollController.dispose();
    _tabBarScrollController.dispose();
    super.dispose();
  }

  List<String> _tabLabels(AppLocalizations l10n) => [
        l10n.profileDetailTabAbout,
        l10n.profileDetailTabPhotos,
        l10n.profileDetailTabFamily,
        l10n.profileDetailTabLifestyle,
        l10n.profileDetailTabHoroscope,
        l10n.profileDetailTabPreferences,
        l10n.profileDetailTabVerification,
        l10n.profileDetailTabTimeline,
      ];

  Future<void> _scrollToSection(int index) async {
    setState(() => _selectedTab = index);
    _isProgrammaticScroll = true;
    final sectionContext = _sectionKeys[index].currentContext;
    if (sectionContext != null) {
      await Scrollable.ensureVisible(
        sectionContext,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    }
    _revealActiveTab(index);
    if (mounted) _isProgrammaticScroll = false;
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

    final activationLine = kToolbarHeight +
        MediaQuery.paddingOf(context).top +
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
    final l10n = AppLocalizations.of(context);
    final detail = widget.detail;
    final base = detail.base;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        ProfileDetailHeroAppBar(
          detail: detail,
          heroTag: widget.heroTag,
          isBlocked: widget.isBlocked,
        ),
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
        SliverPadding(
          padding: const EdgeInsets.all(AppSpacing.base),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              TrustScoreCard(trust: detail.trustScore),
              const SizedBox(height: AppSpacing.md),
              KeyedSubtree(
                key: _sectionKeys[0],
                child: AboutSection(detail: detail),
              ),
              const SizedBox(height: AppSpacing.md),
              CompatibilityCardSection(detail: detail),
              const SizedBox(height: AppSpacing.md),
              KeyedSubtree(
                key: _sectionKeys[1],
                child: NmPhotoGalleryCard(
                  photoUrls: base.photoUrls,
                  maxPhotos: base.photoUrls.length,
                  onPhotoTap: (index) => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProfilePhotoViewerPage(
                        photoUrls: base.photoUrls,
                        initialIndex: index,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              BasicInformationSection(detail: detail),
              const SizedBox(height: AppSpacing.md),
              KeyedSubtree(
                key: _sectionKeys[2],
                child: FamilyInfoSection(family: detail.family),
              ),
              const SizedBox(height: AppSpacing.md),
              KeyedSubtree(
                key: _sectionKeys[3],
                child: LifestyleSection(lifestyle: detail.lifestyle),
              ),
              if (detail.personality != null) ...[
                const SizedBox(height: AppSpacing.md),
                PsychologySection(result: detail.personality!),
              ],
              const SizedBox(height: AppSpacing.md),
              KeyedSubtree(
                key: _sectionKeys[4],
                child: HoroscopeSection(detail: detail),
              ),
              const SizedBox(height: AppSpacing.md),
              KeyedSubtree(
                key: _sectionKeys[5],
                child: NmPartnerPreferenceCard(
                  preferences: _preferenceRows(detail),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              KeyedSubtree(
                key: _sectionKeys[6],
                child: VerificationTrustSection(detail: detail),
              ),
              const SizedBox(height: AppSpacing.md),
              KeyedSubtree(
                key: _sectionKeys[7],
                child: TimelineSection(events: detail.timeline),
              ),
              const SizedBox(height: AppSpacing.md),
              SimilarProfilesSection(baseProfile: base),
            ]),
          ),
        ),
      ],
    );
  }

  List<NmPreferenceRow> _preferenceRows(ProfileDetailEntity detail) {
    final prefs = detail.partnerPreferences;
    return [
      if (prefs.preferredAgeRange.isNotEmpty)
        NmPreferenceRow(label: 'Age Range', value: prefs.preferredAgeRange),
      if (prefs.preferredHeightRange.isNotEmpty)
        NmPreferenceRow(label: 'Height', value: prefs.preferredHeightRange),
      if (prefs.educationPref.isNotEmpty)
        NmPreferenceRow(label: 'Education', value: prefs.educationPref),
      if (prefs.occupationPref.isNotEmpty)
        NmPreferenceRow(label: 'Occupation', value: prefs.occupationPref),
      if (prefs.incomePref.isNotEmpty)
        NmPreferenceRow(label: 'Income', value: prefs.incomePref),
      if (prefs.religionPref.isNotEmpty)
        NmPreferenceRow(label: 'Religion', value: prefs.religionPref),
      if (prefs.castePref.isNotEmpty)
        NmPreferenceRow(label: 'Caste', value: prefs.castePref),
      if (prefs.motherTonguePref.isNotEmpty)
        NmPreferenceRow(label: 'Mother Tongue', value: prefs.motherTonguePref),
      if (prefs.locationPref.isNotEmpty)
        NmPreferenceRow(label: 'Location', value: prefs.locationPref),
      if (prefs.maritalStatusPref.isNotEmpty)
        NmPreferenceRow(label: 'Marital Status', value: prefs.maritalStatusPref),
    ];
  }
}
