import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/relationship_intelligence/horoscope_compatibility_section.dart';
import '../../../../core/widgets/relationship_intelligence/profile_prompt_section.dart';
import '../../../../core/widgets/relationship_intelligence/psychology_section.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../astro/domain/models/compatibility_result.dart';
import '../../../astro/presentation/providers/compatibility_provider.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../../discover/presentation/providers/discover_providers.dart';
import '../../../interests/domain/repositories/interests_repository.dart';
import '../../../interests/presentation/providers/interests_provider.dart';
import '../../../profile_completion/presentation/providers/profile_completeness_provider.dart';
import '../../../partner_preferences/presentation/utils/open_partner_preferences.dart';
import '../../../profile_photos/presentation/providers/photo_providers.dart';
import '../../../profile_completion/presentation/utils/module_copy.dart';
import '../../../profile_prompts/domain/models/prompt_bank_item.dart';
import '../../../profile_prompts/presentation/providers/profile_prompt_provider.dart';
import '../../../psychology/domain/models/personality_result.dart';
import '../../../psychology/presentation/providers/personality_provider.dart';
import '../../../registration/domain/models/profile_draft.dart';
import '../../../registration/presentation/utils/open_edit_profile.dart';
import '../providers/profile_dashboard_providers.dart';
import '../utils/profile_dashboard_mapper.dart';
import '../widgets/account_section.dart';
import '../widgets/activity_stats_card.dart';
import '../widgets/ai_match_coach_card.dart';
import '../widgets/discover_opportunities_card.dart';
import '../widgets/identity_hero_card.dart';
import '../widgets/match_journey_card.dart';
import '../widgets/partner_preference_card.dart';
import '../widgets/photo_gallery_card.dart';
import '../widgets/premium_membership_card.dart';
import '../widgets/profile_performance_card.dart';
import '../widgets/quick_actions_card.dart';
import '../widgets/today_priority_card.dart';
import '../widgets/verification_card.dart';

