import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../location/domain/models/location_models.dart';
import '../../../location/presentation/widgets/location_picker_field.dart';

/// A location level on an onboarding step, in the onboarding's own chrome.
///
/// Deliberately a thin wrapper over the shared [LocationPickerField] rather
/// than a second picker: onboarding and the Edit Profile wizard ask the same
/// question of the same master data, and the loading / failed / empty states
/// that field already handles are exactly the ones a signup screen must not
/// get wrong. All this adds is the bold heading and the required asterisk the
/// surrounding [OnboardingDropdownField]s use, so the location fields do not
/// look like visitors from another screen.
class OnboardingLocationField extends StatelessWidget {
  const OnboardingLocationField({
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
    this.isRequired = false,
  });

  final String label;
  final String hint;

  /// The options for this level — loading, failed or ready.
  final AsyncValue<List<LocationOption>> options;

  final LocationOption? value;
  final ValueChanged<LocationOption?> onChanged;

  /// An answer stored before the master data existed, or one whose label the
  /// current list does not offer. Shown as the member's own answer rather
  /// than as a hint, so reopening a step never looks like the app lost it.
  final String legacyValue;

  final bool enabled;
  final String? disabledHint;
  final VoidCallback? onRetry;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return LocationPickerField(
      label: isRequired ? '$label *' : label,
      labelStyle: AppTypography.titleMedium.copyWith(
        color: colors.onSurface,
        fontWeight: FontWeight.w700,
      ),
      hint: hint,
      options: options,
      value: value,
      legacyValue: legacyValue,
      enabled: enabled,
      disabledHint: disabledHint,
      onRetry: onRetry,
      onChanged: onChanged,
    );
  }
}

/// Spacing between stacked onboarding location fields, matching the gap the
/// scaffold puts between its own fields.
const double onboardingLocationFieldGap = AppSpacing.lg;

/// Resolves a stored (code, label) pair against the options the API returned.
///
/// Three cases, and the middle one is the reason this exists:
///
///  * **Code present and known** — return the live option, so the label shown
///    is the current one even if it has since been corrected upstream.
///  * **Code absent but the label matches an option** — adopt that option.
///    Every draft created before the master data existed has a label and no
///    code, and `LocationDetails.country` defaults to `'India'` for *every*
///    new draft, so without this a member would have to re-pick a country
///    their screen is already showing them, and could not reach the state
///    list at all. This is not fallback data: the match is made against the
///    API's own list, and a label the API does not offer resolves to nothing.
///  * **Neither** — null, and the caller shows [label] as legacy text.
///
/// Matching is case-insensitive and trimmed because the stored labels came
/// from a hand-maintained list, not from this API.
LocationOption? resolveStoredLocation(
  AsyncValue<List<LocationOption>> options,
  String code,
  String label,
) {
  final available = options.valueOrNull;

  // Still loading or failed: keep showing what the draft holds rather than
  // blanking the field while a request is in flight.
  if (available == null) {
    if (code.isEmpty) return null;
    return LocationOption(code: code, label: label);
  }

  if (code.isNotEmpty) {
    for (final option in available) {
      if (option.code == code) return option;
    }
    // A code the list no longer offers — a retired city, or a stale draft.
    // Kept as-is so the answer survives; the member can still re-pick.
    return LocationOption(code: code, label: label);
  }

  final wanted = label.trim().toLowerCase();
  if (wanted.isEmpty) return null;
  for (final option in available) {
    if (option.label.toLowerCase() == wanted) return option;
  }
  return null;
}
