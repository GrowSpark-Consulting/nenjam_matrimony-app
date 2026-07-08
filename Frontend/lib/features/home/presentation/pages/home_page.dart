import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/premium_banner.dart';
import '../../../../core/widgets/cards/profile_card.dart';
import '../../../../core/widgets/cards/profile_completion_card.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/discovery_profile_entity.dart';
import '../../domain/entities/home_feed_entity.dart';
import '../providers/home_providers.dart';

/// Nenjam Home Feed — dashboard: profile completion, premium upsell, and
/// horizontally-scrolling recommendation rows. The full-screen swipeable
/// discovery experience lives on the Discover tab, not here.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(homeFeedProvider);

    return Scaffold(
      body: feedAsync.when(
        data: (feed) => _HomeDashboard(feed: feed),
        loading: () => const _HomeLoading(),
        error: (error, stackTrace) => Center(
          child: NmErrorWidget(
            onRetry: () => ref.invalidate(homeFeedProvider),
          ),
        ),
      ),
    );
  }
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: AppSpacing.pagePadding,
        children: const [
          NmShimmer(height: 96, borderRadius: AppSpacing.radiusXl),
          SizedBox(height: AppSpacing.xl2),
          NmShimmer(height: 140, borderRadius: AppSpacing.radiusXl),
          SizedBox(height: AppSpacing.xl2),
          NmShimmerProfileCard(),
        ],
      ),
    );
  }
}

class _HomeDashboard extends ConsumerWidget {
  final HomeFeedEntity feed;

  const _HomeDashboard({required this.feed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(homeFeedProvider.future),
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            elevation: 0,
            title: Text(
              l10n.appName,
              style: AppTypography.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              Semantics(
                button: true,
                label: l10n.notificationsTitle,
                child: IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_none_rounded),
                ),
              ),
              Semantics(
                button: true,
                label: l10n.homeFilterLabel,
                child: IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.tune_rounded),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
          ),
          SliverPadding(
            padding: AppSpacing.pageHorizontal,
            sliver: SliverToBoxAdapter(
              child: NmProfileCompletionCard(
                percentage: feed.profileCompletionPercent,
                nextStep: l10n.homeStepUploadHoroscope,
              ),
            ),
          ),
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.xl2, AppSpacing.lg, 0,
            ),
            sliver: SliverToBoxAdapter(child: NmPremiumBanner()),
          ),
          if (feed.aiRecommended.isNotEmpty)
            _HorizontalSection(
              title: l10n.homeAiRecommendationsTitle,
              icon: Icons.auto_awesome_rounded,
              profiles: feed.aiRecommended,
            ),
          if (feed.recentlyJoined.isNotEmpty)
            _HorizontalSection(
              title: l10n.homeRecentlyJoinedTitle,
              profiles: feed.recentlyJoined,
            ),
          if (feed.verifiedProfiles.isNotEmpty)
            _HorizontalSection(
              title: l10n.homeVerifiedProfilesTitle,
              icon: Icons.verified_rounded,
              profiles: feed.verifiedProfiles,
            ),
          if (feed.premiumMembers.isNotEmpty)
            _HorizontalSection(
              title: l10n.homePremiumMembersTitle,
              icon: Icons.workspace_premium_rounded,
              profiles: feed.premiumMembers,
            ),
          if (feed.nearYou.isNotEmpty)
            _HorizontalSection(
              title: l10n.homeNearYouTitle,
              icon: Icons.location_on_rounded,
              profiles: feed.nearYou,
            ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl3)),
        ],
      ),
    );
  }
}

class _HorizontalSection extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<DiscoveryProfileEntity> profiles;

  const _HorizontalSection({
    required this.title,
    required this.profiles,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xl2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: AppSpacing.pageHorizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 20, color: AppColors.accentGold),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        Flexible(
                          child: Text(
                            title,
                            style: AppTypography.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: Text(l10n.homeSeeAllButton),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 296,
              child: ListView.separated(
                padding: AppSpacing.pageHorizontal,
                scrollDirection: Axis.horizontal,
                itemCount: profiles.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.base),
                itemBuilder: (context, index) {
                  return SizedBox(
                    width: 176,
                    child: _ProfileTile(profile: profiles[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adapts a [DiscoveryProfileEntity] onto the existing [NmProfileCard] grid
/// widget so Home doesn't grow a second, near-duplicate compact card —
/// the same reusable card that powered the original Home dashboard.
class _ProfileTile extends StatelessWidget {
  final DiscoveryProfileEntity profile;

  const _ProfileTile({required this.profile});

  @override
  Widget build(BuildContext context) {
    return NmProfileCard(
      name: profile.name,
      age: '${profile.age}',
      location: profile.distanceKm != null
          ? '${profile.distanceKm!.toStringAsFixed(1)} km'
          : profile.location,
      imageUrl: profile.photoUrls.isNotEmpty ? profile.photoUrls.first : null,
      profession: profile.profession,
      isVerified: profile.isVerified,
      isPremium: profile.isPremium,
      isOnline: profile.isOnline,
      onLikeTap: () {},
      onShortlistTap: () {},
    );
  }
}
