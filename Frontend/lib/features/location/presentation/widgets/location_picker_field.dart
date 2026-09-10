import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sheets/app_sheets.dart';
import '../../domain/models/location_models.dart';

/// One level of the country → state → city cascade.
///
/// Reuses [AppSheets.showSearchableSelection] rather than a bespoke sheet, so
/// picking a city looks and behaves like every other long-list field in the
/// app. Labels are unique within a parent — a city's code is derived from its
/// own label, so two cities in one state cannot share one — which is what
/// makes it safe to round-trip through the sheet's string API and map the
/// chosen label back to its [LocationOption].
///
/// The three states it can be in are all real and all handled: still loading,
/// failed to load (with a retry the member can actually use), and ready. A
/// silently empty dropdown is the one outcome this must never produce, since
/// it looks identical to "there is nothing here" while actually meaning "the
/// request failed".
class LocationPickerField extends ConsumerWidget {
  const LocationPickerField({
    super.key,
    required this.label,
    required this.hint,
    required this.options,
    required this.value,
    required this.onChanged,
    this.legacyValue = '',
    this.enabled = true,
    this.disabledHint,
    this.onRetry,
  });

  final String label;
  final String hint;

  /// Free text from before the master data existed, shown when there is no
  /// code-backed [value]. Displayed like a real value, not like a hint,
  /// because to the member it IS their answer.
  final String legacyValue;

  /// The options for this level, which may still be loading or failed.
  final AsyncValue<List<LocationOption>> options;

  final LocationOption? value;
  final ValueChanged<LocationOption?> onChanged;

  /// False while the parent level has no selection — there is nothing to
  /// list yet, and tapping should say so rather than open an empty sheet.
  final bool enabled;
  final String? disabledHint;

  /// Invoked when the member taps "Try again" after a load failure.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = options.hasError && !options.isLoading;
    final loading = options.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.labelMedium),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: !enabled || loading || failed ? null : () => _open(context),
          child: InputDecorator(
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        failed
                            ? Icons.error_outline_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: failed
                            ? AppColors.error
                            : AppColors.textSecondaryLight,
                        size: 22,
                      ),
              ),
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            child: Text(
              _displayText,
              style: AppTypography.bodyMedium.copyWith(
                color: _hasValue ? null : AppColors.textSecondaryLight,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (failed && onRetry != null) ...[
          const SizedBox(height: 6),
          // A failure the member can act on. Without this the field is simply
          // stuck, and the only way forward is to restart the app.
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ],
    );
  }

  /// Whether the field is showing the member's own answer rather than a hint.
  bool get _hasValue => value != null || legacyValue.isNotEmpty;

  String get _displayText {
    if (value != null) return value!.label;
    if (legacyValue.isNotEmpty) return legacyValue;
    if (!enabled) return disabledHint ?? hint;
    if (options.hasError && !options.isLoading) return 'Could not load';
    return hint;
  }

  Future<void> _open(BuildContext context) async {
    final available = options.valueOrNull ?? const <LocationOption>[];
    if (available.isEmpty) return;

    final selected = await AppSheets.showSearchableSelection(
      context,
      title: label,
      options: available.map((o) => o.label).toList(growable: false),
      selectedValue: value?.label,
    );
    if (selected == null) return;

    // firstWhere with a fallback rather than a bang: the sheet can only
    // return a label it was given, but a null here would be a crash in the
    // member's face, and doing nothing is the honest failure.
    for (final option in available) {
      if (option.label == selected) {
        onChanged(option);
        return;
      }
    }
  }
}
