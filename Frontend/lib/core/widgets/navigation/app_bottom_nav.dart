import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/inbox/presentation/providers/inbox_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../constants/app_spacing.dart';
import '../../layout/window_class.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_typography.dart';
import '../../theme/tokens/app_radius.dart';
import 'nav_badge.dart';

/// Explicit widths for the two navigation-rail variants.
///
/// The rail is a *sibling* of the page content in the shell's Row, so content
/// never has to subtract these itself — a content-level LayoutBuilder already
/// receives the post-rail width.
abstract final class NavRailMetrics {
  /// Icon-only rail, shown at [WindowClass.expanded].
  static const double compactWidth = AppSpacing.xl8; // 96

  /// Icon + label rail, shown at [WindowClass.large].
  static const double extendedWidth = 240;
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

/// Floating pill-style bottom navigation shell that wraps tabbed routes —
/// Discover / Matches / Inbox / Premium.
///
/// Backed by a [StatefulShellRoute.indexedStack] (see `app_router.dart`):
/// [navigationShell] itself renders whichever branch is active inside an
/// `IndexedStack`, so switching tabs preserves each branch's own Navigator
/// stack and scroll position instead of rebuilding it from scratch.
class AppBottomNavShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AppBottomNavShell({super.key, required this.navigationShell});

  static const _tabs = [
    _NavTab(Icons.explore_rounded, Icons.explore_outlined),
    _NavTab(Icons.favorite_rounded, Icons.favorite_border_rounded),
    _NavTab(Icons.chat_bubble_rounded, Icons.chat_bubble_outline_rounded),
    _NavTab(Icons.workspace_premium_rounded, Icons.workspace_premium_outlined),
  ];

  /// Index of the Inbox branch in [_tabs] — and in `app_router.dart`'s branch
  /// order, which the two lists share.
  static const _inboxTabIndex = 2;

