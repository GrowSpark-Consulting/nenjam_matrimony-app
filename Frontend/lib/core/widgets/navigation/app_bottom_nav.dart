import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../constants/app_spacing.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_typography.dart';
import '../../theme/tokens/app_radius.dart';

/// Floating pill-style bottom navigation shell that wraps tabbed routes —
/// Discover / Matches / Inbox / Premium.
///
/// Backed by a [StatefulShellRoute.indexedStack] (see `app_router.dart`):
/// [navigationShell] itself renders whichever branch is active inside an
/// `IndexedStack`, so switching tabs preserves each branch's own Navigator
/// stack and scroll position instead of rebuilding it from scratch.
class AppBottomNavShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppBottomNavShell({super.key, required this.navigationShell});

  static const _tabs = [
    _NavTab(Icons.explore_rounded, Icons.explore_outlined),
    _NavTab(Icons.favorite_rounded, Icons.favorite_border_rounded),
    _NavTab(Icons.chat_bubble_rounded, Icons.chat_bubble_outline_rounded),
    _NavTab(Icons.workspace_premium_rounded, Icons.workspace_premium_outlined),
  ];

  /// Localized labels, index-aligned with [_tabs] and with the branch order
  /// declared in `app_router.dart`.
  List<String> _labels(AppLocalizations l10n) => [
        l10n.navDiscover,
        l10n.navMatches,
        l10n.navMessages,
        l10n.navPremium,
      ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentIndex = navigationShell.currentIndex;
    final labels = _labels(AppLocalizations.of(context));

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
            AppSpacing.base, 0, AppSpacing.base, AppSpacing.sm,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
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

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor = isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight;
    final activeLabelColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

    return Semantics(
      button: true,
      label: label,
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
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                width: AppSpacing.xl3,
                height: AppSpacing.xl3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? AppColors.accentGold : Colors.transparent,
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
