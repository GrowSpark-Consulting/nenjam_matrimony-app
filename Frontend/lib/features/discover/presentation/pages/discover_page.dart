import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/layout/adaptive_grid.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/layout/window_class.dart';
import '../../../../core/router/profile_navigation.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/avatars/app_avatars.dart';
import '../../../../core/widgets/avatars/gender_placeholder.dart';
import '../../../../core/permissions/permission_providers.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../core/widgets/images/sized_network_photo.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/navigation/app_bottom_nav.dart';
import '../../../../core/widgets/system_ui/nm_status_bar_style.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../inbox/presentation/widgets/inbox_preview_panel.dart';
import '../../../interests/presentation/providers/interests_provider.dart';
import '../../../interests/presentation/utils/interest_button_copy.dart';
import '../../../notifications/presentation/providers/notification_providers.dart';
import '../../../shortlist/presentation/providers/shortlist_provider.dart';
import '../../../shortlist/presentation/utils/shortlist_toggle.dart';
import '../../../profile_photos/presentation/providers/photo_providers.dart';
import '../../../partner_preferences/presentation/utils/open_partner_preferences.dart';
import '../../../nearby/data/repositories/nearby_repository_impl.dart';
import '../../../nearby/presentation/providers/nearby_providers.dart';
import '../../../profile_completion/presentation/widgets/complete_profile_card.dart';
import '../../domain/entities/discovery_profile_entity.dart';
import '../../domain/entities/discover_feed_entity.dart';
import '../../domain/entities/story_entity.dart';
import '../providers/discover_providers.dart';
import '../widgets/compatibility_badge.dart';
import '../../../../core/layout/mouse_drag_scroll.dart';

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
///   7. Premium Members — deep plum section
class DiscoverPage extends ConsumerWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(discoverFeedProvider);

    // Measured on the window, so the inbox panel arrives at a 1200px window
    // whatever the navigation rail beside the page takes.
    final wide = WindowClass.of(context).isLarge;

    // The feed is held at [ContentWidth.feed] at every width, not only beside
    // the inbox panel: on a tablet or a small laptop window a full-width large
    // card became a wide landscape crop with its actions stretched across it.
    final feedBody = feedAsync.when(
      data: (feed) => _DiscoverFeedView(feed: feed),
      loading: () => const NmContentWidth(
        maxWidth: ContentWidth.feed,
        child: _DiscoverLoading(),
      ),
      // skipError: a background refresh this provider's own `.invalidate`
      // (pull-to-refresh, or a realtime `feed.invalidate` signal — see
      // realtime_providers.dart) can fail without replacing an
      // already-visible feed with a full error screen; only a genuine
      // first-load failure (no previous value to fall back on) reaches
      // this branch regardless of the flag — see AsyncValue.when's own
      // doc comment.
      skipError: true,
      error: (error, _) => Center(
        child: NmErrorWidget(
          onRetry: () => ref.invalidate(discoverFeedProvider),
        ),
      ),
    );

    // Explicit rather than left to AppBarTheme: the Scaffold below is
    // hardcoded to a light background in every app theme, but
    // AppBarTheme.systemOverlayStyle flips to light (white) icons in dark
    // mode — invisible against this still-light background. Deriving the
    // style from the actual background color sidesteps that drift.
    return NmPageStatusBar(
      background: AppColors.backgroundLight,
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
        body: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: feedBody),
                  const SizedBox(
                    width: InboxPreviewPanel.width,
                    child: InboxPreviewPanel(),
                  ),
                ],
              )
            : feedBody,
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
  /// Centered at [ContentWidth.feed] whenever it has more room than that. The
  /// scroll view itself stays full width, so a mouse wheel over the side
  /// gutters still scrolls the feed.
  final DiscoverFeedEntity feed;

  const _DiscoverFeedView({required this.feed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    // A feed with no profiles in any section is a legitimate state — the
    // caller hasn't finalized their own profile (backend fails the mandatory
    // opposite-gender rule closed), or nobody matches even after the backend's
    // progressive fallback. Show a real empty state instead of the perpetual
    // "Searching for more souls…" footer, which reads like a stuck spinner.
    final bool isEmpty =
        feed.stories.isEmpty &&
        feed.aiRecommended.isEmpty &&
        feed.recentlyJoined.isEmpty &&
        feed.verifiedProfiles.isEmpty &&
        feed.nearYou.isEmpty &&
        feed.premiumMembers.isEmpty;

    // Near You reads no part of `feed`: different data source (the device's
    // location, via `/profiles/nearby`), different filters, and its own
    // permission state, which it renders itself. Defined once and placed in
    // both branches below — it must survive an empty feed, and it must keep
    // its position above Premium Members when the feed has content, so it
    // cannot simply be appended after the branch.
    const nearYouSliver = SliverToBoxAdapter(child: _NearYouSection());

    // Everything below the sticky app bar (section 1).
    final contentSlivers = <Widget>[
      // ── 2. New Today stories ───────────────────────────────────
      // Hoisted above the isEmpty/feed-content split rather than left
      // inside the non-empty branch: `feed.stories.isNotEmpty` already
      // implies `isEmpty == false` (stories is one of the six conditions
      // isEmpty checks), so this renders in exactly the same case either
      // way — but living up here keeps it a sibling of, not nested
      // inside, the branch that used to also hide the card below.
      if (feed.stories.isNotEmpty)
        SliverToBoxAdapter(child: _NewTodaySection(stories: feed.stories)),

      // ── 2b. Complete Your Profile reminder ──────────────────────
      // Deliberately a sibling of the isEmpty/feed-content branch below,
      // not nested inside either side of it: this card reflects the
      // profile-completion response, never Discover's match results, so
      // an empty or errored feed must not take it down with it. Renders
      // nothing on its own when every section is done or the card was
      // dismissed this session — see CompleteProfileCard.
      const SliverToBoxAdapter(child: CompleteProfileCard()),

      // An empty preference-filtered feed no longer takes the whole page.
      // `SliverFillRemaining(hasScrollBody: false)` used to, which meant a
      // user with no preference matches also lost Near You — even though
      // Near Me applies completely different rules (gender and safety
      // only, no partner preferences, a radius instead) and may well have
      // people to show. Sized to its content now, with Near You below it.
      if (isEmpty) ...[
        const SliverToBoxAdapter(child: _DiscoverEmptyState()),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.sm,
            ),
            child: Divider(height: 1),
          ),
        ),
        nearYouSliver,
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl3)),
      ] else ...[
        // ── Fallback banner (backend widened the search) ───────────
        if (feed.fallbackUsed)
          const SliverToBoxAdapter(child: _FallbackBanner()),

        // ── 3. AI Recommended card ────────────────────────────────
        if (feed.aiRecommended.isNotEmpty)
          SliverToBoxAdapter(
            child: _SectionPadding(
              child: _FeedSection(
                title: l10n.discoverAiRecommendedTitle,
                icon: Icons.auto_awesome_rounded,
                iconColor: AppColors.secondary,
                child: _AiRecommendedCarousel(feed: feed),
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
                child: _ProfileCarousel(
                  profiles: feed.verifiedProfiles,
                  showStats: true,
                ),
              ),
            ),
          ),

        // ── 6. Near You — real device-location results ─────────────
        nearYouSliver,

        // ── 7. Premium Members ─────────────────────────────────────
        if (feed.premiumMembers.isNotEmpty)
          SliverToBoxAdapter(
            child: _PremiumMembersSection(profiles: feed.premiumMembers),
          ),

        // ── Footer ────────────────────────────────────────────────
        const SliverToBoxAdapter(child: _FeedFooter()),

        // Clearance for the floating nav pill. Measured from the shell
        // rather than the fixed 40 this used to be — that guessed number
        // was shorter than the pill on most devices, so the footer ended
        // up partly behind it.
        SliverToBoxAdapter(child: SizedBox(height: navContentInset(context))),
      ],
    ];

    return RefreshIndicator(
      color: AppColors.secondary,
      onRefresh: () => ref.refresh(discoverFeedProvider.future),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final surplus = constraints.maxWidth - ContentWidth.feed;
          final inset = surplus > 0 ? surplus / 2 : 0.0;
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── 1. Sticky App Bar ──────────────────────────────────
              _DiscoverAppBar(horizontalInset: inset),
              if (inset == 0)
                ...contentSlivers
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  sliver: SliverMainAxisGroup(slivers: contentSlivers),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// App Bar
// ─────────────────────────────────────────────────────────────────────────────

const double _appBarHeight = 64;

/// Translucent sticky app bar: avatar + "Nenjam Matrimony" + search + bell.
class _DiscoverAppBar extends StatelessWidget {
  /// Extra space on each side so the bar's contents line up with a feed that
  /// is centered narrower than the bar's full-width background.
  final double horizontalInset;

  const _DiscoverAppBar({this.horizontalInset = 0});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inset = horizontalInset > 0;

    return SliverAppBar(
      pinned: true,
      floating: false,
      automaticallyImplyLeading: false,
      titleSpacing: inset
          ? NavigationToolbar.kMiddleSpacing + horizontalInset
          : null,
      actionsPadding: inset
          ? EdgeInsetsDirectional.only(end: horizontalInset)
          : null,
      backgroundColor: AppColors.backgroundLight.withValues(alpha: 0.88),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      toolbarHeight: _appBarHeight,
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
          // User avatar — a scoped Consumer so a photo change only rebuilds
          // this small avatar, not the whole sticky app bar / feed below it.
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.borderLight.withValues(alpha: 0.3),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Consumer(
              builder: (context, ref, _) => NmCircleAvatar(
                imageUrl: ref.watch(myPrimaryPhotoUrlProvider),
                size: 32,
                // Full-screen profile menu, pushed onto the root
                // navigator so it covers this page and the bottom-nav
                // shell entirely (see RouteNames.profileMenu).
                onTap: () => context.push(RouteNames.profileMenu),
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
          // Pushed (not `go`) so Discover stays on the navigator stack —
          // back returns to this exact instance with scroll position,
          // loaded feed data, and provider state all intact.
          onPressed: () => context.push(RouteNames.search),
          icon: const Icon(Icons.search_rounded, color: AppColors.primary),
          tooltip: l10n.discoverSearchTooltip,
        ),
        // Scoped Consumer so an unread-count change only rebuilds this small
        // icon+badge, not the whole sticky app bar (same reasoning as the
        // avatar Consumer above).
        Consumer(
          builder: (context, ref, _) {
            final unreadCount = ref.watch(unreadNotificationsCountProvider);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  // Pushed (not `go`) for the same reason as Search above —
                  // Discover stays on the navigator stack so Back returns to
                  // this exact instance.
                  onPressed: () => context.push(RouteNames.notifications),
                  icon: const Icon(
                    Icons.notifications_none_rounded,
                    color: AppColors.primary,
                  ),
                  tooltip: l10n.notificationsTitle,
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        textAlign: TextAlign.center,
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fallback banner — shown when the backend's ProgressiveFallbackStrategy had
// to widen the caller's saved preferences to avoid an empty feed. Deliberately
// a quiet inline banner (not a dialog/snackbar) per the fallback spec: it
// should never interrupt the user, just quietly explain what happened.
// ─────────────────────────────────────────────────────────────────────────────

class _FallbackBanner extends StatelessWidget {
  const _FallbackBanner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.base,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.secondary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: AppColors.secondary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.tune_rounded,
              size: 16,
              color: AppColors.secondary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l10n.discoverFallbackBannerLabel,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textSecondaryLight,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
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
            child: NmMouseDragScroll(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                ),
                itemCount: stories.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.base),
                itemBuilder: (context, index) =>
                    _StoryBubble(story: stories[index]),
              ),
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
    final profile = story.profile;

    return GestureDetector(
      // "New Today" bubbles represent newly-joined members, not
      // ephemeral stories — tapping one opens Profile Detail exactly
      // like any other profile card.
      onTap: profile == null
          ? null
          : () => openProfileDetail(
              context,
              profile,
              heroTag: 'profile-photo-discover-${profile.id}',
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: story.hasNewStory ? AppGradients.match : null,
              color: story.hasNewStory
                  ? null
                  : AppColors.dividerLight.withValues(alpha: 0.5),
            ),
            // The white separator ring is a filled circle + padding rather
            // than a stroked border: a `Border` insets the child while the
            // clip path stays the full circle, which left un-covered gaps
            // between the square image and the circular edge.
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.backgroundLight,
              ),
              child: ClipOval(
                clipBehavior: Clip.antiAlias,
                // Forces the image to tightly fill the clipped circle so
                // BoxFit.cover always centre-crops with no empty areas.
                child: SizedBox.expand(
                  child: Hero(
                    tag: profile == null
                        ? 'story-photo-${story.id}'
                        : 'profile-photo-discover-${profile.id}',
                    child: story.imageUrl.isEmpty
                        ? _fallback()
                        : (story.imageUrl.startsWith('http')
                              ? NmSizedNetworkPhoto(
                                  url: story.imageUrl,
                                  alignment: Alignment.center,
                                  filterQuality: FilterQuality.medium,
                                  errorBuilder: (_, __, ___) => _fallback(),
                                )
                              : Image.asset(
                                  story.imageUrl,
                                  fit: BoxFit.cover,
                                  alignment: Alignment.center,
                                  filterQuality: FilterQuality.medium,
                                  errorBuilder: (_, __, ___) => _fallback(),
                                )),
                  ),
                ),
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
      ),
    );
  }

  Widget _fallback() => NmGenderPlaceholder(
    gender: story.gender,
    iconSize: 28,
    backgroundColor: AppColors.primarySurface,
    iconColor: AppColors.primary,
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
                        color: iconColor ?? AppColors.secondary,
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
                    color: AppColors.secondary,
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

/// Full-bleed profile card — radius-32, matching Stitch design. Its height
/// comes from [heightFor], shared with the carousel that hosts it.
class _LargeProfileCard extends StatelessWidget {
  final DiscoveryProfileEntity profile;
  final bool showStats;
  final double height;

  const _LargeProfileCard({
    super.key,
    required this.profile,
    required this.showStats,
    required this.height,
  });

  /// Floor and cap for [heightFor]. The floor holds the name, a row of tags
  /// and all three actions at their full touch size; the cap keeps the card's
  /// portrait shape on a tall monitor, where the feed column is only 680 wide.
  static const double minHeight = 420;
  static const double maxHeight = 760;

  /// Room the badge row takes at the top of the card; the info block below
  /// never grows into it.
  static const double _badgeReserve = 56;

  /// 72% of the window, as the card always was, but no taller than what is
  /// left below the sticky app bar once the carousel controls and the nav
  /// clearance are taken out, so on a short window the whole card, actions
  /// included, fits on screen at once. Clamped to [minHeight]..[maxHeight]:
  /// below the floor the page scrolls rather than squeezing the actions.
  static double heightFor(BuildContext context) {
    final media = MediaQuery.of(context);
    final h = media.size.height;
    final available =
        h -
        media.padding.top -
        _appBarHeight -
        _CarouselControls.height -
        navContentInset(context) -
        AppSpacing.base;
    final target = h * 0.72 < available ? h * 0.72 : available;
    return target.clamp(minHeight, maxHeight);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cardHeight = height;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: SizedBox(
          height: cardHeight,
          // Tapping anywhere on the card opens Profile Detail; the
          // buttons in `_CardButtons` below win the gesture arena for
          // their own taps since they're the deeper, more-specific
          // recognizers, so they keep working independently.
          child: GestureDetector(
            onTap: () => openProfileDetail(
              context,
              profile,
              heroTag: 'profile-photo-discover-${profile.id}',
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Profile photo ────────────────────────────────────
                Hero(
                  tag: 'profile-photo-discover-${profile.id}',
                  child: _CardImage(
                    photoUrls: profile.photoUrls,
                    gender: profile.gender,
                  ),
                ),

                // ── Bottom gradient scrim ──────────────────────────────
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        AppColors.photoScrimSoft,
                        AppColors.photoScrimStrong,
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
                // Held below the badge row. If larger text or a long Tamil
                // name still makes the block taller than that band, it scales
                // down as a whole instead of running off the card's top edge,
                // so the actions are never the part that gets cut.
                Positioned(
                  top: _badgeReserve,
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: LayoutBuilder(
                      builder: (context, box) => FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomLeft,
                        child: SizedBox(
                          width: box.maxWidth,
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
                                        style: AppTypography.headlineMedium
                                            .copyWith(
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
                                        color: AppColors.accentLight,
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
                                      if (profile.location.isNotEmpty)
                                        profile.location,
                                      if (profile.profession.isNotEmpty)
                                        profile.profession,
                                    ].join(' • '),
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),

                                // Stats row (Match / Astro) for verified card
                                if (showStats &&
                                    profile.compatibility.aiMatchPercent >
                                        0) ...[
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
                      ),
                    ),
                  ),
                ),
              ],
            ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Large-card carousel (AI Recommended / Verified Profiles)
// ─────────────────────────────────────────────────────────────────────────────

/// AI Recommended: this page's recommendations, then whatever
/// [discoverMoreProfilesProvider] has paged in after them.
class _AiRecommendedCarousel extends ConsumerWidget {
  final DiscoverFeedEntity feed;

  const _AiRecommendedCarousel({required this.feed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final more = ref.watch(discoverMoreProfilesProvider);
    return _ProfileCarousel(
      profiles: [...feed.aiRecommended, ...more.profiles],
      showStats: false,
      hasMore: more.hasMore,
      isLoadingMore: more.isLoadingMore,
      loadFailed: more.loadFailed,
      onLoadMore: ref.read(discoverMoreProfilesProvider.notifier).loadMore,
    );
  }
}

/// Every profile in a section, one large card at a time: swipe (or drag with
/// a mouse) between them, or use the previous/next controls underneath.
///
/// These sections used to render only their first profile. Since the feed's
/// Verified, Premium and New sections began taking only members who qualify,
/// everyone else lands in AI Recommended — so on a typical feed that one card
/// was the only profile on the screen and the rest were never shown.
class _ProfileCarousel extends StatefulWidget {
  final List<DiscoveryProfileEntity> profiles;
  final bool showStats;
  final bool hasMore;
  final bool isLoadingMore;
  final bool loadFailed;

  /// Asks for the next page. Called as the member nears the last card, and
  /// when they press next on it.
  final VoidCallback? onLoadMore;

  const _ProfileCarousel({
    required this.profiles,
    required this.showStats,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.loadFailed = false,
    this.onLoadMore,
  });

  /// How close to the last card the next page is requested, so it is usually
  /// there before the member reaches the end.
  static const _prefetchDistance = 3;

  @override
  State<_ProfileCarousel> createState() => _ProfileCarouselState();
}

class _ProfileCarouselState extends State<_ProfileCarousel> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _index = index);
    if (index >= widget.profiles.length - _ProfileCarousel._prefetchDistance) {
      _loadMore();
    }
  }

  void _loadMore() {
    if (widget.hasMore && !widget.isLoadingMore) widget.onLoadMore?.call();
  }

  void _go(int delta) {
    final target = _current + delta;
    if (target >= widget.profiles.length) {
      _loadMore();
      return;
    }
    if (target < 0) return;
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// [_index], kept in range when a refresh hands back a shorter list.
  int get _current =>
      widget.profiles.isEmpty ? 0 : _index.clamp(0, widget.profiles.length - 1);

  @override
  Widget build(BuildContext context) {
    final height = _LargeProfileCard.heightFor(context);
    final profiles = widget.profiles;
    final showControls =
        profiles.length > 1 || widget.hasMore || widget.loadFailed;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          child: NmMouseDragScroll(
            child: PageView.builder(
              controller: _controller,
              itemCount: profiles.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, i) => _LargeProfileCard(
                key: ValueKey(profiles[i].id),
                profile: profiles[i],
                showStats: widget.showStats,
                height: height,
              ),
            ),
          ),
        ),
        if (showControls)
          _CarouselControls(
            current: _current,
            total: profiles.length,
            canGoBack: _current > 0,
            canGoForward: _current < profiles.length - 1 || widget.hasMore,
            isLoadingMore: widget.isLoadingMore,
            loadFailed: widget.loadFailed,
            onPrevious: () => _go(-1),
            onNext: () => _go(1),
            onRetry: _loadMore,
          ),
      ],
    );
  }
}

/// Previous / "3 of 14" / next under a carousel, plus its paging state.
class _CarouselControls extends StatelessWidget {
  static const double height = 56;

  final int current;
  final int total;
  final bool canGoBack;
  final bool canGoForward;
  final bool isLoadingMore;
  final bool loadFailed;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onRetry;

  const _CarouselControls({
    required this.current,
    required this.total,
    required this.canGoBack,
    required this.canGoForward,
    required this.isLoadingMore,
    required this.loadFailed,
    required this.onPrevious,
    required this.onNext,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = loadFailed
        ? <Widget>[
            Flexible(
              child: Text(
                l10n.discoverLoadMoreFailed,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.error,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(
                l10n.commonRetry,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ]
        : <Widget>[
            Flexible(
              child: Text(
                l10n.discoverProfilePosition(current + 1, total),
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isLoadingMore) ...[
              const SizedBox(width: AppSpacing.sm),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ];

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          children: [
            IconButton(
              tooltip: l10n.discoverPreviousProfile,
              onPressed: canGoBack ? onPrevious : null,
              color: AppColors.primary,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: status,
              ),
            ),
            IconButton(
              tooltip: l10n.discoverNextProfile,
              onPressed: canGoForward ? onNext : null,
              color: AppColors.primary,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
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

/// Match / Astro stats row shown on verified profiles card.
class _StatsRow extends StatelessWidget {
  final AppLocalizations l10n;
  final dynamic compatibility;

  const _StatsRow({required this.l10n, required this.compatibility});

  @override
  Widget build(BuildContext context) {
    // 0 means "not computed", not "0% compatible" — the astrology engine does
    // not exist yet, so the backend sends a deliberate 0 (see
    // profile-feed.mapper.ts). Rendering it as "Astro 0%" beside a real AI
    // score reads as a computed verdict. Hidden instead, exactly as
    // CompatibilityBadge and HoroscopeSection already gate the same value.
    // The divider goes with it, so a lone AI stat carries no dangling rule.
    // Explicitly cast: `compatibility` is `dynamic` here, so the comparison
    // yields `dynamic` and strict-casts rejects it as a condition.
    final showAstro = (compatibility.astroMatchPercent as int) > 0;

    return Row(
      children: [
        Flexible(
          child: _Stat(
            label: l10n.discoverStatMatchLabel,
            value: '${compatibility.aiMatchPercent}%',
            isAccent: true,
          ),
        ),
        if (showAstro) ...[
          _Divider(),
          Flexible(
            child: _Stat(
              label: l10n.discoverStatAstroLabel,
              value: '${compatibility.astroMatchPercent}%',
              isAccent: true,
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final bool isAccent;

  const _Stat({
    required this.label,
    required this.value,
    required this.isAccent,
  });

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
            color: isAccent
                ? AppColors.accentLight
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

/// Interested (full-width gradient) + Shortlist / View Profile buttons.
class _CardButtons extends ConsumerStatefulWidget {
  final DiscoveryProfileEntity profile;

  const _CardButtons({required this.profile});

  @override
  ConsumerState<_CardButtons> createState() => _CardButtonsState();
}

class _CardButtonsState extends ConsumerState<_CardButtons> {
  bool _isSending = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(
      interestRelationshipStatusProvider(widget.profile.id),
    );
    final settled = interestButtonIsSettled(status);
    final shortlisted = ref.watch(isShortlistedProvider(widget.profile.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Interested
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _isSending
                ? null
                : () async {
                    setState(() => _isSending = true);
                    await handleInterestButtonTap(
                      context,
                      ref,
                      profile: widget.profile,
                      status: status,
                      l10n: l10n,
                    );
                    if (mounted) setState(() => _isSending = false);
                  },
            child: Ink(
              decoration: BoxDecoration(
                color: settled ? AppColors.faceVerificationGreen : null,
                borderRadius: BorderRadius.circular(16),
                boxShadow: settled ? null : AppShadows.accentGlow,
              ),
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color: settled ? AppColors.faceVerificationGreen : null,
                  gradient: settled ? null : AppGradients.accent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isSending)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else
                      Icon(
                        settled
                            ? Icons.check_circle_rounded
                            : Icons.favorite_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        interestButtonLabel(status, l10n),
                        style: AppTypography.button.copyWith(
                          color: Colors.white,
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
                icon: shortlisted
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                label: l10n.profileCardShortlist,
                onTap: () =>
                    handleShortlistToggle(context, ref, widget.profile),
                iconColor: shortlisted ? AppColors.accentLight : Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _GlassBtn(
                icon: Icons.person_rounded,
                label: l10n.actionViewProfile,
                onTap: () => openProfileDetail(
                  context,
                  widget.profile,
                  heroTag: 'profile-photo-discover-${widget.profile.id}',
                ),
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
    return NmMouseDragScroll(
      child: SingleChildScrollView(
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
      ),
    );
  }
}

class _CompactProfileCard extends ConsumerStatefulWidget {
  final DiscoveryProfileEntity profile;

  const _CompactProfileCard({required this.profile});

  @override
  ConsumerState<_CompactProfileCard> createState() =>
      _CompactProfileCardState();
}

class _CompactProfileCardState extends ConsumerState<_CompactProfileCard> {
  bool _isSending = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = widget.profile;
    final status = ref.watch(interestRelationshipStatusProvider(profile.id));
    final settled = interestButtonIsSettled(status);

    // Tapping anywhere on the card opens Profile Detail; the "Interested"
    // button below wins the gesture arena for its own tap since it's the
    // deeper, more-specific recognizer.
    return GestureDetector(
      onTap: () => openProfileDetail(
        context,
        profile,
        heroTag: 'profile-photo-discover-${profile.id}',
      ),
      child: Container(
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
                  Hero(
                    tag: 'profile-photo-discover-${profile.id}',
                    child: _CardImage(
                      photoUrls: profile.photoUrls,
                      gender: profile.gender,
                    ),
                  ),
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
                                color: AppColors.accentLight,
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
                      onPressed: _isSending
                          ? null
                          : () async {
                              setState(() => _isSending = true);
                              await handleInterestButtonTap(
                                context,
                                ref,
                                profile: profile,
                                status: status,
                                l10n: l10n,
                              );
                              if (mounted) setState(() => _isSending = false);
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: settled
                            ? AppColors.success
                            : AppColors.secondary,
                        side: BorderSide(
                          color: settled
                              ? AppColors.success
                              : AppColors.secondary,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSm,
                          ),
                        ),
                      ),
                      child: _isSending
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              interestButtonLabel(status, l10n),
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Near You — 2-column grid
// ─────────────────────────────────────────────────────────────────────────────

/// The "Near You" section of the Discover feed, backed by the real
/// location-based Nearby feature.
///
/// This is a view over [nearbyNotifierProvider] and nothing else — the same
/// notifier the dedicated Near Me screen drives. There is no second location
/// service, repository, permission flow or API call here; every branch below
/// is a rendering of a state that notifier already produces, and the two
/// surfaces therefore share one cached result.
///
/// Two consequences worth knowing:
///
///   * Opening Discover reads no location and shows no system dialog. The
///     notifier starts [NearbyIdle] and does no work until asked, so this
///     section renders its prompt from a state that cost nothing to compute.
///     Tapping "Enable Location" is the only thing that requests a fix.
///   * Loading once is loading for good. Coming back to Discover, or opening
///     the Near Me screen afterwards, reuses the already-resolved state rather
///     than issuing a second GPS read or a second `/profiles/nearby` call.
class _NearYouSection extends ConsumerStatefulWidget {
  const _NearYouSection();

  @override
  ConsumerState<_NearYouSection> createState() => _NearYouSectionState();
}

class _NearYouSectionState extends ConsumerState<_NearYouSection> {
  @override
  void initState() {
    super.initState();

    // A status check, never a prompt.
    //
    // `resolveIfIdle` asks the OS what the permission currently IS — an
    // interrogation that shows no dialog — and only goes on to read a position
    // when the answer is "already granted". Every other answer becomes a state
    // that renders a call to action here and stops. So a user who granted
    // location last week lands straight on results, and a user who has not is
    // never ambushed by a system dialog for opening Discover. The dialog has
    // exactly one trigger in this app: tapping "Enable Location", which routes
    // to `requestPermissionAndLoad` instead.
    //
    // It also no-ops unless the state is still idle, so re-entering Discover
    // reuses whatever was already resolved rather than re-reading GPS.
    //
    // Deferred off the build phase: the notifier sets state synchronously
    // before its first await, and mutating a provider mid-build throws.
    Future.microtask(
      () => ref.read(nearbyNotifierProvider.notifier).resolveIfIdle(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(nearbyNotifierProvider);
    final notifier = ref.read(nearbyNotifierProvider.notifier);

    // A resolved-but-empty result hides the section outright, matching how
    // every other section here omits itself when it has nothing to show. The
    // dedicated Near Me screen is where "nobody within 100 km" gets explained
    // at length; repeating that inside a browsing feed is just noise.
    if (state is NearbyLoaded && state.profiles.isEmpty) {
      return const SizedBox.shrink();
    }

    final Widget body = switch (state) {
      NearbyLoaded(profiles: final profiles) => _NearYouGrid(
        profiles: profiles,
      ),
      // Idle is momentary here — initState resolves it on the next microtask —
      // so it shows the same placeholder as loading rather than a call to
      // action that would flash for one frame and be replaced.
      NearbyIdle() || NearbyLoading() => const _NearYouLoading(),
      // Not granted, but the OS will still ask — so the button works.
      //
      // Invitation rather than complaint ("Find people near you", not
      // "Location access is required"): on Android this same state covers a
      // user who has simply never been asked, and scolding someone for
      // withholding something nobody requested is a poor first impression.
      // The dedicated Near Me screen keeps the firmer wording, where the user
      // has deliberately navigated to a location feature.
      NearbyPermissionRequired(isPermanentlyDenied: false) => _NearYouPrompt(
        icon: Icons.location_on_rounded,
        title: l10n.nearbyDiscoverPromptTitle,
        message: l10n.nearbyDiscoverPromptMessage(_radiusLabel),
        actionLabel: l10n.nearbyEnableLocation,
        onAction: notifier.requestPermissionAndLoad,
      ),
      // Denied for good: the OS shows nothing on a retry, so offering one
      // would be a button that cannot work. Settings is the only way back.
      // A browser has no settings screen to open: say where the site's
      // permission lives and re-check once it has been allowed.
      NearbyPermissionRequired() when kIsWeb => _NearYouPrompt(
        icon: Icons.location_off_rounded,
        title: l10n.nearbyPermissionTitle,
        message: l10n.nearbyPermissionBlockedMessageWeb,
        actionLabel: l10n.nearbyRetry,
        onAction: notifier.refresh,
      ),
      NearbyPermissionRequired() => _NearYouPrompt(
        icon: Icons.location_off_rounded,
        title: l10n.nearbyPermissionTitle,
        message: l10n.nearbyPermissionBlockedMessage,
        actionLabel: l10n.nearbyOpenSettings,
        onAction: ref.read(appPermissionServiceProvider).openSettings,
      ),
      NearbyLocationServicesOff() when kIsWeb => _NearYouPrompt(
        icon: Icons.gps_off_rounded,
        title: l10n.nearbyServicesOffTitle,
        message: l10n.nearbyPermissionBlockedMessageWeb,
        actionLabel: l10n.nearbyRetry,
        onAction: notifier.refresh,
      ),
      // Permission is irrelevant here — location is off device-wide, and the
      // fix lives on a different settings screen.
      NearbyLocationServicesOff() => _NearYouPrompt(
        icon: Icons.gps_off_rounded,
        title: l10n.nearbyServicesOffTitle,
        message: l10n.nearbyServicesOffMessage,
        actionLabel: l10n.nearbyTurnOnLocation,
        onAction: notifier.openLocationSettings,
      ),
      NearbyLocationFailure() => _NearYouPrompt(
        icon: Icons.error_outline_rounded,
        title: l10n.nearbyErrorTitle,
        message: l10n.nearbyLocationErrorMessage,
        actionLabel: l10n.nearbyRetry,
        onAction: notifier.refresh,
      ),
      // The location was fine; the request was not. Saying otherwise would
      // send the user to a settings screen that cannot help them.
      NearbyFetchFailure() => _NearYouPrompt(
        icon: Icons.cloud_off_rounded,
        title: l10n.nearbyErrorTitle,
        message: l10n.nearbyFetchErrorMessage,
        actionLabel: l10n.nearbyRetry,
        onAction: notifier.refresh,
      ),
    };

    return _SectionPadding(
      child: _FeedSection(
        title: l10n.discoverNearYouTitle,
        icon: Icons.location_on_rounded,
        iconColor: AppColors.secondary,
        child: body,
      ),
    );
  }

  /// The radius the copy quotes, kept in step with the one actually searched
  /// rather than hardcoded into a translated string.
  static String get _radiusLabel =>
      NearbyRepositoryImpl.defaultRadiusKm.round().toString();
}

/// Target tile width for the Near You grid.
///
/// Deliberately smaller than [AdaptiveGrid.resolve]'s default: with the
/// default, a 360px phone would get one full-width column, where this section
/// has always been two-up on phones. 136 is the narrowest tile the two-up
/// phone layout already uses (320px wide: (320 - 32 - 16) / 2), so every
/// width keeps tiles at least that wide and 320px stays two columns.
const double _kNearYouTargetTileWidth = 136;

/// Near You is a one-row teaser (see [_NearYouGrid]'s four-item cap), so the
/// grid never grows past four columns however wide the surface gets.
const int _kNearYouMaxColumns = 4;

/// Column count for the Near You grid and its shimmer placeholder, derived
/// from the width the section actually has rather than the window's.
int _nearYouColumns(double availableWidth) => AdaptiveGrid.resolve(
  availableWidth: availableWidth,
  horizontalPadding: AppSpacing.base * 2,
  spacing: AppSpacing.base,
  targetTileWidth: _kNearYouTargetTileWidth,
  maxColumns: _kNearYouMaxColumns,
).columns;

/// Shared by the placeholder and the real grid so their cards have the same
/// shape and the feed does not jump when results land.
SliverGridDelegate _nearYouGridDelegate(int columns) =>
    SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: AppSpacing.base,
      mainAxisSpacing: AppSpacing.base,
      childAspectRatio: 0.75,
    );

/// Placeholder while a fix is being acquired, shaped like the grid it
/// resolves into so the feed does not jump when results land.
///
/// This never touches profile data: it renders one [NmShimmer.card] per
/// column, which is exactly one row of the real grid.
class _NearYouLoading extends StatelessWidget {
  const _NearYouLoading();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _nearYouColumns(constraints.maxWidth);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: _nearYouGridDelegate(columns),
            // One row of placeholders, deliberately equal to the column count.
            itemCount: columns,
            itemBuilder: (_, __) => const NmShimmer.card(),
          ),
        );
      },
    );
  }
}

/// Inline card carrying one message and one action — the shape every
/// non-result state of [_NearYouSection] renders in.
///
/// One widget for all of them so the states cannot drift apart visually; what
/// differs between them is only the icon, the words and what the button does.
class _NearYouPrompt extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _NearYouPrompt({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: AppColors.secondary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: AppColors.secondary.withValues(alpha: 0.18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.secondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.titleSmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            SizedBox(
              width: double.infinity,
              child: NmPrimaryButton(label: actionLabel, onPressed: onAction),
            ),
          ],
        ),
      ),
    );
  }
}

class _NearYouGrid extends StatelessWidget {
  final List<DiscoveryProfileEntity> profiles;

  const _NearYouGrid({required this.profiles});

  @override
  Widget build(BuildContext context) {
    // A teaser, not the full list: the dedicated Near Me screen carries the
    // rest. The cap is a product decision, independent of the column count.
    final capped = profiles.take(4).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _nearYouColumns(constraints.maxWidth);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: _nearYouGridDelegate(columns),
            itemCount: capped.length,
            itemBuilder: (_, i) => _NearYouCard(profile: capped[i]),
          ),
        );
      },
    );
  }
}

class _NearYouCard extends ConsumerStatefulWidget {
  final DiscoveryProfileEntity profile;

  const _NearYouCard({required this.profile});

  @override
  ConsumerState<_NearYouCard> createState() => _NearYouCardState();
}

class _NearYouCardState extends ConsumerState<_NearYouCard> {
  bool _isSending = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = widget.profile;
    final status = ref.watch(interestRelationshipStatusProvider(profile.id));
    final settled = interestButtonIsSettled(status);

    return GestureDetector(
      onTap: () => openProfileDetail(
        context,
        profile,
        heroTag: 'profile-photo-discover-${profile.id}',
      ),
      child: Container(
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
            Expanded(
              child: Hero(
                tag: 'profile-photo-discover-${profile.id}',
                child: _CardImage(
                  photoUrls: profile.photoUrls,
                  gender: profile.gender,
                ),
              ),
            ),
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
                      onPressed: _isSending
                          ? null
                          : () async {
                              setState(() => _isSending = true);
                              await handleInterestButtonTap(
                                context,
                                ref,
                                profile: profile,
                                status: status,
                                l10n: l10n,
                              );
                              if (mounted) setState(() => _isSending = false);
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: settled
                            ? AppColors.success
                            : AppColors.secondary,
                        side: BorderSide(
                          color: settled
                              ? AppColors.success
                              : AppColors.secondary,
                        ),
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
                        _isSending ? '…' : interestButtonLabel(status, l10n),
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium Members — deep plum section
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
          color: AppColors.primary, // primary-container #6b21a8
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
                        color: AppColors.accentLight,
                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          l10n.discoverPremiumMembersTitle,
                          style: AppTypography.titleMedium.copyWith(
                            color: AppColors.accentLight,
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
                      color: AppColors.accentLight,
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
              child: NmMouseDragScroll(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: profiles.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.base),
                  itemBuilder: (_, i) =>
                      _PremiumMemberCard(profile: profiles[i]),
                ),
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

    // Tapping anywhere on the card opens Profile Detail; the Connect
    // button below wins the gesture arena for its own tap since it's the
    // deeper, more-specific recognizer.
    return GestureDetector(
      onTap: () => openProfileDetail(
        context,
        profile,
        heroTag: 'profile-photo-discover-${profile.id}',
      ),
      child: SizedBox(
        width: 260,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.accentLight.withValues(alpha: 0.3),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: 'profile-photo-discover-${profile.id}',
                child: _CardImage(
                  photoUrls: profile.photoUrls,
                  gender: profile.gender,
                ),
              ),
              // Gradient
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, AppColors.photoScrimMedium],
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
                        color: AppColors.accentLight,
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
                                backgroundColor: AppColors.secondary,
                                foregroundColor: AppColors.textOnSecondary,
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Footer
// ─────────────────────────────────────────────────────────────────────────────

/// Shown when the feed has no profiles in any section.
///
/// One message, deliberately. This used to branch on the backend's
/// `INCOMPLETE_SELF_PROFILE` reason and show a "Complete Your Profile" /
/// "Complete Your Story" prompt instead — which meant every member who landed
/// on Discover straight after registering was met by a profile-completion
/// call to action rather than the Discover page. Discover's landing is now
/// the same for everyone: the feed, or the plain "nothing matched yet" state
/// below.
///
/// The reason is still sent by the backend and still drives the API contract;
/// this screen simply no longer renders a completion prompt from it. Profile
/// completion remains reachable from Edit Profile, where it belongs.
class _DiscoverEmptyState extends ConsumerWidget {
  const _DiscoverEmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    final title = l10n.searchEmptyResultsTitle;
    final subtitle = l10n.searchEmptyResultsSubtitle;
    final ctaLabel = l10n.profileCompletionActionPartnerPref;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.travel_explore_rounded,
            size: 64,
            color: AppColors.secondary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          ElevatedButton(
            onPressed: () => openPartnerPreferences(context, ref),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: AppColors.textOnSecondary,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.base,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
            ),
            child: Text(
              ctaLabel,
              style: AppTypography.button.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

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
  final String gender;

  const _CardImage({required this.photoUrls, this.gender = ''});

  @override
  Widget build(BuildContext context) {
    if (photoUrls.isEmpty) return _placeholder();
    final url = photoUrls.first;
    if (url.startsWith('http')) {
      // Decodes at the card's real size instead of the source 1080² — this
      // one widget backs the AI Recommended card, the Recently Joined
      // shelf, the Near You grid and the Premium shelf, whose rendered
      // widths range from 163 to full-bleed.
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

  Widget _placeholder() => NmGenderPlaceholder(gender: gender);
}
