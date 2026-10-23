import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/inbox/presentation/providers/inbox_providers.dart';
import '../../../features/notifications/presentation/providers/notification_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../constants/app_spacing.dart';
import '../../layout/rail_inset.dart';
import '../../layout/window_class.dart';
import '../../router/route_names.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_gradients.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_typography.dart';
import '../../theme/tokens/app_radius.dart';
import 'nav_badge.dart';

/// Width of the desktop navigation rail.
///
/// The rail is a *sibling* of the routed pages in [NmDesktopFrame]'s Row, so
/// content never has to subtract it — a content-level LayoutBuilder already
/// receives the post-rail width.
abstract final class NavRailMetrics {
  static const double width = AppSpacing.xl8; // 96
}

/// Bottom clearance a page's scrollable content needs so its last item can
/// scroll clear of the floating pill instead of ending up underneath it.
///
/// There is deliberately nothing to measure or hardcode here. [AppBottomNavShell]
/// sets `extendBody: true`, and Flutter's own `Scaffold` responds by publishing
/// `max(viewPadding.bottom, <height of the bottomNavigationBar widget>)` as the
/// body's `MediaQuery.padding.bottom` (see `_BodyBuilder` in Scaffold's source).
/// That number is the pill's real laid-out height plus its SafeArea margin, on
/// this device, at this text scale — so reading it back covers the floating bar,
/// the system navigation area and gesture insets in one value, and adapts by
/// itself when any of them change.
///
/// [gap] is the breathing room between the last content and the top of the pill.
///
/// Safe to call from a page that is not inside the shell: a pushed route has no
/// pill over it, so `padding.bottom` is just the system inset and this returns
/// that plus the gap.
double navContentInset(BuildContext context, {double gap = AppSpacing.base}) =>
    MediaQuery.paddingOf(context).bottom + gap;

/// The four shell tabs, index-aligned with `app_router.dart`'s branch order
/// and with [kShellTabPaths].
const _tabs = [
  _NavTab(Icons.explore_rounded, Icons.explore_outlined),
  _NavTab(Icons.favorite_rounded, Icons.favorite_border_rounded),
  _NavTab(Icons.chat_bubble_rounded, Icons.chat_bubble_outline_rounded),
  _NavTab(Icons.workspace_premium_rounded, Icons.workspace_premium_outlined),
];

/// Index of the Inbox tab in [_tabs].
const _inboxTabIndex = 2;

List<String> _tabLabels(AppLocalizations l10n) => [
  l10n.navDiscover,
  l10n.navMatches,
  l10n.navMessages,
  l10n.navPremium,
];

/// Paths of the four shell tabs, in branch order.
const List<String> kShellTabPaths = [
  RouteNames.discover,
  RouteNames.matches,
  RouteNames.messages,
  RouteNames.premium,
];

