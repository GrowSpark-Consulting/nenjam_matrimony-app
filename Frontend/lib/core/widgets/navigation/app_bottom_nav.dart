import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../constants/app_spacing.dart';
import '../../router/route_names.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_typography.dart';
import '../../theme/tokens/app_radius.dart';

/// Floating pill-style bottom navigation shell that wraps tabbed routes —
/// Discover / Matches / Inbox / Premium.
class AppBottomNavShell extends StatelessWidget {
  final Widget child;

  const AppBottomNavShell({super.key, required this.child});

  static const _tabs = [
    _NavTab(RouteNames.discover, Icons.explore_rounded, Icons.explore_outlined),
    _NavTab(RouteNames.matches, Icons.favorite_rounded, Icons.favorite_border_rounded),
    _NavTab(RouteNames.messages, Icons.chat_bubble_rounded, Icons.chat_bubble_outline_rounded),
    _NavTab(RouteNames.premium, Icons.workspace_premium_rounded, Icons.workspace_premium_outlined),
  ];

  /// Localized labels, index-aligned with [_tabs].
  List<String> _labels(AppLocalizations l10n) => [
        l10n.navDiscover,
        l10n.navMatches,
        l10n.navMessages,
        l10n.navPremium,
      ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    for (int i = 0; i < _tabs.length; i++) {
      if (location == _tabs[i].path) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentIndex = _currentIndex(context);
    final labels = _labels(AppLocalizations.of(context));

    // Android/iOS back button: only the Discover tab is a true "root" —
    // every other tab was reached via context.go() (a stack replace, not a
    // push), so there's nothing underneath it to pop back to. Intercept
    // the back gesture there and return to Discover instead of letting the
    // OS close the app; only allow the real pop (app exit) from Discover
    // itself. Routes pushed on top of any tab (Edit Profile, wizard steps,
    // ...) are unaffected — they live above this in the Navigator stack,
    // so the OS back button already pops them first as normal.
    return PopScope(
      canPop: currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go(RouteNames.discover);
      },
      child: Scaffold(
        body: child,
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
                    onTap: () => context.go(tab.path),
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
  final String path;
  final IconData activeIcon;
  final IconData icon;

  const _NavTab(this.path, this.activeIcon, this.icon);
}
