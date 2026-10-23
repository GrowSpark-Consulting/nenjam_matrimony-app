import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/layout/window_class.dart';
import '../../../../core/router/profile_navigation.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/tokens/app_animation_tokens.dart';
import '../../../../core/theme/tokens/app_touch_target.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/widgets/cards/profile_hero_content.dart';
import '../../../../core/widgets/system_ui/nm_status_bar_style.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../../interests/domain/repositories/interests_repository.dart';
import '../../../interests/presentation/providers/interests_provider.dart';
import '../../../interests/presentation/utils/interest_button_copy.dart';
import '../../../safety/presentation/providers/blocked_users_provider.dart';
import '../../../safety/presentation/utils/show_safety_action_sheet.dart';
import '../../../shortlist/presentation/providers/shortlist_provider.dart';
import '../../../shortlist/presentation/utils/shortlist_toggle.dart';
import '../providers/matches_providers.dart';
import '../providers/reel_feed_provider.dart';
import '../../../../core/layout/mouse_drag_scroll.dart';

/// Nenjam Matches — Instagram Reels-style vertical swipeable feed.
///
/// Pixel-faithful translation of the Stitch "matches_reels" design:
///   • Full-screen profile photo per page (scroll-snap = PageView)
///   • Black gradient overlay top + bottom
///   • Fixed header: title + Search/New/Daily/My Matches/Near Me/More
///     Matches category selector + avatar
///   • Right-side action column: ❤ Interested / ☆ Shortlist / ↗ Share / ⚑ More
///     (opens the Report User / Block User sheet)
///   • Bottom info: magenta AI Match pill, name + profession, glass chips
///   • Double-tap anywhere → heart burst animation
class MatchesPage extends ConsumerStatefulWidget {
  const MatchesPage({super.key});

