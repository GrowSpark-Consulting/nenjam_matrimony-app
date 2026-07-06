import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router/route_names.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_shadows.dart';

/// Bottom navigation shell that wraps tabbed routes.
class AppBottomNavShell extends StatelessWidget {
  final Widget child;

  const AppBottomNavShell({super.key, required this.child});

  static const _tabs = [
    _NavTab(RouteNames.home, Icons.home_rounded, Icons.home_outlined, 'Home'),
    _NavTab(RouteNames.search, Icons.search_rounded, Icons.search_rounded, 'Search'),
    _NavTab(RouteNames.matches, Icons.favorite_rounded, Icons.favorite_border_rounded, 'Matches'),
    _NavTab(RouteNames.chat, Icons.chat_bubble_rounded, Icons.chat_bubble_outline_rounded, 'Chat'),
    _NavTab(RouteNames.profile, Icons.person_rounded, Icons.person_outline_rounded, 'Profile'),
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

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          boxShadow: AppShadows.bottomNav,
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_tabs.length, (index) {
                final tab = _tabs[index];
                final isActive = index == currentIndex;

                return Expanded(
                  child: Semantics(
                    label: tab.label,
                    selected: isActive,
                    child: InkWell(
                      onTap: () => context.go(tab.path),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              isActive ? tab.activeIcon : tab.icon,
                              key: ValueKey(isActive),
                              size: 24,
                              color: isActive
                                  ? Theme.of(context).colorScheme.primary
                                  : (isDark
                                      ? AppColors.textTertiaryDark
                                      : AppColors.textTertiaryLight),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tab.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isActive
                                  ? Theme.of(context).colorScheme.primary
                                  : (isDark
                                      ? AppColors.textTertiaryDark
                                      : AppColors.textTertiaryLight),
                            ),
                          ),
                        ],
                      ),
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

class _NavTab {
  final String path;
  final IconData activeIcon;
  final IconData icon;
  final String label;

  const _NavTab(this.path, this.activeIcon, this.icon, this.label);
}
