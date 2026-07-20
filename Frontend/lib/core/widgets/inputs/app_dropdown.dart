import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Reusable dropdown input component.
class NmDropdown<T> extends StatelessWidget {
  final String? label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?)? onChanged;
  final String? hint;

  const NmDropdown({
    super.key,
    this.label,
    required this.items,
    this.value,
    this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!, style: AppTypography.labelMedium),
          const SizedBox(width: 4, height: 6),
        ],
        DropdownButtonFormField<T>(
          initialValue: value,
          items: items,
          // Without this, the button sizes itself to its widest item/value
          // instead of the space it's actually given — the horizontal
          // overflow when a dropdown sits in a Row (e.g. next to another
          // field) or an option's text is long.
          isExpanded: true,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondaryLight),
          style: AppTypography.bodyMedium,
          // Truncates the closed-state selected value with an ellipsis
          // instead of wrapping/overflowing — wraps whatever widget each
          // caller's DropdownMenuItem uses (typically a plain Text) without
          // requiring every call site to opt in itself.
          selectedItemBuilder: (context) => items
              .map(
                (item) => Align(
                  alignment: Alignment.centerLeft,
                  child: DefaultTextStyle.merge(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: item.child,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