  /// Localized labels, index-aligned with [_tabs] and with the branch order
  /// declared in `app_router.dart`.
  List<String> _labels(AppLocalizations l10n) => [
    l10n.navDiscover,
    l10n.navMatches,
    l10n.navMessages,
    l10n.navPremium,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = navigationShell.currentIndex;
    final l10n = AppLocalizations.of(context);
    final labels = _labels(l10n);
    // App-wide unread message total, summed from the conversations list (see
    // `unreadMessagesCountProvider`). Watching it here means the badge tracks
    // every path that touches unread state — a live socket message, opening a
    // thread, mark read/unread, a reconnect or foreground re-sync — without
    // any of them knowing this widget exists.
    final unreadMessages = ref.watch(unreadMessagesCountProvider);
    const surfaceColor = AppColors.surfaceLight;

    // Android/iOS back button: only the Discover branch is a true "root" —
    // every other branch was reached by switching tabs, not by pushing on
    // top of Discover, so there's nothing underneath it in ITS OWN branch
    // stack to pop back to. Intercept the back gesture there and switch to
    // the Discover branch instead of letting the OS close the app; only
    // allow the real pop (app exit) from Discover itself. Routes pushed on
    // top of any branch (Search, Edit Profile, wizard steps, ...) are
    // unaffected — they live above this as root-navigator pages, so the OS
    // back button already pops them first as normal.
    // Built once and placed either in the bottom pill (phones/tablets) or in
    // the desktop rail, so both navigations share labels, badge and tap
    // behaviour.
    List<Widget> items(Color badgeBorderColor, {Axis axis = Axis.vertical}) =>
        List<Widget>.generate(_tabs.length, (index) {
          final tab = _tabs[index];
          return _NavItem(
            icon: tab.icon,
            activeIcon: tab.activeIcon,
            label: labels[index],
            axis: axis,
            isActive: index == currentIndex,
            badgeCount: index == _inboxTabIndex ? unreadMessages : 0,
            // Announced instead of the bare count, so the badge reads
            // as "Inbox, 3 unread messages" rather than "Inbox" and a
            // loose "3" (see [NavBadge]'s own ExcludeSemantics).
            badgeSemanticLabel: l10n.navUnreadMessagesSemanticLabel(
              unreadMessages,
            ),
            // The badge's ring should read as a cut-out in the bar,
            // so it takes the bar's own colour rather than a hardcoded
            // white that would look like a sticker in dark mode.
            badgeBorderColor: badgeBorderColor,
            // initialLocation resets the branch to its starting
            // route when re-tapping the tab you're already on —
            // the standard go_router pattern — while switching
            // between different tabs preserves each one's state.
            onTap: () => navigationShell.goBranch(
              index,
              initialLocation: index == currentIndex,
            ),
          );
        });

    // Shell-level decision, so the window is the right thing to measure.
    // Everything laid out *inside* the shell classifies from its own
    // LayoutBuilder constraints instead — see WindowClass.of's docs.
    final windowClass = WindowClass.of(context);
    final useRail = windowClass.isAtLeastExpanded;
    final useExtendedRail = windowClass.isLarge;

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
        body: useRail
            ? Row(
                children: [
                  NmNavigationRail(
                    extended: useExtendedRail,
                    children: items(
                      AppColors.surfaceLight,
                      axis: useExtendedRail ? Axis.horizontal : Axis.vertical,
                    ),
                  ),
                  Expanded(child: navigationShell),
                ],
              )
            : navigationShell,
        bottomNavigationBar: useRail
            ? null
            : SafeArea(
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
                      for (final item in items(surfaceColor))
                        Expanded(child: item),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Left-hand navigation for [WindowClass.expanded] and wider, in place of the
/// floating pill.
///
/// Two variants, same items and same behavior: an icon-only rail at expanded
/// widths, and an [extended] icon + label rail at large widths. Separated from
/// the page by surface colour rather than a border.
class NmNavigationRail extends StatelessWidget {
  final List<Widget> children;

  /// Whether to show the wider icon + label variant.
  final bool extended;

  const NmNavigationRail({
    super.key,
    required this.children,
    required this.extended,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // Retained so existing tests and tooling keep locating the rail; the
      // extended variant adds its own key below rather than changing this one.
      key: const ValueKey('desktop-nav-rail'),
      width: extended
          ? NavRailMetrics.extendedWidth
          : NavRailMetrics.compactWidth,
      color: AppColors.surfaceLight,
      child: SafeArea(
        right: false,
        child: KeyedSubtree(
          key: extended
              ? const ValueKey('desktop-nav-rail-extended')
              : const ValueKey('desktop-nav-rail-compact'),
          // Scrolls rather than overflows on a short window.
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: extended ? AppSpacing.md : AppSpacing.sm,
              vertical: AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: extended
                  ? CrossAxisAlignment.stretch
                  : CrossAxisAlignment.center,
              children: [
                for (final item in children)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: item,
                  ),
              ],
            ),
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

  /// Unread count overlaid on this item's icon — 0 on every tab that doesn't
  /// have one, which [NavBadge] renders as scaled-to-nothing rather than
  /// absent, so the pop-in animation has something to animate from.
  final int badgeCount;
  final String badgeSemanticLabel;
  final Color badgeBorderColor;

  /// Vertical in the bottom pill and the icon rail (icon over label);
  /// horizontal in the extended rail (icon beside label).
  final Axis axis;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.axis,
    this.badgeCount = 0,
    this.badgeSemanticLabel = '',
    this.badgeBorderColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    const inactiveColor = AppColors.textTertiaryLight;
    const activeLabelColor = AppColors.textPrimaryLight;
    final horizontal = axis == Axis.horizontal;

    // The badge floats over the icon's top-right corner. The Stack
    // takes its size from the (unpositioned) icon circle, so adding
    // the badge changes nothing about the bar's layout — the badge
    // overhangs the circle's corner without ever widening the item
    // or shifting the label below it.
    final iconStack = Stack(
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
          child: NavBadge(count: badgeCount, borderColor: badgeBorderColor),
        ),
      ],
    );

    final labelText = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 250),
      style: AppTypography.labelSmall.copyWith(
        color: isActive ? activeLabelColor : inactiveColor,
        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: horizontal ? TextAlign.start : null,
      ),
    );

    // Stacked axis: scale the label down to fit under the icon. Horizontal
    // axis: no FittedBox — inside a Flexible it would shrink the text instead
    // of letting the ellipsis handle a long or localized label.
    final labelWidget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs2),
      child: horizontal
          ? labelText
          : FittedBox(fit: BoxFit.scaleDown, child: labelText),
    );

    // Magenta active indicator bar — same visual language as the
    // tab-chip underline used elsewhere (discover top bar, matches
    // header), so the active tab reads clearly at a glance.
    final activeIndicator = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      width: isActive ? AppSpacing.md : 0,
      height: 3,
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(AppSpacing.xs2),
      ),
    );

    return Semantics(
      button: true,
      label: badgeCount > 0 ? '$label, $badgeSemanticLabel' : label,
      selected: isActive,
      child: InkWell(
        borderRadius: AppRadius.br16,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: horizontal ? AppSpacing.sm : 0,
          ),
          child: horizontal
              ? Row(
                  children: [
                    iconStack,
                    const SizedBox(width: AppSpacing.md),
                    // Flexible, so a long or localized label ellipsizes
                    // inside the 240px rail instead of overflowing it.
                    Flexible(child: labelWidget),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    iconStack,
                    const SizedBox(height: AppSpacing.xs2),
                    labelWidget,
                    const SizedBox(height: AppSpacing.xs2),
                    activeIndicator,
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