/// Shell for the tabbed routes — Discover / Matches / Inbox / Premium — with
/// the floating pill navigation on phones and tablets.
///
/// Backed by a [StatefulShellRoute.indexedStack] (see `app_router.dart`):
/// [navigationShell] itself renders whichever branch is active inside an
/// `IndexedStack`, so switching tabs preserves each branch's own Navigator
/// stack and scroll position instead of rebuilding it from scratch.
///
/// Where [NmDesktopFrame] draws its rail, that rail is the navigation and this
/// shows the page alone.
class AppBottomNavShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AppBottomNavShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = navigationShell.currentIndex;
    final l10n = AppLocalizations.of(context);
    final labels = _tabLabels(l10n);
    // App-wide unread message total, summed from the conversations list (see
    // `unreadMessagesCountProvider`). Watching it here means the badge tracks
    // every path that touches unread state — a live socket message, opening a
    // thread, mark read/unread, a reconnect or foreground re-sync — without
    // any of them knowing this widget exists.
    final unreadMessages = ref.watch(unreadMessagesCountProvider);
    const surfaceColor = AppColors.surfaceLight;
    final showPill = NmRailInset.of(context) == 0;

    // Android/iOS back button: only the Discover branch is a true "root" —
    // every other branch was reached by switching tabs, not by pushing on
    // top of Discover, so there's nothing underneath it in ITS OWN branch
    // stack to pop back to. Intercept the back gesture there and switch to
    // the Discover branch instead of letting the OS close the app; only
    // allow the real pop (app exit) from Discover itself. Routes pushed on
    // top of any branch (Search, Edit Profile, wizard steps, ...) are
    // unaffected — they live above this as root-navigator pages, so the OS
    // back button already pops them first as normal.
    return PopScope(
      canPop: currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        navigationShell.goBranch(0);
      },
      child: Scaffold(
        // Lets each page's body paint all the way to the bottom of the
        // screen instead of stopping above a reserved bottomNavigationBar
        // slot — without this, Flutter fills that slot with this Scaffold's
        // own opaque scaffoldBackgroundColor, which shows as a full-width
        // rectangle behind (and around) the pill on every page, regardless
        // of that page's own background. With it, only the pill itself
        // paints, and whatever page is underneath shows through beside it.
        extendBody: true,
        body: navigationShell,
        bottomNavigationBar: showPill
            ? SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(
                  AppSpacing.base,
                  0,
                  AppSpacing.base,
                  AppSpacing.sm,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: AppRadius.pill,
                    boxShadow: AppShadows.floatingLight,
                  ),
                  // No fixed height — the bar sizes itself to each _NavItem's
                  // intrinsic content (icon badge + label), so it can never clip
                  // at large text-scale settings the way a hardcoded height did.
                  child: Row(
                    children: [
                      for (var index = 0; index < _tabs.length; index++)
                        Expanded(
                          child: _NavItem(
                            icon: _tabs[index].icon,
                            activeIcon: _tabs[index].activeIcon,
                            label: labels[index],
                            isActive: index == currentIndex,
                            badgeCount: index == _inboxTabIndex
                                ? unreadMessages
                                : 0,
                            // Announced instead of the bare count, so the
                            // badge reads as "Inbox, 3 unread messages"
                            // rather than "Inbox" and a loose "3" (see
                            // [NavBadge]'s own ExcludeSemantics).
                            badgeSemanticLabel: l10n
                                .navUnreadMessagesSemanticLabel(unreadMessages),
                            // The badge's ring should read as a cut-out in
                            // the bar, so it takes the bar's own colour.
                            badgeBorderColor: surfaceColor,
                            // initialLocation resets the branch to its
                            // starting route when re-tapping the tab you're
                            // already on — the standard go_router pattern —
                            // while switching between different tabs
                            // preserves each one's state.
                            onTap: () => navigationShell.goBranch(
                              index,
                              initialLocation: index == currentIndex,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// The app's desktop chrome: from [WindowClass.expanded] up, a
/// [NmNavigationRail] beside every signed-in page — the four tabs and the
/// pages pushed over them alike — so navigation never disappears behind a
/// pushed route.
///
/// Wraps the router's Navigator (main.dart's `MaterialApp.router` builder), so
/// it changes no route, path, guard or back behavior. Public routes — splash,
/// sign-in, onboarding, face verification — get no rail.
class NmDesktopFrame extends StatefulWidget {
  final GoRouter router;
  final Widget child;

  /// The tab destinations, in rail order.
  final List<String> tabPaths;

  const NmDesktopFrame({
    super.key,
    required this.router,
    required this.child,
    this.tabPaths = kShellTabPaths,
  });

  @override
  State<NmDesktopFrame> createState() => _NmDesktopFrameState();
}

class _NmDesktopFrameState extends State<NmDesktopFrame> {
  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_onRouteChanged);
  }

  @override
  void didUpdateWidget(NmDesktopFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routerDelegate.removeListener(_onRouteChanged);
      widget.router.routerDelegate.addListener(_onRouteChanged);
    }
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_onRouteChanged);
    super.dispose();
  }

  /// The delegate can notify while the Router below is building, when this
  /// frame may not be marked dirty; the rebuild then waits for that frame to
  /// finish.
  void _onRouteChanged() {
    if (!mounted) return;
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      scheduler.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  String? _currentLocation() {
    final config = widget.router.routerDelegate.currentConfiguration;
    if (config.isEmpty) return null;
    return config.last.matchedLocation;
  }

  static bool _railVisibleAt(String location) =>
      !RouteNames.publicRoutes.contains(location) &&
      !location.startsWith(RouteNames.registration);

  @override
  Widget build(BuildContext context) {
    final wide = WindowClass.of(context).isAtLeastExpanded;
    final location = wide ? _currentLocation() : null;
    final showRail = location != null && _railVisibleAt(location);
    final railWidth = showRail ? NavRailMetrics.width : 0.0;
    return NmRailInset(
      width: railWidth,
      // A Stack rather than a Row so the rail paints *after* the pages: each
      // route carries a BlockSemantics, which drops the semantics of whatever
      // was painted before it — a rail painted first would be invisible to
      // screen readers. The pages stay the first child, so the Navigator's
      // place in the tree never moves as the rail comes and goes.
      child: Stack(
        children: [
          PositionedDirectional(
            start: railWidth,
            top: 0,
            end: 0,
            bottom: 0,
            child: widget.child,
          ),
          if (showRail)
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              width: railWidth,
              child: _FrameRail(
                router: widget.router,
                location: location,
                tabPaths: widget.tabPaths,
              ),
            ),
        ],
      ),
    );
  }
}

/// The frame's rail: the four tabs, then notifications, profile and the
/// account menu at the bottom.
class _FrameRail extends ConsumerWidget {
  final GoRouter router;
  final String location;
  final List<String> tabPaths;

  const _FrameRail({
    required this.router,
    required this.location,
    required this.tabPaths,
  });

  int? _activeTab() {
    // A conversation opened from the Inbox is still the Inbox.
    if (location.startsWith('${RouteNames.chatDetail}/')) {
      final inbox = tabPaths.indexOf(RouteNames.messages);
      return inbox < 0 ? null : inbox;
    }
    for (var i = 0; i < tabPaths.length; i++) {
      final path = tabPaths[i];
      if (location == path || location.startsWith('$path/')) return i;
    }
    return null;
  }

  /// Pushed, like the Discover avatar and bell already do, so Back returns to
  /// the page underneath.
  void _open(String path) {
    if (location != path) router.push(path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final labels = _tabLabels(l10n);
    final unreadMessages = ref.watch(unreadMessagesCountProvider);
    final unreadNotifications = ref.watch(unreadNotificationsCountProvider);
    final activeTab = _activeTab();
    const surface = AppColors.surfaceLight;

    return NmNavigationRail(
      leading: _BrandMark(onTap: () => router.go(tabPaths.first)),
      footer: [
        _NavItem(
          icon: Icons.notifications_none_rounded,
          activeIcon: Icons.notifications_rounded,
          label: l10n.notificationsTitle,
          isActive: location == RouteNames.notifications,
          badgeCount: unreadNotifications,
          badgeSemanticLabel: '$unreadNotifications',
          badgeBorderColor: surface,
          onTap: () => _open(RouteNames.notifications),
        ),
        _NavItem(
          icon: Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          label: l10n.navProfile,
          isActive: location == RouteNames.profile,
          onTap: () => _open(RouteNames.profile),
        ),
        _NavItem(
          icon: Icons.menu_rounded,
          activeIcon: Icons.menu_rounded,
          label: l10n.navMore,
          isActive: location == RouteNames.profileMenu,
          onTap: () => _open(RouteNames.profileMenu),
        ),
      ],
      children: [
        for (var index = 0; index < _tabs.length; index++)
          _NavItem(
            icon: _tabs[index].icon,
            activeIcon: _tabs[index].activeIcon,
            label: labels[index],
            isActive: index == activeTab,
            badgeCount: index == _inboxTabIndex ? unreadMessages : 0,
            badgeSemanticLabel: l10n.navUnreadMessagesSemanticLabel(
              unreadMessages,
            ),
            badgeBorderColor: surface,
            // `go` switches to the tab like the pill does: the shell keeps
            // each tab's own state, and pages pushed over it are left.
            onTap: () => router.go(tabPaths[index]),
          ),
      ],
    );
  }
}

/// Left-hand navigation for [WindowClass.expanded] and wider: [leading] at the
/// top, the primary destinations under it, and [footer] pinned to the bottom.
///
/// Fills the window's height and scrolls rather than overflowing on a short
/// window. Separated from the page by surface colour rather than a border.
class NmNavigationRail extends StatelessWidget {
  final Widget? leading;
  final List<Widget> children;
  final List<Widget> footer;

  const NmNavigationRail({
    super.key,
    this.leading,
    required this.children,
    this.footer = const [],
  });

  @override
  Widget build(BuildContext context) {
    // A Material so the items' ink splashes paint on the rail.
    return Material(
      key: const ValueKey('desktop-nav-rail'),
      color: AppColors.surfaceLight,
      child: SizedBox(
        width: NavRailMetrics.width,
        child: SafeArea(
          right: false,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              // At least the window's height, so spaceBetween can pin the
              // footer to the bottom; taller content scrolls instead.
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.lg,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (leading != null) ...[
                            leading!,
                            const SizedBox(height: AppSpacing.xl),
                          ],
                          for (final item in children)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.md,
                              ),
                              child: item,
                            ),
                        ],
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final item in footer)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.md,
                              ),
                              child: item,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The splash screen's heart mark, on the brand gradient so it reads on the
/// white rail. Goes to Discover, as a logo goes home.
class _BrandMark extends StatelessWidget {
  final VoidCallback onTap;

  const _BrandMark({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).appNameShort,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: AppGradients.primary,
            borderRadius: radius,
          ),
          child: const ExcludeSemantics(
            child: Icon(Icons.favorite_rounded, size: 24, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  /// Unread count overlaid on this item's icon — 0 on every item that doesn't
  /// have one, which [NavBadge] renders as scaled-to-nothing rather than
  /// absent, so the pop-in animation has something to animate from.
  final int badgeCount;
  final String badgeSemanticLabel;
  final Color badgeBorderColor;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.badgeCount = 0,
    this.badgeSemanticLabel = '',
    this.badgeBorderColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    const inactiveColor = AppColors.textTertiaryLight;
    const activeLabelColor = AppColors.textPrimaryLight;

    return Semantics(
      button: true,
      label: badgeCount > 0 ? '$label, $badgeSemanticLabel' : label,
      selected: isActive,
      child: InkWell(
        borderRadius: AppRadius.br16,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The badge floats over the icon's top-right corner. The Stack
              // takes its size from the (unpositioned) icon circle, so adding
              // the badge changes nothing about the layout — it overhangs the
              // circle's corner without widening the item or shifting the
              // label below it.
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    width: AppSpacing.xl3,
                    height: AppSpacing.xl3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? AppColors.primary : Colors.transparent,
                      boxShadow: isActive ? AppShadows.button : null,
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          isActive ? activeIcon : icon,
                          key: ValueKey(isActive),
                          size: 20,
                          color: isActive ? Colors.white : inactiveColor,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: NavBadge(
                      count: badgeCount,
                      borderColor: badgeBorderColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs2),
              // Scaled down to fit under the icon rather than overflowing.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 250),
                    style: AppTypography.labelSmall.copyWith(
                      color: isActive ? activeLabelColor : inactiveColor,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs2),
              // Magenta active indicator bar — same visual language as the
              // tab-chip underline used elsewhere (discover top bar, matches
              // header), so the active item reads clearly at a glance.
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                width: isActive ? AppSpacing.md : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(AppSpacing.xs2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTab {
  final IconData activeIcon;
  final IconData icon;

  const _NavTab(this.activeIcon, this.icon);
}
