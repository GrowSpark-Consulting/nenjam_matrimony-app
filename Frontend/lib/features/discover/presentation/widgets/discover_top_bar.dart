import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/avatars/app_avatars.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/discover_providers.dart';

/// Floating top overlay for the Discover reel: search icon → tab pills →
/// avatar. Sits over a dark-to-transparent scrim so it reads on any photo.
///
/// Overflow-safe: tabs are in a [SingleChildScrollView] so they never
/// clip on 360 px devices.
class DiscoverTopBar extends ConsumerWidget {
  const DiscoverTopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(discoverFilterProvider);

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + AppSpacing.xs,
        left: AppSpacing.xs,
        right: AppSpacing.sm,
        bottom: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.scrim, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          // ── Search ──────────────────────────────────────────────
          Semantics(
            button: true,
            label: l10n.searchTitle,
            child: IconButton(
              onPressed: () {},
              icon: const Icon(Icons.search_rounded, color: Colors.white),
              tooltip: l10n.searchTitle,
            ),
          ),

          // ── Tab pills (scrollable so they never overflow) ────────
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DiscoverTabChip(
                    label: l10n.discoverForYouTab,
                    isSelected: filter == DiscoverFilter.forYou,
                    onTap: () =>
                        ref.read(discoverFilterProvider.notifier).state =
                            DiscoverFilter.forYou,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _DiscoverTabChip(
                    label: l10n.discoverNearMeTab,
                    isSelected: filter == DiscoverFilter.nearMe,
                    onTap: () =>
                        ref.read(discoverFilterProvider.notifier).state =
                            DiscoverFilter.nearMe,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _DiscoverTabChip(
                    label: l10n.discoverNewTab,
                    isSelected: filter == DiscoverFilter.newProfiles,
                    onTap: () =>
                        ref.read(discoverFilterProvider.notifier).state =
                            DiscoverFilter.newProfiles,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: AppSpacing.sm),

          // ── Avatar / filter ──────────────────────────────────────
          Semantics(
            button: true,
            label: l10n.homeFilterLabel,
            child: const NmCircleAvatar(size: 36),
          ),
        ],
      ),
    );
  }
}

/// Small on-photo tab pill with selected (gold gradient) / unselected
/// (frosted-glass) states.
class _DiscoverTabChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DiscoverTabChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          gradient: isSelected ? AppGradients.gold : AppGradients.cardGlass,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: isSelected
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: isSelected ? AppColors.textOnGold : Colors.white,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
