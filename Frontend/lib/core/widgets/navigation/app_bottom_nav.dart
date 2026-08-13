import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/inbox/presentation/providers/inbox_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../constants/app_spacing.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_typography.dart';
import '../../theme/tokens/app_radius.dart';
import 'nav_badge.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentIndex = navigationShell.currentIndex;
    final l10n = AppLocalizations.of(context);
    final labels = _labels(l10n);
    // App-wide unread message total, summed from the conversations list (see
    // `unreadMessagesCountProvider`). Watching it here means the badge tracks
    // every path that touches unread state — a live socket message, opening a
    // thread, mark read/unread, a reconnect or foreground re-sync — without
    // any of them knowing this widget exists.
    final unreadMessages = ref.watch(unreadMessagesCountProvider);
    final surfaceColor = isDark
        ? AppColors.surfaceDark
        : AppColors.surfaceLight;

    // Android/iOS back button: only the Discover branch is a true "root" —
    // every other branch was reached by switching tabs, not by pushing on
    // top of Discover, so there's nothing underneath it in ITS OWN branch
    // stack to pop back to. Intercept the back gesture there and switch to
    // the Discover branch instead of letting the OS close the app; only
    // allow the real pop (app exit) from Discover itself. Routes pushed on
    // top of any branch (Search, Edit Profile, wizard steps, ...) are
    // unaffected — they live above this as root-navigator pages, so the OS
    // back button already pops them first as normal.
    // TEMP DEBUG — remove before shipping.
    debugPrint(
      '[BACK] AppBottomNavShell.build: currentIndex=$currentIndex '
      'canPop(computed)=${currentIndex == 0}',
    );
    return PopScope(
      canPop: currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        // TEMP DEBUG — remove before shipping.
        debugPrint(
          '[BACK] PopScope.onPopInvokedWithResult FIRED: '
          'didPop=$didPop currentIndex=$currentIndex',
        );
        if (didPop) return;
        debugPrint('[BACK] -> navigationShell.goBranch(0)');
        navigationShell.goBranch(0);
      },
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(
            AppSpacing.base,
            0,
            AppSpacing.base,
            AppSpacing.sm,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: AppRadius.pill,
              boxShadow: AppShadows.floatingLight,
            ),
            // No fixed height — the bar sizes itself to each _NavItem's
            // intrinsic content (icon badge + label), so it can never clip
            // at large text-scale settings the way a hardcoded height did.
            child: Row(
              children: List.generate(_tabs.length, (index) {
                final tab = _tabs[index];
                return Expanded(
                  child: _NavItem(
                    icon: tab.icon,
                    activeIcon: tab.activeIcon,
                    label: labels[index],
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
                    badgeBorderColor: surfaceColor,
                    // initialLocation resets the branch to its starting
                    // route when re-tapping the tab you're already on —
                    // the standard go_router pattern — while switching
                    // between different tabs preserves each one's state.
                    onTap: () => navigationShell.goBranch(
                      index,
                      initialLocation: index == currentIndex,
                    ),
                  ),
                );
              }),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = isDark
        ? AppColors.textTertiaryDark
        : AppColors.textTertiaryLight;
    final activeLabelColor = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimaryLight;

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
              // the badge changes nothing about the bar's layout — the badge
              // overhangs the circle's corner without ever widening the item
              // or shifting the label below it.
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
                      color: isActive
                          ? AppColors.accentGold
                          : Colors.transparent,
                      boxShadow: isActive ? AppShadows.goldGlow : null,
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
              // Gold active indicator bar — same visual language as the
              // tab-chip underline used elsewhere (discover top bar, matches
              // header), so the active tab reads clearly at a glance.
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                width: isActive ? AppSpacing.md : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.accentGold,
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
