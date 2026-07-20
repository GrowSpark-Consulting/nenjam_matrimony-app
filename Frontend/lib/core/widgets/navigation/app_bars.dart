import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_typography.dart';

/// Luxury Top App Bar with notification and action slots.
class NmTopAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;

  const NmTopAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.centerTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title, style: AppTypography.titleLarge),
      centerTitle: centerTitle,
      leading: leading,
      actions: actions,
      elevation: 0,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

/// Search App Bar with embedded text input.
class NmSearchAppBar extends StatelessWidget implements PreferredSizeWidget {
  final TextEditingController? controller;
  final String hint;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final VoidCallback? onFilterTap;
  /// Count shown as a small pill on the filter icon when > 0 (e.g. active
  /// filter count). No pill is drawn at 0 — existing callers that don't
  /// pass this see no visual change.
  final int filterBadgeCount;

  const NmSearchAppBar({
    super.key,
    this.controller,
    this.hint = 'Search by ID, name, community...',
    this.onChanged,
    this.onSubmitted,
    this.onFilterTap,
    this.filterBadgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const BackButton(),
            Expanded(
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: AppColors.textSecondaryLight),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        onChanged: onChanged,
                        onSubmitted: onSubmitted,
                        decoration: InputDecoration(hintText: hint, border: InputBorder.none),
                        style: AppTypography.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (onFilterTap != null) ...[
              const SizedBox(width: 8),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(icon: const Icon(Icons.tune_rounded), onPressed: onFilterTap),
                  if (filterBadgeCount > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 16),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.all(Radius.circular(999)),
                        ),
                        child: Text(
                          '$filterBadgeCount',
                          textAlign: TextAlign.center,
                          style: AppTypography.labelSmall.copyWith(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(64);
}

/// Luxury Sliver App Bar for profile scrolling.
class NmSliverAppBar extends StatelessWidget {
  final String title;
  final String? backgroundImageUrl;
  final List<Widget>? actions;

  const NmSliverAppBar({
    super.key,
    required this.title,
    this.backgroundImageUrl,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      stretch: true,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      actions: actions,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(title, style: AppTypography.titleMedium.copyWith(color: Colors.white)),
        background: backgroundImageUrl != null
            ? Image.network(backgroundImageUrl!, fit: BoxFit.cover)
            : Container(color: AppColors.primary),
      ),
    );
  }
}

/// Floating Navigation Pill bar.
class NmFloatingNavigation extends StatelessWidget {
  final List<IconData> icons;
  final int selectedIndex;
  final void Function(int) onItemSelected;

  const NmFloatingNavigation({
    super.key,
    required this.icons,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(999),
        boxShadow: AppShadows.floatingLight,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: icons.asMap().entries.map((entry) {
          final isSelected = selectedIndex == entry.key;
          return IconButton(
            icon: Icon(entry.value, color: isSelected ? AppColors.accentGold : Colors.white70),
            onPressed: () => onItemSelected(entry.key),
          );
        }).toList(),
      ),
    );
  }
}
