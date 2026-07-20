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

  const ProfileDetailPage({super.key, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(profileDetailProvider(profile));

    return Scaffold(
      body: detailAsync.when(
        data: (detail) => _ProfileDetailScrollView(detail: detail),
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

  const _ProfileDetailScrollView({required this.detail});

  @override
  State<_ProfileDetailScrollView> createState() => _ProfileDetailScrollViewState();
}

class _ProfileDetailScrollViewState extends State<_ProfileDetailScrollView> {
  final _sectionKeys = List.generate(8, (_) => GlobalKey());
  int _selectedTab = 0;

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

  void _scrollToSection(int index) {
    setState(() => _selectedTab = index);
    final context = _sectionKeys[index].currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detail = widget.detail;
    final base = detail.base;

    return CustomScrollView(
      slivers: [
        ProfileDetailHeroAppBar(detail: detail),
        SliverPersistentHeader(
          pinned: true,
          delegate: ProfileDetailTabBarDelegate(
            child: ProfileDetailSectionTabBar(
              labels: _tabLabels(l10n),
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
