import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/profile_navigation.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/tokens/app_animation_tokens.dart';
import '../../../../core/theme/tokens/app_touch_target.dart';
import '../../../../core/widgets/avatars/gender_placeholder.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../providers/matches_providers.dart';
import '../providers/reel_feed_provider.dart';

/// Nenjam Matches — Instagram Reels-style vertical swipeable feed.
///
/// Pixel-faithful translation of the Stitch "matches_reels" design:
///   • Full-screen profile photo per page (scroll-snap = PageView)
///   • Black gradient overlay top + bottom
///   • Fixed header: title + Search/New/Daily/My Matches/Near Me/More
///     Matches category selector + avatar
///   • Right-side action column: ❤ Interested / ☆ Shortlist / ↗ Share / ⚑ Report
///   • Bottom info: gold AI Match pill, name + profession, glass chips
///   • Double-tap anywhere → heart burst animation
class MatchesPage extends ConsumerStatefulWidget {
  const MatchesPage({super.key});

  @override
  ConsumerState<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends ConsumerState<MatchesPage> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
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

    return Scaffold(
      backgroundColor: AppColors.primary,
      extendBodyBehindAppBar: true,
      body: feedAsync.when(
        data: (feed) {
          if (feed.profiles.isEmpty) {
            return const _EmptyReel();
          }
          return _ReelFeed(
            profiles: feed.profiles,
            controller: _pageController,
            hasMore: feed.hasMore,
            onNearEnd: () => ref.read(reelFeedProvider.notifier).loadMore(),
          );
        },
        loading: () => const _ReelLoading(),
        error: (_, __) => Center(
          child: NmErrorWidget(
            onRetry: () => ref.invalidate(reelFeedProvider),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feed container
// ─────────────────────────────────────────────────────────────────────────────

class _ReelFeed extends StatelessWidget {
  final List<DiscoveryProfileEntity> profiles;
  final PageController controller;
  final bool hasMore;
  final VoidCallback onNearEnd;

  const _ReelFeed({
    required this.profiles,
    required this.controller,
    required this.hasMore,
    required this.onNearEnd,
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
              child: _ReelCard(profile: profiles[index]),
            );
          },
        ),

        // ── Fixed header overlay ─────────────────────────────────────
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
          colors: [Color(0x99000000), Colors.transparent],
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

    return SingleChildScrollView(
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
    );
  }
}

/// Small on-photo category pill with selected (gold gradient) / unselected
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
                    ? AppGradients.gold
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
                      color: isSelected ? AppColors.textOnGold : Colors.white,
                    ),
                    const SizedBox(width: 4),
                  ],
                  AnimatedDefaultTextStyle(
                    duration: AppAnimationTokens.normal,
                    curve: AppAnimationTokens.luxuryCurve,
                    style: AppTypography.labelSmall.copyWith(
                      color: isSelected ? AppColors.textOnGold : Colors.white,
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

class _ReelCard extends StatefulWidget {
  final DiscoveryProfileEntity profile;

  const _ReelCard({required this.profile});

  @override
  State<_ReelCard> createState() => _ReelCardState();
}

class _ReelCardState extends State<_ReelCard>
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
  bool _interested = false;
  bool _shortlisted = false;

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
      _interested = true;
    });
    _heartCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return GestureDetector(
      // Tapping anywhere on the card (outside the action column and the
      // action buttons, which win the gesture arena for their own taps
      // as the deeper/more-specific recognizers) opens Profile Detail.
      // Coexists with the double-tap-to-like below exactly the way it
      // already coexists with the action buttons — GestureDetector
      // natively defers a single tap until the double-tap window elapses
      // whenever both are registered on the same detector.
      onTap: () => openProfileDetail(context, widget.profile),
      onDoubleTapDown: _onDoubleTap,
      onDoubleTap: () {}, // needed to activate onDoubleTapDown
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Full-bleed photo ─────────────────────────────────────
            Hero(
              tag: 'profile-photo-${widget.profile.id}',
              child: _ProfilePhoto(
                photoUrls: widget.profile.photoUrls,
                gender: widget.profile.gender,
              ),
            ),

            // ── Gradient: top dark + bottom dark, clear middle ───────
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x66000000), // black/40
                    Colors.transparent,
                    Color(0xE6000000), // black/90
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),

            // ── Right action column ──────────────────────────────────
            Positioned(
              right: 16,
              bottom: 48,
              child: _ActionColumn(
                interested: _interested,
                shortlisted: _shortlisted,
                onInterested: () => setState(() => _interested = !_interested),
                onShortlist: () => setState(() => _shortlisted = !_shortlisted),
                onShare: () {},
                onReport: () {},
              ),
            ),

            // ── Bottom info area ─────────────────────────────────────
            Positioned(
              bottom: 16,
              left: 0,
              right: 80, // leave space for action column
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                ),
                child: _ProfileInfo(profile: widget.profile),
              ),
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
                          color: Color(0xFFFED977),
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
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Right-side action column
// ─────────────────────────────────────────────────────────────────────────────