/// Nenjam Matrimony — Personal Matchmaking HQ
///
/// The redesigned Profile screen is a luxury dashboard comprising 13 sections.
/// All business logic (providers, routes, cubits) is unchanged — this page
/// only reads existing providers/repositories and maps their real data onto
/// the pre-built dashboard widgets. See `profile_dashboard_mapper.dart` for
/// the field-level mapping.
///
/// Layout:
///   1.  Identity Hero
///   2.  Today's Priorities
///   3.  AI Match Coach
///   4.  Match Journey
///   5.  Activity + Performance
///   6.  Discover Opportunities
///   7.  Relationship Intelligence (Horoscope / Personality / Prompts)
///   8.  Verification Center
///   9.  Partner Preferences
///  10.  Photo Gallery
///  11.  Premium Membership
///  12.  Quick Actions
///  13.  Account
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  @override
  void initState() {
    super.initState();
    // The dashboard's data providers (draft, completeness, photos) are kept
    // alive across the app by the always-mounted Discover screen, so without
    // this they'd render a once-loaded, possibly stale snapshot. Forcing a
    // refetch on every open makes the Profile page always reflect the current
    // backend state — the single source of truth — including any edits or
    // photo changes made since the app started.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // One invalidation refreshes the whole dashboard: the shared draft fetch
      // feeds both myProfileDraftProvider (fields) and
      // backendProfileCompletionProvider (%).
      ref.invalidate(profileDraftResponseProvider);
      ref.invalidate(myPhotosProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ── Existing providers — UNCHANGED ─────────────────────────────
    final AsyncValue<HoroscopeSummary> horoscopeAsync = ref.watch(
      myHoroscopeSummaryProvider,
    );
    final AsyncValue<PersonalityResult?> personalityAsync = ref.watch(
      myPersonalityResultProvider,
    );
    final AsyncValue<List<PromptAnswer>> promptsAsync = ref.watch(
      myPromptsProvider,
    );

    // ── Real user/profile data ──────────────────────────────────────
    // `.valueOrNull` (rather than a full `.when(loading:...)` per
    // section) keeps every section's layout identical while loading,
    // partially filled in, or fully complete — mapper functions below
    // supply elegant fallbacks for anything still null.
    final authUser = ref.watch(currentAuthUserProvider);
    final ProfileDraft? draft = ref.watch(myProfileDraftProvider).valueOrNull;
    final completeness = ref.watch(profileCompletenessSnapshotProvider).valueOrNull;
    // Backend-computed completion % — the single source of truth for the
    // figure shown on this screen (hero card + AI coach), so it always matches
    // what the backend calculated rather than a separately recomputed number.
    final completionPct =
        ref.watch(backendProfileCompletionProvider).valueOrNull ??
            completeness?.percentage ??
            0;
    // Single source of truth for photos (PhotoController) — the header hero
    // image and the gallery card below both read this, so the primary photo is
    // identical here and on the Edit Profile screen.
    final photos = ref.watch(myPhotosProvider).valueOrNull ?? const [];
    // Shared derivation (also used by the navigation drawer and Discover app
    // bar avatars) so "what is my current avatar" is computed in one place.
    final primaryPhotoUrl = ref.watch(myPrimaryPhotoUrlProvider);
    final List<DiscoveryProfileEntity> discoverMatches =
        ref.watch(discoverProfilesProvider).valueOrNull ??
        const <DiscoveryProfileEntity>[];

    // Highest-impact-first, per the existing aggregator's own sort order.
    final missingModules = completeness?.missingModules ?? const [];
    const priorityAccentColors = [AppColors.accentGold, AppColors.primary];

    const gap = SizedBox(height: AppSpacing.xl);
    const smallGap = SizedBox(height: AppSpacing.base);

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: _buildAppBar(context, l10n, isDark),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.base,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── 1. Identity Hero ──────────────────────────────
                _FadeInSection(
                  delay: 0,
                  child: NmIdentityHeroCard(
                    name: profileDisplayName(draft, authUser),
                    age: profileDisplayAge(draft),
                    nmId: profileDisplayId(authUser),
                    imageUrl: primaryPhotoUrl,
                    location: profileDisplayLocation(draft),
                    // TODO(backend): no trust-score concept exists yet
                    // anywhere in the app (no entity, no endpoint) —
                    // placeholder until the backend defines one.
                    trustScore: 0,
                    profileCompletion: completionPct,
                    // TODO(backend): no subscription/premium-status
                    // endpoint is wired yet (ApiEndpoints.
                    // subscriptionStatus is unused) — placeholder until
                    // that's implemented.
                    isPremium: false,
                    isVerified: authUser?.isFullyVerified ?? false,
                    faith: profileDisplayFaith(draft),
                    height: profileDisplayHeight(draft),
                    maritalStatus: profileDisplayMaritalStatus(draft),
                    profession: profileDisplayProfession(draft),
                    onEditTap: () => openEditProfile(context, ref),
                  ),
                ),
                gap,

                // ── 2. Today's Priorities ─────────────────────────
                _FadeInSection(
                  delay: 60,
                  child: NmTodayPrioritiesSection(
                    priorities: [
                      for (
                        var i = 0;
                        i < missingModules.length && i < 2;
                        i++
                      )
                        NmPriorityItem(
                          icon: moduleIcon(missingModules[i].module.id),
                          accentColor:
                              priorityAccentColors[i %
                                  priorityAccentColors.length],
                          title: moduleTitle(
                            l10n,
                            missingModules[i].module.id,
                          ),
                          impactLabel: moduleAction(
                            l10n,
                            missingModules[i].module.id,
                          ),
                          onTap: () => openEditProfile(
                            context,
                            ref,
                            wizardStep: missingModules[i].status.wizardStep,
                          ),
                        ),
                    ],
                  ),
                ),
                gap,

                // ── 3. AI Match Coach ─────────────────────────────
                _FadeInSection(
                  delay: 120,
                  child: NmAiMatchCoachCard(
                    headline: completionPct > 0
                        ? 'Your profile is $completionPct% complete'
                        : "Let's build your profile",
                    suggestions: missingModules.isNotEmpty
                        ? [
                            for (final m in missingModules.take(2))
                              moduleAction(l10n, m.module.id),
                          ]
                        : const [
                            'Upload a natural smiling photo',
                            'Expand bio with lifestyle interests',
                          ],
                    onCtaTap: () => openEditProfile(
                      context,
                      ref,
                      wizardStep:
                          completeness?.highestImpactModule?.status.wizardStep,
                    ),
                  ),
                ),
                gap,

                // ── 4. Match Journey ──────────────────────────────
                _FadeInSection(
                  delay: 180,
                  child: NmMatchJourneyCard(
                    currentStep: profileJourneyStep(
                      authUser: authUser,
                      completeness: completeness,
                    ),
                  ),
                ),
                gap,

                // ── 5. Activity + Performance ─────────────────────
                _FadeInSection(
                  delay: 240,
                  child: Column(
                    children: [
                      NmActivityStatsCard(
                        // Interests now reads the real (mock-backed today,
                        // backend-ready) shared Interest state — see
                        // interests_provider.dart. Visitors/Matches still
                        // have no backing data source.
                        interestsReceived: ref
                                .watch(receivedInterestsProvider)
                                .valueOrNull
                                ?.where((r) => r.status == InterestStatus.pending)
                                .length ??
                            0,
                        visitors: 0,
                        matches: 0,
                        onInterestsTap: () =>
                            context.push(RouteNames.interestsReceived),
                        onVisitorsTap: () => context.push(RouteNames.visitors),
                        // Matches is a bottom-nav tab — switch via the
                        // shell's go navigation, not a stacked push.
                        onMatchesTap: () => context.go(RouteNames.matches),
                      ),
                      smallGap,
                      NmProfilePerformanceCard(
                        // Reuses the same completeness score shown in the
                        // hero card and Profile Completion screen — this
                        // is genuinely what "profile strength" means.
                        strengthPct: completionPct,
                        // TODO(backend): no profile-visibility or
                        // response-time analytics exist yet — placeholders
                        // until the backend defines them.
                        visibilityPct: 0,
                        responseTime: '—',
                      ),
                    ],
                  ),
                ),
                gap,

                // ── 6. Discover Opportunities ─────────────────────
                _FadeInSection(
                  delay: 300,
                  child: NmDiscoverOpportunitiesCard(
                    matches: [
                      for (final profile in discoverMatches.take(3))
                        profileDisplayDiscoverMatch(
                          profile,
                          // Discover is a bottom-nav tab — switch via the
                          // shell's go navigation, not a stacked push.
                          onTap: () => context.go(RouteNames.discover),
                        ),
                    ],
                    onViewAllTap: () => context.go(RouteNames.discover),
                  ),
                ),
                gap,

                // ── 7. Relationship Intelligence — EXISTING PROVIDERS ─
                _FadeInSection(
                  delay: 360,
                  child: horoscopeAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (summary) => HoroscopeCompatibilitySection(
                      rasi: summary.rasi,
                      nakshatra: summary.nakshatra,
                      dosham: summary.dosham,
                      matchingEnabled: summary.matchingEnabled,
                    ),
                  ),
                ),
                smallGap,
                _FadeInSection(
                  delay: 380,
                  child: personalityAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (result) => PsychologySection(
                      result: result ?? const PersonalityResult(),
                    ),
                  ),
                ),
                smallGap,
                _FadeInSection(
                  delay: 400,
                  child: promptsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (prompts) => ProfilePromptSection(prompts: prompts),
                  ),
                ),
                gap,

                // ── 8. Verification Center ────────────────────────
                _FadeInSection(
                  delay: 420,
                  child: NmVerificationCard(
                    items: [
                      NmVerificationItem(
                        icon: Icons.phone_iphone_rounded,
                        label: 'Phone',
                        status: (authUser?.phoneVerified ?? false)
                            ? NmVerificationStatus.verified
                            : NmVerificationStatus.incomplete,
                        onTap: () => context.push(RouteNames.verification),
                      ),
                      NmVerificationItem(
                        icon: Icons.mail_rounded,
                        label: 'Email',
                        status: (authUser?.emailVerified ?? false)
                            ? NmVerificationStatus.verified
                            : NmVerificationStatus.incomplete,
                        onTap: () => context.push(RouteNames.verification),
                      ),
                      NmVerificationItem(
                        icon: Icons.badge_rounded,
                        label: 'Gov ID',
                        // TODO(backend): the /verification/status endpoint
                        // is still a stub (see ProfileDraft.
                        // VerificationStatus.fromJson) — this reflects
                        // whatever the draft last echoed, which defaults
                        // to incomplete until that module ships.
                        status: (draft?.verificationStatus.govIdVerified ?? false)
                            ? NmVerificationStatus.verified
                            : NmVerificationStatus.incomplete,
                        onTap: () => context.push(RouteNames.verification),
                      ),
                      NmVerificationItem(
                        icon: Icons.face_rounded,
                        label: 'Face Match',
                        status: (draft?.verificationStatus.faceVerified ?? false)
                            ? NmVerificationStatus.verified
                            : NmVerificationStatus.incomplete,
                        onTap: () => context.push(RouteNames.verification),
                      ),
                    ],
                  ),
                ),
                gap,

                // ── 9. Partner Preferences ────────────────────────
                _FadeInSection(
                  delay: 460,
                  child: NmPartnerPreferenceCard(
                    preferences: profileDisplayPartnerPreferences(
                      draft?.partnerPreference ?? const PartnerPreference(),
                    ),
                    onEditTap: () => openPartnerPreferences(context, ref),
                  ),
                ),
                gap,

                // ── 10. Photo Gallery ─────────────────────────────
                _FadeInSection(
                  delay: 500,
                  // Live photos from the backend (PhotoController) — presigned
                  // URLs, refreshed whenever an upload/delete/reorder/primary
                  // op updates myPhotosProvider. "Add" opens the wizard photo
                  // step (edit mode), which manages the same provider.
                  child: NmPhotoGalleryCard(
                    photoUrls: photos.map((p) => p.cdnUrl).toList(),
                    onAddTap: () =>
                        openEditProfile(context, ref, wizardStep: 11),
                  ),
                ),
                gap,

                // ── 11. Premium Membership ────────────────────────
                _FadeInSection(
                  delay: 540,
                  child: NmPremiumMembershipCard(
                    // TODO(backend): no subscription/premium-status
                    // endpoint is wired yet (ApiEndpoints.
                    // subscriptionStatus is unused) — placeholder until
                    // that's implemented.
                    isPremiumMember: false,
                    // Premium is a bottom-nav tab — switch via the shell's
                    // go navigation, not a stacked push.
                    onCtaTap: () => context.go(RouteNames.premium),
                  ),
                ),
                gap,

                // ── 12. Quick Actions ─────────────────────────────
                _FadeInSection(
                  delay: 580,
                  child: NmQuickActionsCard(
                    actions: [
                      NmQuickAction(
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                        onTap: () => context.push(RouteNames.settings),
                      ),
                      NmQuickAction(
                        icon: Icons.lock_person_outlined,
                        label: 'Privacy',
                        onTap: () => context.push(RouteNames.privacy),
                      ),
                      NmQuickAction(
                        icon: Icons.contact_support_outlined,
                        label: 'Help',
                        onTap: () => context.push(RouteNames.help),
                      ),
                      NmQuickAction(
                        icon: Icons.card_membership_outlined,
                        label: 'Subscription',
                        onTap: () => context.push(RouteNames.subscription),
                      ),
                    ],
                  ),
                ),
                gap,

                // ── 13. Account ───────────────────────────────────
                const _FadeInSection(
                  delay: 620,
                  child: NmAccountSection(
                    // Logout no-op: existing auth flow handles session
                    // invalidation via its own provider/cubit.
                  ),
                ),

                // Bottom padding clears the bottom nav bar
                const SizedBox(height: AppSpacing.xl4),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    AppLocalizations l10n,
    bool isDark,
  ) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      title: Text(
        l10n.profileTitle,
        style: AppTypography.titleLarge.copyWith(
          color: isDark ? AppColors.textPrimaryDark : AppColors.primary,
        ),
      ),
      actions: [
        // Existing settings navigation — UNCHANGED
        IconButton(
          tooltip: 'Settings',
          onPressed: () => context.push(RouteNames.settings),
          icon: Icon(
            Icons.settings_outlined,
            color: isDark ? AppColors.textSecondaryDark : AppColors.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
    );
  }
}

// ── Private: scroll-in fade-up animation ──────────────────────────

/// Fades + slides each section up with a configurable stagger delay.
/// Purely implicit — no [AnimationController] needed.
class _FadeInSection extends StatelessWidget {
  final Widget child;
  final int delay;

  const _FadeInSection({required this.child, this.delay = 0});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 450 + delay),
      curve: Curves.easeOutCubic,
      builder: (_, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 18),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
