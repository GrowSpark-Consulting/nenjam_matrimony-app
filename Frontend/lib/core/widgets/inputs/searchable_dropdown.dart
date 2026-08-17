import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../sheets/app_sheets.dart';

/// A [NmDropdown]-styled field that opens [AppSheets.showSearchableSelection]
/// on tap, instead of a native dropdown menu — for fields with option lists
/// long enough that scrolling to find one is tedious (city, community,
/// rashi, star).
///
/// String-only (unlike [NmDropdown]'s generic `T`): the underlying sheet
/// filters by substring match against the option's display text, so a
/// non-string value has no well-defined way to match against what the user
/// types.
class NmSearchableDropdown extends StatelessWidget {
  final String? label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final String? hint;

  const NmSearchableDropdown({
    super.key,
    this.label,
    required this.options,
    this.value,
    required this.onChanged,
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
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final selected = await AppSheets.showSearchableSelection(
              context,
              title: label ?? hint ?? '',
              options: options,
              selectedValue: value,
            );
            if (selected != null) onChanged(selected);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              hintText: hint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              // Default suffixIcon reserves a ~48dp box regardless of the
              // icon's own size, which is what was crowding out the
              // selected-value text (especially in a half-width field like
              // Height Min/Max) — shrinking the reserved box, not the
              // padding, is what actually gives the text more room.
              suffixIcon: const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textSecondaryLight,
                  size: 22,
                ),
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
            ),
            child: Text(
              value ?? hint ?? '',
              style: AppTypography.bodyMedium.copyWith(
                color: value == null ? AppColors.textSecondaryLight : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}