class _ActionColumn extends StatelessWidget {
  final bool interested;
  final bool shortlisted;
  final VoidCallback onInterested;
  final VoidCallback onShortlist;
  final VoidCallback onShare;
  final VoidCallback onReport;

  const _ActionColumn({
    required this.interested,
    required this.shortlisted,
    required this.onInterested,
    required this.onShortlist,
    required this.onShare,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: Icons.favorite_rounded,
          label: l10n.actionInterested,
          active: interested,
          activeColor: const Color(0xFFFED977),
          onTap: onInterested,
        ),
        const SizedBox(height: 24),
        _ActionButton(
          icon: Icons.star_rounded,
          label: l10n.profileCardShortlist,
          active: shortlisted,
          activeColor: const Color(0xFFFED977),
          onTap: onShortlist,
        ),
        const SizedBox(height: 24),
        _ActionButton(
          icon: Icons.share_rounded,
          label: l10n.actionShare,
          onTap: onShare,
        ),
        const SizedBox(height: 24),
        Opacity(
          opacity: 0.6,
          child: _ActionButton(
            icon: Icons.report_rounded,
            label: '',
            onTap: onReport,
          ),
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
// Bottom profile info
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileInfo extends StatelessWidget {
  final DiscoveryProfileEntity profile;

  const _ProfileInfo({required this.profile});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // AI Match badge
        if (profile.compatibility.aiMatchPercent > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xE6FED977), // secondary-container/90
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFED977).withValues(alpha: 0.4),
                  blurRadius: 15,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 14,
                  color: Color(0xFF785D00), // on-secondary-container
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${profile.compatibility.aiMatchPercent}% ${l10n.discoverStatMatchLabel}',
                    style: AppTypography.labelMedium.copyWith(
                      color: const Color(0xFF785D00),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 12),

        // Name, age
        Text(
          '${profile.name}, ${profile.age}',
          style: AppTypography.displaySmall.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 36,
            height: 1.0,
            shadows: const [Shadow(blurRadius: 12, color: Colors.black54)],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 4),

        // Profession
        if (profile.profession.isNotEmpty)
          Text(
            profile.profession,
            style: AppTypography.bodyLarge.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
              shadows: const [Shadow(blurRadius: 8, color: Colors.black45)],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

        const SizedBox(height: 12),

        // Glass chip pills
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _chips(
            profile,
          ).map((chip) => _GlassChip(label: chip.$1, icon: chip.$2)).toList(),
        ),
      ],
    );
  }

  List<(String, IconData?)> _chips(DiscoveryProfileEntity p) {
    final chips = <(String, IconData?)>[];
    if (p.location.isNotEmpty) chips.add((p.location, null));
    if (p.height.isNotEmpty) chips.add((p.height, Icons.height_rounded));
    if (p.religion.isNotEmpty) chips.add((p.religion, null));
    if (p.community.isNotEmpty) chips.add((p.community, null));
    if (p.motherTongue.isNotEmpty) {
      chips.add((p.motherTongue, Icons.translate_rounded));
    }
    if (p.education.isNotEmpty) chips.add((p.education, Icons.school_rounded));
    if (p.maritalStatus.isNotEmpty) {
      chips.add((p.maritalStatus, Icons.favorite_border_rounded));
    }
    if (p.diet.isNotEmpty) chips.add((p.diet, Icons.restaurant_rounded));
    return chips.take(6).toList();
  }
}

class _GlassChip extends StatelessWidget {
  final String label;
  final IconData? icon;

  const _GlassChip({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile photo
// ─────────────────────────────────────────────────────────────────────────────

class _ProfilePhoto extends StatelessWidget {
  final List<String> photoUrls;
  final String gender;

  const _ProfilePhoto({required this.photoUrls, this.gender = ''});

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

  Widget _placeholder() => NmGenderPlaceholder(
    gender: gender,
    iconSize: 72,
    backgroundColor: AppColors.primaryDark,
    iconColor: const Color(0xFF374668),
  );
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
      child: CircularProgressIndicator(color: Color(0xFFFED977)),
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
              color: Color(0xFFFED977),
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
