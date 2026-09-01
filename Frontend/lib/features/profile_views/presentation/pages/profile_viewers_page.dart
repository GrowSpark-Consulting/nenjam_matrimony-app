import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/profile_navigation.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/avatars/app_avatars.dart';
import '../../../../core/widgets/badges/premium_badge.dart';
import '../../../../core/widgets/badges/verification_badge.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/feedback/empty_state.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/profile_viewer_entity.dart';
import '../providers/profile_views_provider.dart';

/// Profile Viewers — "who viewed my profile".
///
/// The destination of a PROFILE_VIEW notification tap (see
/// `NotificationNavigationService`) and reachable from the navigation drawer.
/// Backed by `GET /matches/profile-views`, which returns distinct viewers
/// newest-first, so repeat views by the same member appear once.
///
/// ## Back behaviour
///
/// Both entry points push this page onto a real stack, so Back is an ordinary
/// [GoRouter] pop in the normal case:
///
///   * from the drawer — pushed over Discover, so Back returns to Discover
///   * from a notification — the service navigates to the Notification Center
///     *first* and pushes this page on top, so Back returns to Notifications
///
/// [openedFromNotification] only decides where Back goes when there is
/// nothing beneath this page to pop to. That happens on a cold start whose
/// very first frame is this route, where a dead Back button would otherwise
/// strand the member.
class ProfileViewersPage extends ConsumerWidget {
  const ProfileViewersPage({super.key, this.openedFromNotification = false});

  /// Whether a PROFILE_VIEW notification tap opened this page.
  ///
  /// Supplied by the router from the `openedFromNotification` query
  /// parameter — a query parameter rather than `extra` so it survives the
  /// process death / restoration path that a cold-start notification tap
  /// goes through, which `extra` does not.
  final bool openedFromNotification;

  /// Where Back goes when this page is the only entry on the stack.
  String get _fallbackRoute =>
      openedFromNotification ? RouteNames.notifications : RouteNames.discover;

  void _onBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(_fallbackRoute);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final viewersAsync = ref.watch(profileViewersNotifierProvider);
    // Whether this page sits on top of something. Fixed for as long as the
    // page is mounted — nothing is inserted beneath a route that is already
    // on screen — so reading it once per build is safe.
    final canPop = context.canPop();

    return PopScope(
      // When there is a page underneath, let the framework do the pop itself:
      // that keeps the Android system back button and the iOS swipe-back
      // gesture behaving natively. Only the no-stack case is intercepted.
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.go(_fallbackRoute);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => _onBack(context),
          ),
          title: Text(
            l10n.profileViewersTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SafeArea(
          child: viewersAsync.when(
            loading: () => const _LoadingView(),
            error: (_, __) => Center(
              child: NmErrorWidget(
                onRetry: () =>
                    ref.read(profileViewersNotifierProvider.notifier).refresh(),
              ),
            ),
            data: (viewers) => viewers.isEmpty
                ? _EmptyView(l10n: l10n)
                : RefreshIndicator(
                    onRefresh: () => ref
                        .read(profileViewersNotifierProvider.notifier)
                        .refresh(),
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: viewers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _ViewerCard(
                        key: ValueKey(viewers[index].profile.id),
                        viewer: viewers[index],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Same shape/spacing family as `ShortlistedProfileCard` — avatar + identity
/// column — with the relative view time in place of that card's action
/// button.
class _ViewerCard extends StatelessWidget {
  final ProfileViewerEntity viewer;

  const _ViewerCard({super.key, required this.viewer});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = viewer.profile;
    final details = [
      '${profile.age}',
      if (profile.location.isNotEmpty) profile.location,
      if (profile.profession.isNotEmpty) profile.profession,
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => openProfileDetail(context, profile),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.dividerLight,
            ),
          ),
          child: Row(
            children: [
              NmCircleAvatar(
                imageUrl:
                    profile.photoUrls.isEmpty ? null : profile.photoUrls.first,
                size: 56,
                gender: profile.gender,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.name,
                            style: AppTypography.titleSmall.copyWith(
                              color: AppColors.textPrimaryLight,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (profile.isVerified) ...[
                          const SizedBox(width: 6),
                          const NmVerificationBadge(),
                        ],
                        if (profile.isPremium) ...[
                          const SizedBox(width: 6),
                          const NmPremiumBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      details,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondaryLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _viewedLabel(viewer.viewedAt, l10n),
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondaryLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Coarse relative time — a viewers list only needs "recent vs a while ago",
/// and coarse buckets avoid implying a precision the throttled view log
/// doesn't have.
String _viewedLabel(DateTime viewedAt, AppLocalizations l10n) {
  final elapsed = DateTime.now().difference(viewedAt);
  if (elapsed.inMinutes < 1) return l10n.profileViewersViewedJustNow;
  if (elapsed.inHours < 1) {
    return l10n.profileViewersViewedMinutesAgo(elapsed.inMinutes);
  }
  if (elapsed.inDays < 1) {
    return l10n.profileViewersViewedHoursAgo(elapsed.inHours);
  }
  return l10n.profileViewersViewedDaysAgo(elapsed.inDays);
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => const NmShimmer.card(),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final AppLocalizations l10n;
  const _EmptyView({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: NmEmptyState(
            title: l10n.profileViewersEmptyTitle,
            message: l10n.profileViewersEmptyMessage,
            icon: Icons.visibility_outlined,
            action: SizedBox(
              width: 200,
              child: NmPrimaryButton(
                label: l10n.shortlistExploreProfiles,
                onPressed: () => context.go(RouteNames.discover),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
