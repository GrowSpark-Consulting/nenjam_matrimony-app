import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Reusable dual-handle range slider with a label + current-range readout
/// above the track. Styling extracted from the Search filter sheet's
/// original age-range field so the visual spec lives in one place.
class NmRangeSlider extends StatelessWidget {
  final String label;
  final RangeValues range;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<RangeValues> onChanged;
  final String Function(double)? valueFormatter;

  const NmRangeSlider({
    super.key,
    required this.label,
    required this.range,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.valueFormatter,
  });

  @override
  Widget build(BuildContext context) {
    final format = valueFormatter ?? (v) => v.round().toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTypography.labelMedium),
            Text(
              '${format(range.start)} – ${format(range.end)}',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.primarySurface,
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withValues(alpha: 0.12),
            rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: RangeSlider(
            values: range,
            min: min,
            max: max,
            divisions: divisions,
            labels: RangeLabels(format(range.start), format(range.end)),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
