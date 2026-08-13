import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';

/// One axis of a multi-axis compatibility breakdown (e.g. "Psychology: 88").
class CompatibilityAxis {
  final String label;
  final int score;

  const CompatibilityAxis({required this.label, required this.score});
}

/// Expandable multi-axis compatibility breakdown for the Nenjam hub's
/// Compatibility Report section. Reuses the same circular-score visual
/// language as [NmCompatibilityCard] rather than a second bespoke score
/// widget, just applied across several axes instead of one.
class NmCompatibilityReportCard extends StatefulWidget {
  final int overallScore;
  final String overallLabel;
  final List<CompatibilityAxis> axes;
  final String showMoreLabel;
  final String showLessLabel;
  final int collapsedCount;

  const NmCompatibilityReportCard({
    super.key,
    required this.overallScore,
    required this.overallLabel,
    required this.axes,
    required this.showMoreLabel,
    required this.showLessLabel,
    this.collapsedCount = 4,
  });

  @override
  State<NmCompatibilityReportCard> createState() =>
      _NmCompatibilityReportCardState();
}

class _NmCompatibilityReportCardState extends State<NmCompatibilityReportCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canExpand = widget.axes.length > widget.collapsedCount;
    final visibleAxes = _expanded
        ? widget.axes
        : widget.axes.take(widget.collapsedCount).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.card(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                height: 64,
                width: 64,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: widget.overallScore / 100,
                      strokeWidth: 6,
                      backgroundColor: AppColors.divider,
                      color: AppColors.accentGold,
                    ),
                    Center(
                      child: Text(
                        '${widget.overallScore}%',
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.overallLabel,
                  style: AppTypography.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          for (final axis in visibleAxes)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _AxisRow(axis: axis),
            ),
          if (canExpand)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded ? widget.showLessLabel : widget.showMoreLabel,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AxisRow extends StatelessWidget {
  final CompatibilityAxis axis;

  const _AxisRow({required this.axis});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(axis.label, style: AppTypography.bodyMedium)),
            Text(
              '${axis.score}%',
              style: AppTypography.labelMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: axis.score / 100,
            minHeight: 6,
            backgroundColor: isDark
                ? AppColors.surfaceVariantDark
                : AppColors.divider,
            color: AppColors.accentGold,
          ),
        ),
      ],
    );
  }
}
