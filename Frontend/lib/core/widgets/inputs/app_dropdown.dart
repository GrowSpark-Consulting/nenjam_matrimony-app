import 'package:flutter/material.dart';

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
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AppTypography.labelMedium
                .copyWith(color: colors.onSurfaceVariant),
          ),
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
          // Reads from the scheme rather than the light token so the chevron
          // stays legible in a dark scheme. Identical in light: the light
          // scheme maps onSurfaceVariant to AppColors.textSecondaryLight.
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          // Both colours are explicit on purpose. AppTypography's styles come
          // from GoogleFonts and carry NO colour, and this `style` is what
          // the *open menu* paints its items with — leaving it unset resolved
          // to white-on-white, making every option invisible once the menu
          // was open. Never hand a colourless TextStyle to a dropdown.
          dropdownColor: colors.surface,
          style: AppTypography.bodyMedium.copyWith(color: colors.onSurface),
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
