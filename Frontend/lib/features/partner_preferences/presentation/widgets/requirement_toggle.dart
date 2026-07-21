import 'package:flutter/material.dart';

import '../../../../core/widgets/inputs/segmented_control.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/partner_preference_extended.dart';

/// The only two importance levels the UI offers — Required (hard filter)
/// or Optional (soft preference). The legacy `doesntMatter` value is
/// deliberately excluded here; [PartnerPreferenceExtended.requirementFor]
/// already folds it into [PreferenceRequirement.optional] before it ever
/// reaches this widget, so `value` is always one of these two.
const List<PreferenceRequirement> _kRequirementOptions = [
  PreferenceRequirement.required,
  PreferenceRequirement.optional,
];

/// Small "How important is this?" segmented toggle for
/// [PreferenceRequirement] — placed inside a field's own bottom sheet (not
/// the collapsed row list), so the matching-engine importance tag stays
/// available without turning every row into a wall of controls.
class RequirementToggle extends StatelessWidget {
  final PreferenceRequirement value;
  final ValueChanged<PreferenceRequirement> onChanged;

  const RequirementToggle({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // `_` also covers the legacy `doesntMatter` value defensively, in case
    // this widget is ever handed an un-normalized value directly — it
    // displays as Optional rather than a label with no matching segment.
    String labelOf(PreferenceRequirement r) => switch (r) {
          PreferenceRequirement.required => l10n.partnerPrefRequirementRequired,
          _ => l10n.partnerPrefRequirementOptional,
        };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: NmSegmentedControl<PreferenceRequirement>(
        options: _kRequirementOptions,
        labelBuilder: labelOf,
        value: value.normalized,
        // A binary Required/Optional toggle should never end up
        // unselected — clearing back to null (NmSegmentedControl's
        // tap-again-to-clear convention) still resolves to Optional rather
        // than leaving no segment highlighted.
        onChanged: (v) => onChanged(v ?? PreferenceRequirement.optional),
      ),
    );
  }
}
