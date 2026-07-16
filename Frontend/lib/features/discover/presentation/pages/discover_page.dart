import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../authentication/presentation/utils/logout_flow.dart';
import '../../../profile_completion/presentation/providers/profile_completeness_provider.dart';
import '../../../registration/presentation/utils/open_edit_profile.dart';
import '../../domain/entities/discovery_profile_entity.dart';
import '../../domain/entities/discover_feed_entity.dart';
import '../../domain/entities/story_entity.dart';
import '../providers/discover_providers.dart';
import '../widgets/compatibility_badge.dart';
import '../widgets/nenjam_navigation_drawer.dart';

/// Nenjam Discover Page — pixel-faithful Flutter translation of the
/// "Nenjam Home Feed" Stitch screen.
///
/// Sections (top to bottom):
///   1. Sticky app bar (avatar • title • search • notifications)
///   2. "New Today" story rings (horizontal scroll)
///   3. AI Recommended full-height profile card
///   4. Recently Joined — horizontal scroll compact cards
///   5. Verified Profiles — full-height card with stats
///   6. Near You — 2-column grid
///   7. Premium Members — dark navy section
///
/// Profile Intelligence is optional enrichment, never auto-opened here —
/// users reach it deliberately via the navigation drawer or Profile page.
class DiscoverPage extends ConsumerWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(discoverFeedProvider);
    final completenessAsync = ref.watch(profileCompletenessSnapshotProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      drawer: NenjamNavigationDrawer(
        // Falls back to the previous static default while loading/on error
        // so the drawer never regresses to a broken state.
        profileCompletionPercent:
            completenessAsync.valueOrNull?.percentage ?? 85,
        onMyProfileTap: () => context.push(RouteNames.profile),
        onEditProfileTap: () => openEditProfile(context, ref),
        onProfileIntelligenceTap: () =>
            context.push(RouteNames.profileIntelligence),
        onVerificationCenterTap: () =>
            openEditProfile(context, ref, wizardStep: 12),
        onTrustScoreTap: () => context.push(RouteNames.trustScore),
        onVisitorsTap: () => context.push(RouteNames.visitors),
        onInterestSentTap: () => context.push(RouteNames.interestsSent),
        onInterestReceivedTap: () => context.push(RouteNames.interestsReceived),
        onShortlistTap: () => context.push(RouteNames.shortlisted),
        onLanguageTap: () => context.push(RouteNames.language),
        onSettingsTap: () => context.push(RouteNames.settings),
        onPrivacyTap: () => context.push(RouteNames.privacy),
        onHelpTap: () => context.push(RouteNames.help),
        onLogoutTap: () => confirmAndLogout(context, ref),
        onUpgradeTap: () => context.go(RouteNames.premium),
        onCompleteProfileTap: () => context.push(RouteNames.profileCompletion),
      ),
      body: feedAsync.when(
        data: (feed) => _DiscoverFeedView(feed: feed),
        loading: () => const _DiscoverLoading(),
        error: (error, _) => Center(
          child: NmErrorWidget(
            onRetry: () => ref.invalidate(discoverFeedProvider),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading skeleton
// ─────────────────────────────────────────────────────────────────────────────

class _DiscoverLoading extends StatelessWidget {
  const _DiscoverLoading();

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          const NmShimmer(height: 88, borderRadius: AppSpacing.radiusLg),
          const SizedBox(height: AppSpacing.base),
          NmShimmer(height: h * 0.70, borderRadius: 32),
          const SizedBox(height: AppSpacing.xl2),
          const NmShimmer(height: 220, borderRadius: AppSpacing.radiusXl),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main feed scroll view
// ─────────────────────────────────────────────────────────────────────────────

class _DiscoverFeedView extends ConsumerWidget {
  final DiscoverFeedEntity feed;

  const _DiscoverFeedView({required this.feed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return RefreshIndicator(
      color: AppColors.accentGold,
      onRefresh: () => ref.refresh(discoverFeedProvider.future),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── 1. Sticky App Bar ──────────────────────────────────────
          const _DiscoverAppBar(),

          // ── 2. New Today stories ───────────────────────────────────
          if (feed.stories.isNotEmpty)
            SliverToBoxAdapter(child: _NewTodaySection(stories: feed.stories)),

          // ── 3. AI Recommended card ────────────────────────────────
          if (feed.aiRecommended.isNotEmpty)
            SliverToBoxAdapter(
              child: _SectionPadding(
                child: _FeedSection(
                  title: l10n.discoverAiRecommendedTitle,
                  icon: Icons.auto_awesome_rounded,
                  iconColor: AppColors.accentGold,
                  child: _LargeProfileCard(
                    profile: feed.aiRecommended.first,
                    showStats: false,
                  ),
                ),
              ),
            ),

          // ── 4. Recently Joined ─────────────────────────────────────
          if (feed.recentlyJoined.isNotEmpty)
            SliverToBoxAdapter(
              child: _SectionPadding(
                child: _FeedSection(
                  title: l10n.discoverRecentlyJoinedTitle,
                  child: _HorizontalCompactCards(profiles: feed.recentlyJoined),
                ),
              ),
            ),

          // ── 5. Verified Profiles card ─────────────────────────────
          if (feed.verifiedProfiles.isNotEmpty)
            SliverToBoxAdapter(
              child: _SectionPadding(
                child: _FeedSection(
                  title: l10n.discoverVerifiedProfilesTitle,
                  icon: Icons.verified_rounded,
                  iconColor: AppColors.verifiedBlue,
                  child: _LargeProfileCard(
                    profile: feed.verifiedProfiles.first,
                    showStats: true,
                  ),
                ),
              ),
            ),

          // ── 6. Near You grid ──────────────────────────────────────
          if (feed.nearYou.isNotEmpty)
            SliverToBoxAdapter(
              child: _SectionPadding(
                child: _FeedSection(
                  title: l10n.discoverNearYouTitle,
                  icon: Icons.location_on_rounded,
                  iconColor: AppColors.accentGold,
                  child: _NearYouGrid(profiles: feed.nearYou),
                ),
              ),
            ),

          // ── 7. Premium Members ─────────────────────────────────────
          if (feed.premiumMembers.isNotEmpty)
            SliverToBoxAdapter(
              child: _PremiumMembersSection(profiles: feed.premiumMembers),
            ),

          // ── Footer ────────────────────────────────────────────────
          const SliverToBoxAdapter(child: _FeedFooter()),

          // Bottom padding for nav bar
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl3)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// App Bar
// ─────────────────────────────────────────────────────────────────────────────

/// Translucent sticky app bar: avatar + "Nenjam Matrimony" + search + bell.
class _DiscoverAppBar extends StatelessWidget {
  const _DiscoverAppBar();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SliverAppBar(
      pinned: true,
      floating: false,
      automaticallyImplyLeading: false,
      backgroundColor: AppColors.backgroundLight.withValues(alpha: 0.88),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      toolbarHeight: 64,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundLight.withValues(alpha: 0.88),
            border: Border(
              bottom: BorderSide(
                color: AppColors.dividerLight.withValues(alpha: 0.2),
              ),
            ),
          ),
        ),
      ),
      title: Row(
        children: [
          // User avatar
          GestureDetector(
            onTap: () => Scaffold.of(context).openDrawer(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.borderLight.withValues(alpha: 0.3),
                ),
                color: AppColors.primarySurface,
              ),
              clipBehavior: Clip.antiAlias,
              child: const Icon(
                Icons.person_rounded,
                size: 20,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.appNameShort,
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.search_rounded, color: AppColors.primary),
          tooltip: l10n.discoverSearchTooltip,
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: () {},
              icon: const Icon(
                Icons.notifications_none_rounded,
                color: AppColors.primary,
              ),
              tooltip: l10n.notificationsTitle,
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// New Today Stories
// ─────────────────────────────────────────────────────────────────────────────

class _NewTodaySection extends StatelessWidget {
  final List<StoryEntity> stories;

  const _NewTodaySection({required this.stories});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.sm, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            child: Text(
              l10n.discoverNewTodayLabel.toUpperCase(),
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textSecondaryLight,
                letterSpacing: 1.2,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              itemCount: stories.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AppSpacing.base),
              itemBuilder: (context, index) =>
                  _StoryBubble(story: stories[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryBubble extends StatelessWidget {
  final StoryEntity story;

  const _StoryBubble({required this.story});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 76,
          height: 76,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: story.hasNewStory
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF755B00), Color(0xFFFED977)],
                  )
                : null,
            color: story.hasNewStory
                ? null
                : AppColors.dividerLight.withValues(alpha: 0.5),
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.backgroundLight, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: story.imageUrl.startsWith('http')
                ? Image.network(
                    story.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fallback(),
                  )
                : Image.asset(
                    story.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fallback(),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          width: 76,
          child: Text(
            story.name,
            textAlign: TextAlign.center,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textPrimaryLight,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _fallback() => Container(
    color: AppColors.primarySurface,
    child: const Icon(Icons.person_rounded, size: 28, color: AppColors.primary),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Section wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _SectionPadding extends StatelessWidget {
  final Widget child;

  const _SectionPadding({required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xl2),
    child: child,
  );
}

class _FeedSection extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color? iconColor;
  final Widget child;

  const _FeedSection({
    required this.title,
    required this.child,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 20,
                        color: iconColor ?? AppColors.accentGold,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Flexible(
                      child: Text(
                        title,
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 20,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {},
                child: Text(
                  l10n.discoverViewAllButton.toUpperCase(),
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.accentGold,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        child,
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Large Profile Card (AI Recommended / Verified Profiles)
// ─────────────────────────────────────────────────────────────────────────────

/// Full-bleed profile card — 75vh height, radius-32, matching Stitch design.
class _LargeProfileCard extends StatelessWidget {
  final DiscoveryProfileEntity profile;
  final bool showStats;

  const _LargeProfileCard({required this.profile, required this.showStats});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cardHeight = MediaQuery.sizeOf(context).height * 0.72;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: SizedBox(
          height: cardHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Profile photo ──────────────────────────────────────
              _CardImage(photoUrls: profile.photoUrls),

              // ── Bottom gradient scrim ──────────────────────────────
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0x4D041635), // primary/30
                      Color(0xF2041635), // primary/95
                    ],
                    stops: [0.0, 0.45, 1.0],
                  ),
                ),
              ),

              // ── Top badge row ──────────────────────────────────────
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: CompatibilityBadgeRow(
                  compatibility: profile.compatibility,
                  isVerified: profile.isVerified,
                  isPremium: profile.isPremium,
                ),
              ),

              // ── Bottom info + buttons ──────────────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name + verified
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              '${profile.name}, ${profile.age}',
                              style: AppTypography.headlineMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (profile.isVerified) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified_rounded,
                              size: 20,
                              color: Color(0xFFFFE08F), // secondary-fixed
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Location • Profession
                      if (profile.location.isNotEmpty ||
                          profile.profession.isNotEmpty)
                        Text(
                          [
                            if (profile.location.isNotEmpty) profile.location,
                            if (profile.profession.isNotEmpty)
                              profile.profession,
                          ].join(' • '),
                          style: AppTypography.bodyMedium.copyWith(
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                      // Stats row (Match / Astro / Trust) for verified card
                      if (showStats &&
                          profile.compatibility.aiMatchPercent > 0) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _StatsRow(
                          l10n: l10n,
                          compatibility: profile.compatibility,
                        ),
                      ],

                      // Tag pills
                      if (_tagPills(l10n, profile).isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: 6,
                          runSpacing: 5,
                          children: _tagPills(
                            l10n,
                            profile,
                          ).map((t) => _TagPill(label: t)).toList(),
                        ),
                      ],

                      const SizedBox(height: AppSpacing.base),

                      // Buttons
                      _CardButtons(profile: profile),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _tagPills(AppLocalizations l10n, DiscoveryProfileEntity p) {
    final list = <String>[...p.tags];
    if (p.isVerified && !list.contains('Verified')) {
      list.insert(0, 'Verified Identity');
    }
    if (p.isPremium && !list.contains('Premium Plus')) list.add('Premium Plus');
    return list.take(4).map((tag) => _localizedTag(l10n, tag)).toList();
  }
}

/// Maps the fixed set of known raw tag values (mock data content) to their
/// localized display text. Unrecognized/custom tags pass through unchanged.
String _localizedTag(AppLocalizations l10n, String tag) {
  switch (tag) {
    case 'NRI':
      return l10n.discoverChipNri;
    case 'Verified Identity':
      return l10n.discoverChipVerifiedIdentity;
    case 'Premium Plus':
      return l10n.discoverChipPremiumPlus;
    default:
      return tag;
  }
}

/// Match / Astro / Trust stats row shown on verified profiles card.
class _StatsRow extends StatelessWidget {
  final AppLocalizations l10n;
  final dynamic compatibility;

  const _StatsRow({required this.l10n, required this.compatibility});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: _Stat(
            label: l10n.discoverStatMatchLabel,
            value: '${compatibility.aiMatchPercent}%',
            isGold: true,
          ),
        ),
        _Divider(),
        Flexible(
          child: _Stat(
            label: l10n.discoverStatAstroLabel,
            value: '${compatibility.astroMatchPercent}%',
            isGold: true,
          ),
        ),
        _Divider(),
        Flexible(
          child: _Stat(
            label: l10n.discoverStatTrustLabel,
            value: '${compatibility.overallCompatibility}/100',
            isGold: false,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final bool isGold;

  const _Stat({required this.label, required this.value, required this.isGold});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTypography.labelSmall.copyWith(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          value,
          style: AppTypography.labelMedium.copyWith(
            color: isGold
                ? const Color(0xFFFFE08F)
                : AppColors.faceVerificationGreen,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 28,
    margin: const EdgeInsets.symmetric(horizontal: 16),
    color: Colors.white.withValues(alpha: 0.2),
  );
}

/// Interested (full-width gold) + Shortlist / View Profile buttons.
class _CardButtons extends StatefulWidget {
  final DiscoveryProfileEntity profile;

  const _CardButtons({required this.profile});

  @override
  State<_CardButtons> createState() => _CardButtonsState();
}

class _CardButtonsState extends State<_CardButtons> {
  bool _sent = false;
  bool _shortlisted = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Interested
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _sent
                ? null
                : () async {
                    setState(() => _sent = true);
                    await Future<void>.delayed(const Duration(seconds: 3));
                    if (mounted) setState(() => _sent = false);
                  },
            child: Ink(
              decoration: BoxDecoration(
                color: _sent ? AppColors.faceVerificationGreen : null,
                gradient: _sent ? null : null,
                borderRadius: BorderRadius.circular(16),
                boxShadow: _sent ? null : AppShadows.goldGlow,
              ),
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color: _sent
                      ? AppColors.faceVerificationGreen
                      : const Color(0xFFFFE08F),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _sent
                          ? Icons.check_circle_rounded
                          : Icons.favorite_rounded,
                      size: 20,
                      color: _sent ? Colors.white : const Color(0xFF241A00),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _sent
                            ? l10n.discoverInterestSentLabel
                            : l10n.actionInterested,
                        style: AppTypography.button.copyWith(
                          color: _sent ? Colors.white : const Color(0xFF241A00),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Shortlist + View Profile
        Row(
          children: [
            Expanded(
              child: _GlassBtn(
                icon: _shortlisted
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                label: l10n.profileCardShortlist,
                onTap: () => setState(() => _shortlisted = !_shortlisted),
                iconColor: _shortlisted
                    ? AppColors.accentGoldLight
                    : Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _GlassBtn(
                icon: Icons.person_rounded,
                label: l10n.actionViewProfile,
                onTap: () {},
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GlassBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color iconColor;

  const _GlassBtn({
    required this.icon,
    required this.label,
    this.onTap,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
          ),
          child: SizedBox(
            height: 46,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: AppTypography.labelMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted glass tag pill
class _TagPill extends StatelessWidget {
  final String label;

  const _TagPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.labelSmall.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          fontSize: 10,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recently Joined — horizontal compact cards
// ─────────────────────────────────────────────────────────────────────────────

class _HorizontalCompactCards extends StatelessWidget {
  final List<DiscoveryProfileEntity> profiles;

  const _HorizontalCompactCards({required this.profiles});

  @override
  Widget build(BuildContext context) {
    // A horizontal SingleChildScrollView + Row (rather than a ListView
    // pinned to a guessed pixel height) lets each card size itself from
    // its own content — the row's height becomes the tallest card's
    // natural height, so larger text-scale settings or longer localized
    // profession/location strings simply make the row taller instead of
    // overflowing a fixed box.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < profiles.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.base),
            _CompactProfileCard(profile: profiles[i]),
          ],
        ],
      ),
    );
  }
}

class _CompactProfileCard extends StatelessWidget {
  final DiscoveryProfileEntity profile;

  const _CompactProfileCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      width: 176,
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        boxShadow: AppShadows.cardLight,
        border: Border.all(
          color: AppColors.dividerLight.withValues(alpha: 0.15),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Photo
          SizedBox(
            height: 192,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _CardImage(photoUrls: profile.photoUrls),
                // Match badge overlay
                if (profile.compatibility.aiMatchPercent > 0)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.bolt_rounded,
                              size: 10,
                              color: Color(0xFFFFE08F),
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                '${profile.compatibility.aiMatchPercent}% ${l10n.discoverStatMatchLabel}',
                                style: AppTypography.labelSmall.copyWith(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Info
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${profile.name}, ${profile.age}',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.textPrimaryLight,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (profile.profession.isNotEmpty) profile.profession,
                    if (profile.location.isNotEmpty) profile.location,
                  ].join(' • '),
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textSecondaryLight,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // Interested button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accentGold,
                      side: const BorderSide(color: AppColors.accentGold),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                      ),
                    ),
                    child: Text(
                      l10n.actionInterested,
                      style: AppTypography.labelSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Near You — 2-column grid
// ─────────────────────────────────────────────────────────────────────────────

class _NearYouGrid extends StatelessWidget {
  final List<DiscoveryProfileEntity> profiles;

  const _NearYouGrid({required this.profiles});

  @override
  Widget build(BuildContext context) {
    final capped = profiles.take(4).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: AppSpacing.base,
          mainAxisSpacing: AppSpacing.base,
          childAspectRatio: 0.75,
        ),
        itemCount: capped.length,
        itemBuilder: (_, i) => _NearYouCard(profile: capped[i]),
      ),
    );
  }
}

class _NearYouCard extends StatelessWidget {
  final DiscoveryProfileEntity profile;

  const _NearYouCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariantLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(
          color: AppColors.dividerLight.withValues(alpha: 0.15),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _CardImage(photoUrls: profile.photoUrls)),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${profile.name}, ${profile.age}',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.textPrimaryLight,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  profile.distanceKm != null
                      ? '${profile.distanceKm!.toStringAsFixed(1)} ${l10n.discoverKmAwaySuffix} • ${profile.education}'
                      : profile.profession,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textSecondaryLight,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accentGold,
                      side: const BorderSide(color: AppColors.accentGold),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                      ),
                    ),
                    child: Text(
                      l10n.actionInterested,
                      style: AppTypography.labelSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium Members — dark navy section
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumMembersSection extends StatelessWidget {
  final List<DiscoveryProfileEntity> profiles;

  const _PremiumMembersSection({required this.profiles});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl2),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.primary, // primary-container #1b2b4b
          borderRadius: BorderRadius.circular(32),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.workspace_premium_rounded,
                        color: Color(0xFFFFE08F),
                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          l10n.discoverPremiumMembersTitle,
                          style: AppTypography.titleMedium.copyWith(
                            color: const Color(0xFFFFE08F),
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: Text(
                    l10n.discoverUpgradeButton.toUpperCase(),
                    style: AppTypography.labelSmall.copyWith(
                      color: const Color(0xFFFFE08F),
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.base),
            // Horizontal premium cards
            SizedBox(
              height: 296,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: profiles.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.base),
                itemBuilder: (_, i) => _PremiumMemberCard(profile: profiles[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumMemberCard extends StatelessWidget {
  final DiscoveryProfileEntity profile;

  const _PremiumMemberCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SizedBox(
      width: 260,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFFFE08F).withValues(alpha: 0.3),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _CardImage(photoUrls: profile.photoUrls),
            // Gradient
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC041635)],
                ),
              ),
            ),
            // Bottom info
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.discoverEliteMemberLabel.toUpperCase(),
                    style: AppTypography.labelSmall.copyWith(
                      color: const Color(0xFFFFE08F),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${profile.name}, ${profile.age}',
                    style: AppTypography.titleMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: ElevatedButton(
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFE08F),
                              foregroundColor: const Color(0xFF241A00),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            child: Text(
                              l10n.discoverConnectButton,
                              style: AppTypography.labelSmall.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Footer
// ─────────────────────────────────────────────────────────────────────────────

class _FeedFooter extends StatelessWidget {
  const _FeedFooter();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.xl3,
      ),
      child: Column(
        children: [
          Icon(
            Icons.all_inclusive_rounded,
            size: 40,
            color: AppColors.textTertiaryLight.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.discoverSearchingMoreLabel,
            textAlign: TextAlign.center,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textTertiaryLight.withValues(alpha: 0.4),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared image widget
// ─────────────────────────────────────────────────────────────────────────────

class _CardImage extends StatelessWidget {
  final List<String> photoUrls;

  const _CardImage({required this.photoUrls});

  @override
  Widget build(BuildContext context) {
    if (photoUrls.isEmpty) return _placeholder();
    final url = photoUrls.first;
    if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
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

  Widget _placeholder() => Container(
    color: AppColors.surfaceVariantDark,
    child: const Center(
      child: Icon(
        Icons.person_rounded,
        size: 48,
        color: AppColors.textTertiaryDark,
      ),
    ),
  );
}
