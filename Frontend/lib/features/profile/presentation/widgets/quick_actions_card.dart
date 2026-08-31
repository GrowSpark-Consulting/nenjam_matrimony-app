import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

/// A single quick-action tile.
class NmQuickAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? iconColor;

  const NmQuickAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.iconColor,
  });
}

/// Quick Actions grid — a 2×2 (or 2×N) grid of action tiles for Settings,
/// Privacy, Help Center, and Subscription navigation.
class NmQuickActionsCard extends StatelessWidget {
  final List<NmQuickAction> actions;

  const NmQuickActionsCard({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.of(context).profileQuickActions, style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.md),
        // A Wrap of quarter-width tiles sizes to its content height, so
        // tiles never clip when the label wraps under large font scaling
        // — unlike a fixed-aspect-ratio GridView.
        LayoutBuilder(
          builder: (context, constraints) {
            const columns = 4;
            final tileWidth =
                (constraints.maxWidth - AppSpacing.sm * (columns - 1)) /
                columns;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: actions
                  .map(
                    (action) => SizedBox(
                      width: tileWidth,
                      child: _ActionTile(action: action),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final NmQuickAction action;

  const _ActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    final iconColor =
        action.iconColor ??
        AppColors.primary;

    return Semantics(
      label: action.label,
      button: true,
      child: Material(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.icon, size: 24, color: iconColor),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  action.label,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textSecondaryLight,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
