import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Horizontally-scrollable underline tab row pinned under the collapsed
/// hero. Tapping a tab scrolls the page to the matching section — the
/// page owns the actual [Scrollable.ensureVisible] call via [onTap].
class ProfileDetailSectionTabBar extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const ProfileDetailSectionTabBar({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onTap,
  });

  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.lg),
        itemBuilder: (context, index) {
          final selected = index == selectedIndex;
          return _UnderlineTab(
            label: labels[index],
            selected: selected,
            isDark: isDark,
            onTap: () => onTap(index),
          );
        },
      ),
    );
  }
}

class _UnderlineTab extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _UnderlineTab({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryText = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryText =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: AppTypography.labelLarge.copyWith(
                color: selected ? primaryText : secondaryText,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 2.5,
              width: selected ? 20 : 0,
              decoration: BoxDecoration(
                color: AppColors.accentGold,
                borderRadius: AppSpacing.borderRadiusFull,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [SliverPersistentHeader] delegate that pins [ProfileDetailSectionTabBar]
/// under the collapsed hero.
class ProfileDetailTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const ProfileDetailTabBarDelegate({required this.child});

  @override
  double get minExtent => ProfileDetailSectionTabBar.height;

  @override
  double get maxExtent => ProfileDetailSectionTabBar.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant ProfileDetailTabBarDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}
