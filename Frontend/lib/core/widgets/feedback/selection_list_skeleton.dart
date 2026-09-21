import 'package:flutter/material.dart';

import '../../constants/app_spacing.dart';
import '../../theme/app_colors.dart';
import 'shimmer_widget.dart';

/// A row-shaped placeholder for a selection list that is still loading —
/// a dropdown, a bottom sheet, a searchable picker — built from the shared
/// [NmShimmer] primitive so a loading State/City/Religion/Community field
/// reads as "the same app, still working" rather than a generic spinner
/// screen dropped in from elsewhere.
///
/// Deliberately dumb: it only draws placeholder rows. The loading caption
/// ("Loading states...", "Finding cities in Gujarat...") is the caller's
/// text above this widget, not part of it, so the same skeleton serves every
/// field without knowing what it is a skeleton for.
class SelectionListSkeleton extends StatelessWidget {
  const SelectionListSkeleton({
    super.key,
    this.rowCount = 4,
    this.rowHeight = 48,
    this.horizontalPadding = AppSpacing.lg,
    this.rowSpacing = AppSpacing.sm,
    this.showLeading = false,
  });

  /// How many placeholder rows to draw. 3–5 reads as "a list is coming"
  /// without the sheet looking over-built for a field that may resolve in
  /// under a second.
  final int rowCount;

  /// Matches a real [ListTile]'s height (44–52px) so the sheet does not jump
  /// once the skeleton is replaced by the actual list.
  final double rowHeight;
  final double horizontalPadding;
  final double rowSpacing;

  /// Draws a circular placeholder ahead of each row's text bar, for a list
  /// whose real rows carry a leading icon or avatar.
  final bool showLeading;

  @override
  Widget build(BuildContext context) {
    // Motion is not the only signal something is loading — the caller's
    // caption text already says so — but a member with reduced-motion
    // preferences should not get an animated shimmer regardless.
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      label: 'Loading options',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(rowCount, (index) {
            // Varied widths so the rows read as text of differing length
            // rather than a uniform, obviously-fake bar grid.
            final widthFactor = index.isOdd ? 0.62 : 0.82;
            return Padding(
              padding: EdgeInsets.only(
                left: horizontalPadding,
                right: horizontalPadding,
                bottom: index == rowCount - 1 ? 0 : rowSpacing,
              ),
              child: SizedBox(
                height: rowHeight,
                child: Row(
                  children: [
                    if (showLeading) ...[
                      SizedBox(
                        width: rowHeight - 16,
                        height: rowHeight - 16,
                        child: reduceMotion
                            ? _staticBlock(borderRadius: (rowHeight - 16) / 2)
                            : NmShimmer.circle(size: rowHeight - 16),
                      ),
                      const SizedBox(width: AppSpacing.md),
                    ],
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: widthFactor,
                          child: reduceMotion
                              ? _staticBlock(height: 16)
                              : const NmShimmer(
                                  height: 16,
                                  borderRadius: AppSpacing.radiusSm,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _staticBlock({double? height, double borderRadius = AppSpacing.radiusSm}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.shimmerBaseLight,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}