  @override
  ConsumerState<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends ConsumerState<MatchesPage> {
  late final PageController _pageController;
  late final ReelWheelPager _wheelPager;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _wheelPager = ReelWheelPager(_pageController);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Category selection refreshes the paginated reel (the backend serves one
    // preference-filtered feed; the category bar acts as a refresh + selector)
    // and returns to the first card.
    ref.listen<MatchCategory>(matchCategoryProvider, (previous, next) {
      if (previous != null && previous != next) {
        ref.invalidate(reelFeedProvider);
        if (_pageController.hasClients) _pageController.jumpToPage(0);
      }
    });

    final feedAsync = ref.watch(reelFeedProvider);

    // The reel is a full-bleed photo/plum background regardless of app
    // theme, so it needs status-bar icons matched to that fixed background —
    // without this it silently inherits whatever style the previously
    // active screen left behind (e.g. Discover's dark icons for its white
    // background), which are invisible against this dark one.
    return NmPageStatusBar(
      background: AppColors.primary,
      child: Scaffold(
        backgroundColor: AppColors.primary,
        extendBodyBehindAppBar: true,
        body: LayoutBuilder(
          builder: (context, constraints) {
            // Width alone would also catch a landscape phone, too short for
            // the action column beside a card; it keeps the full-bleed reel.
            final desktop =
                WindowClass.fromWidth(constraints.maxWidth).isAtLeastExpanded &&
                constraints.maxHeight >= ReelColumnMetrics.minDesktopHeight;
            final reel = feedAsync.when(
              data: (feed) {
                if (feed.profiles.isEmpty) {
                  return const _EmptyReel();
                }
                return _ReelFeed(
                  profiles: feed.profiles,
                  controller: _pageController,
                  wheelPager: _wheelPager,
                  hasMore: feed.hasMore,
                  desktop: desktop,
                  onNearEnd: () =>
                      ref.read(reelFeedProvider.notifier).loadMore(),
                );
              },
              loading: () => const _ReelLoading(),
              // See discover_page.dart's identical flag for why: keeps the
              // reel on screen through a failed background refresh (e.g. a
              // realtime `feed.invalidate`) instead of replacing it with an
              // error state.
              skipError: true,
              error: (_, __) => Center(
                child: NmErrorWidget(
                  onRetry: () => ref.invalidate(reelFeedProvider),
                ),
              ),
            );

            if (!desktop) return reel;

            // On a wide page a full-bleed reel crops portrait photos to a
            // landscape strip. Instead: the category bar as a page toolbar,
            // and under it each profile as a portrait card in the photos'
            // 9:16 shape, centered, with its actions beside it.
            return SafeArea(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.base,
                      AppSpacing.base,
                      AppSpacing.base,
                      AppSpacing.md,
                    ),
                    child: Center(child: _MatchesCategoryBar()),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.base),
                      child: LayoutBuilder(
                        builder: (context, region) {
                          final cardWidth = (region.maxHeight * 9 / 16).clamp(
                            ReelColumnMetrics.minWidth,
                            ReelColumnMetrics.maxWidth,
                          );
                          return Center(
                            child: SizedBox(
                              key: const ValueKey('matches-reel-column'),
                              width:
                                  cardWidth + ReelColumnMetrics.sideWidth * 2,
                              child: reel,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The desktop reel: card bounds, and the band either side of the card — the
/// actions on the right, an equal band on the left so the card itself is
/// centered under the toolbar.
abstract final class ReelColumnMetrics {
  /// The card's width follows the page height at the photos' 9:16 shape,
  /// within these limits.
  static const double minWidth = 360;
  static const double maxWidth = 560;

  /// Page height the desktop layout needs: the toolbar, plus a card tall
  /// enough for the four actions stacked beside it.
  static const double minDesktopHeight = 560;

  static const double actionsWidth = 80;
  static const double actionsGap = AppSpacing.base;
  static const double sideWidth = actionsWidth + actionsGap;
}

/// Moves the reel one whole profile per mouse-wheel notch.
///
/// The [PageView]'s own wheel handling scrolls by the notch's pixels and then
/// springs back to the nearest page, so on a tall reel one notch snapped back
/// to where it started and a mouse could barely leave the first profile.
/// Small trackpad deltas are summed until they add up to a notch, and nothing
/// moves again until the page animation has had time to finish, so one
/// trackpad swipe moves one profile rather than several.
class ReelWheelPager {
  final PageController controller;
  final DateTime Function() _now;

  ReelWheelPager(this.controller, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const double _notch = 50;
  static const Duration _cooldown = Duration(milliseconds: 450);

  double _pending = 0;
  DateTime _lastMove = DateTime.fromMillisecondsSinceEpoch(0);

  /// Wire to a [Listener.onPointerSignal] *inside* the [PageView]'s items:
  /// the deepest registrant wins [PointerSignalResolver], so registering
  /// there takes the event before the PageView's own handler can.
  void handle(PointerSignalEvent event, int pageCount) {
    if (event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!controller.hasClients) return;
      final now = _now();
      if (now.difference(_lastMove) < _cooldown) return;
      _pending += dy;
      if (_pending.abs() < _notch) return;
      final page = controller.page?.round() ?? 0;
      final target = _pending > 0 ? page + 1 : page - 1;
      _pending = 0;
      if (target < 0 || target >= pageCount) return;
      _lastMove = now;
      controller.animateToPage(
        target,
        duration: AppAnimationTokens.normal,
        curve: AppAnimationTokens.buttonPressCurve,
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feed container
// ─────────────────────────────────────────────────────────────────────────────

class _ReelFeed extends StatelessWidget {
  final List<DiscoveryProfileEntity> profiles;
  final PageController controller;
  final ReelWheelPager wheelPager;
  final bool hasMore;
  final VoidCallback onNearEnd;

  /// Desktop layout: the category bar is the page's toolbar instead of an
  /// overlay, and each card's actions sit beside it.
  final bool desktop;

  const _ReelFeed({
    required this.profiles,
    required this.controller,
    required this.wheelPager,
    required this.hasMore,
    required this.onNearEnd,
    this.desktop = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Reel PageView ────────────────────────────────────────────
        PageView.builder(
          controller: controller,
          scrollDirection: Axis.vertical,
          physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
          itemCount: profiles.length,
          // Fetch the next page as the user nears the end of the loaded set
          // (loadMore is a safe no-op when a request is in flight or the feed
          // is exhausted). Infinite scroll without reloading existing cards.
          onPageChanged: (index) {
            if (hasMore && index >= profiles.length - 3) onNearEnd();
          },
          itemBuilder: (context, index) {
            return _KeepAlivePage(
              key: ValueKey(profiles[index].id),
              child: Listener(
                onPointerSignal: (event) =>
                    wheelPager.handle(event, profiles.length),
                child: _ReelCard(
                  profile: profiles[index],
                  sideActions: desktop,
                ),
              ),
            );
          },
        ),

        // ── Fixed header overlay ─────────────────────────────────────
        if (!desktop)
          const Positioned(top: 0, left: 0, right: 0, child: _ReelHeader()),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fixed header
// ─────────────────────────────────────────────────────────────────────────────

class _ReelHeader extends StatelessWidget {
  const _ReelHeader();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return Container(
      padding: EdgeInsets.only(
        top: top + 8,
        left: AppSpacing.base,
        right: AppSpacing.base,
        bottom: 12,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.photoScrimVeil, Colors.transparent],
        ),
      ),
      // Category selector: Search / New / Daily / My Matches / Near Me /
      // More Matches — the only content in the header, given the full
      // width to work with.
      child: const _MatchesCategoryBar(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category selector bar
// ─────────────────────────────────────────────────────────────────────────────

/// Horizontal scrollable category selector: Search, New, Daily, My Matches,
/// Near Me, More Matches. Self-contained — reads/writes [matchCategoryProvider]
/// directly so it rebuilds independently of the reel [PageView] below it.
class _MatchesCategoryBar extends ConsumerStatefulWidget {
  const _MatchesCategoryBar();

  @override
  ConsumerState<_MatchesCategoryBar> createState() =>
      _MatchesCategoryBarState();
}

class _MatchesCategoryBarState extends ConsumerState<_MatchesCategoryBar> {
  final _scrollController = ScrollController();
  final Map<MatchCategory, GlobalKey> _chipKeys = {
    for (final category in MatchCategory.values) category: GlobalKey(),
  };

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onCategorySelected(MatchCategory category) {
    // Near Me is a navigation shortcut rather than a feed filter — the same
    // exception the Search chip above already makes. It needs device location,
    // and its permission / services-off / empty states have nowhere to render
    // inside a swipeable reel, so it opens the dedicated screen. Selection
    // state is deliberately not changed: the user comes back to whichever
    // category they were actually on.
    if (category == MatchCategory.nearMe) {
      context.push(RouteNames.nearby);
      return;
    }

    ref.read(matchCategoryProvider.notifier).state = category;
    final chipContext = _chipKeys[category]?.currentContext;
    if (chipContext != null) {
      Scrollable.ensureVisible(
        chipContext,
        duration: AppAnimationTokens.normal,
        curve: AppAnimationTokens.luxuryCurve,
        alignment: 0.5,
      );
    }
  }

  String _labelFor(MatchCategory category, AppLocalizations l10n) {
    switch (category) {
      case MatchCategory.newProfiles:
        return l10n.matchesCategoryNew;
      case MatchCategory.daily:
        return l10n.matchesCategoryDaily;
      case MatchCategory.myMatches:
        return l10n.matchesCategoryMyMatches;
      case MatchCategory.nearMe:
        return l10n.matchesCategoryNearMe;
      case MatchCategory.moreMatches:
        return l10n.matchesCategoryMoreMatches;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(matchCategoryProvider);

    return NmMouseDragScroll(
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search is a pure navigation shortcut — not a MatchCategory, so
            // it never carries selected state. Pushed (not `go`) so Matches
            // stays on the navigator stack — back returns to this exact
            // instance with its state intact, per the app-wide rule that
            // temporary/secondary pages use push, not replace.
            _MatchesCategoryChip(
              label: l10n.matchesCategorySearch,
              icon: Icons.search_rounded,
              isSelected: false,
              onTap: () => context.push(RouteNames.search),
            ),
            const SizedBox(width: AppSpacing.sm),
            for (final category in MatchCategory.values) ...[
              _MatchesCategoryChip(
                key: _chipKeys[category],
                label: _labelFor(category, l10n),
                isSelected: category == selected,
                onTap: () => _onCategorySelected(category),
              ),
              if (category != MatchCategory.values.last)
                const SizedBox(width: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small on-photo category pill with selected (magenta gradient) / unselected
/// (frosted-glass) states — mirrors the Discover reel's tab styling so both
/// reel-style feeds share the same "Nenjam" on-photo selector language.
class _MatchesCategoryChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _MatchesCategoryChip({
    super.key,
    required this.label,
    this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouchTarget.minSize),
          child: Center(
            child: AnimatedContainer(
              duration: AppAnimationTokens.normal,
              curve: AppAnimationTokens.luxuryCurve,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? AppGradients.accent
                    : AppGradients.cardGlass,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                border: isSelected
                    ? null
                    : Border.all(color: Colors.white.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 15,
                      color: isSelected
                          ? AppColors.textOnSecondary
                          : Colors.white,
                    ),
                    const SizedBox(width: 4),
                  ],
                  AnimatedDefaultTextStyle(
                    duration: AppAnimationTokens.normal,
                    curve: AppAnimationTokens.luxuryCurve,
                    style: AppTypography.labelSmall.copyWith(
                      color: isSelected
                          ? AppColors.textOnSecondary
                          : Colors.white,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    child: Text(
                      label,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single reel card
// ─────────────────────────────────────────────────────────────────────────────

class _ReelCard extends ConsumerStatefulWidget {
  final DiscoveryProfileEntity profile;

  /// Actions beside the card (desktop) instead of over the photo.
  final bool sideActions;

  const _ReelCard({required this.profile, this.sideActions = false});

  @override
  ConsumerState<_ReelCard> createState() => _ReelCardState();
}

class _ReelCardState extends ConsumerState<_ReelCard>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  // Heart burst
  bool _showHeart = false;
  Offset _heartPosition = Offset.zero;
  late final AnimationController _heartCtrl;
  late final Animation<double> _heartScale;
  late final Animation<double> _heartOpacity;

  // Action states
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _heartCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.5), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.5, end: 1.2), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 2.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _heartCtrl, curve: Curves.easeOut));
    _heartOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(_heartCtrl);

    _heartCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) setState(() => _showHeart = false);
      }
    });
  }

  @override
  void dispose() {
    _heartCtrl.dispose();
    super.dispose();
  }

  void _onDoubleTap(TapDownDetails details) {
    setState(() {
      _showHeart = true;
      _heartPosition = details.localPosition;
    });
    _heartCtrl.forward(from: 0);
    _sendInterest();
  }

  /// Web only: the browser has an address for every profile
  /// (`/profile-detail/:id`), so Share copies it. The link is still behind
  /// the sign-in guard, so it shows the profile only to a signed-in member.
  Future<void> _copyProfileLink() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final link = Uri.base
        .resolve(RouteNames.profileDetailPath(widget.profile.id))
        .toString();
    await Clipboard.setData(ClipboardData(text: link));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.profileLinkCopied)));
  }

  Future<void> _sendInterest() async {
    if (_isSending) return;
    final status = ref.read(
      interestRelationshipStatusProvider(widget.profile.id),
    );
    if (status != InterestRelationshipStatus.none &&
        status != InterestRelationshipStatus.cancelled) {
      return;
    }
    setState(() => _isSending = true);
    await handleInterestButtonTap(
      context,
      ref,
      profile: widget.profile,
      status: status,
      l10n: AppLocalizations.of(context),
    );
    if (mounted) setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final status = ref.watch(
      interestRelationshipStatusProvider(widget.profile.id),
    );
    final settled = interestButtonIsSettled(status);
    final shortlisted = ref.watch(isShortlistedProvider(widget.profile.id));

    final actions = _ActionColumn(
      interested: settled,
      interestedLabel: interestButtonLabel(
        status,
        AppLocalizations.of(context),
      ),
      shortlisted: shortlisted,
      onInterested: _sendInterest,
      onShortlist: () => handleShortlistToggle(context, ref, widget.profile),
      onShare: kIsWeb ? _copyProfileLink : () {},
      onMore: () => showSafetyActionSheet(
        context,
        ref,
        userId: widget.profile.id,
        userName: widget.profile.name,
        onBlocked: () {
          ref.read(reelFeedProvider.notifier).removeProfile(widget.profile.id);
          // So this member shows up next time the Blocked Users list
          // (Privacy & Safety) is opened, even if it was already loaded
          // before this block happened.
          ref.invalidate(blockedUsersNotifierProvider);
        },
      ),
    );

    final card = GestureDetector(
      // Tapping anywhere on the card (outside the action column and the
      // action buttons, which win the gesture arena for their own taps
      // as the deeper/more-specific recognizers) opens Profile Detail.
      // Coexists with the double-tap-to-like below exactly the way it
      // already coexists with the action buttons — GestureDetector
      // natively defers a single tap until the double-tap window elapses
      // whenever both are registered on the same detector.
      onTap: () => openProfileDetail(
        context,
        widget.profile,
        heroTag: 'profile-photo-matches-${widget.profile.id}',
      ),
      onDoubleTapDown: _onDoubleTap,
      onDoubleTap: () {}, // needed to activate onDoubleTapDown
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Full-bleed photo ─────────────────────────────────────
            Hero(
              tag: 'profile-photo-matches-${widget.profile.id}',
              child: NmProfileHeroPhoto(
                photoUrls: widget.profile.photoUrls,
                gender: widget.profile.gender,
              ),
            ),

            // ── Gradient: top dark + bottom dark, clear middle ───────
            const NmProfileHeroScrim(),

            // ── Right action column ──────────────────────────────────
            // The card runs to the physical bottom of the screen (the shell
            // draws the floating nav over it), so the pill's own height is
            // added to the offset — otherwise the lowest buttons sit behind
            // the pill, which also swallows their taps.
            if (!widget.sideActions)
              Positioned(
                right: 16,
                bottom: 48 + MediaQuery.paddingOf(context).bottom,
                child: actions,
              ),

            // ── Bottom info area ─────────────────────────────────────
            // Same widget Profile Detail's hero uses; the gutter it leaves on
            // the right is the space the action column above occupies.
            //
            // bottomInset is what keeps the name and the metadata chips
            // (location, height, religion, education, ...) above the floating
            // nav: the reel card is full-bleed to the bottom of the screen, so
            // without it the last chip row renders underneath the pill.
            NmProfileHeroOverlay(
              profile: widget.profile,
              bottomInset: MediaQuery.paddingOf(context).bottom,
            ),

            // ── Heart burst animation ────────────────────────────────
            if (_showHeart)
              Positioned(
                left: _heartPosition.dx - 50,
                top: _heartPosition.dy - 50,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _heartCtrl,
                    builder: (_, __) => Opacity(
                      opacity: _heartOpacity.value,
                      child: Transform.scale(
                        scale: _heartScale.value,
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: AppColors.accentLight,
                          size: 100,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (!widget.sideActions) return card;

    // Desktop: a rounded card with its actions beside it, an equal band on
    // the left keeping the card centered, and a gap between consecutive
    // cards.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SizedBox(width: ReelColumnMetrics.sideWidth),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
              child: card,
            ),
          ),
          const SizedBox(width: ReelColumnMetrics.actionsGap),
          SizedBox(
            width: ReelColumnMetrics.actionsWidth,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: actions,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Right-side action column
// ─────────────────────────────────────────────────────────────────────────────

class _ActionColumn extends StatelessWidget {
  final bool interested;
  final String interestedLabel;
  final bool shortlisted;
  final VoidCallback onInterested;
  final VoidCallback onShortlist;
  final VoidCallback onShare;
  final VoidCallback onMore;

  const _ActionColumn({
    required this.interested,
    required this.interestedLabel,
    required this.shortlisted,
    required this.onInterested,
    required this.onShortlist,
    required this.onShare,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: Icons.favorite_rounded,
          label: interestedLabel,
          active: interested,
          activeColor: AppColors.accentLight,
          onTap: onInterested,
        ),
        const SizedBox(height: 24),
        _ActionButton(
          // Bookmark (not star) to match Discover/Search's icon for the
          // same concept — filled once shortlisted, outlined otherwise.
          icon: shortlisted
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          label: l10n.profileCardShortlist,
          active: shortlisted,
          activeColor: AppColors.accentLight,
          onTap: onShortlist,
        ),
        const SizedBox(height: 24),
        _ActionButton(
          icon: Icons.share_rounded,
          label: l10n.actionShare,
          onTap: onShare,
        ),
        const SizedBox(height: 24),
        _ActionButton(
          icon: Icons.flag_rounded,
          label: l10n.profileDetailMoreLabel,
          onTap: onMore,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color activeColor;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? activeColor.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.15),
              border: Border.all(
                color: active
                    ? activeColor.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(
              icon,
              size: 24,
              color: active ? activeColor : Colors.white,
            ),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 64),
              child: Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  shadows: const [
                    Shadow(blurRadius: 10, color: Colors.black54),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Keep-alive page wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _KeepAlivePage extends StatefulWidget {
  final Widget child;

  const _KeepAlivePage({super.key, required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading & empty states
// ─────────────────────────────────────────────────────────────────────────────

class _ReelLoading extends StatelessWidget {
  const _ReelLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.accentLight),
    );
  }
}

class _EmptyReel extends StatelessWidget {
  const _EmptyReel();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.favorite_border_rounded,
              size: 64,
              color: AppColors.accentLight,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.matchesEmptyTitle,
              textAlign: TextAlign.center,
              style: AppTypography.titleMedium.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.matchesEmptySubtitle,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
