import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
import '../utils/partner_preference_labels.dart';
import 'registration_helper_tip.dart';

/// Step 10 — Partner Preferences
class StepPartnerPref extends StatefulWidget {
  final PartnerPreference details;
  final void Function(PartnerPreference) onChanged;

  const StepPartnerPref({super.key, required this.details, required this.onChanged});

  @override
  State<StepPartnerPref> createState() => _StepPartnerPrefState();
}

class _StepPartnerPrefState extends State<StepPartnerPref> {
  late String _ageRange;
  late String _heightRange;
  late String _religionPref;
  late String _castePref;
  late String _educationPref;
  late String _occupationPref;
  late String _incomePref;
  late String _locationPref;
  late String _motherTonguePref;
  late String _maritalStatusPref;

  static const _ageRanges = partnerPrefAgeRanges;
  static const _heightRanges = partnerPrefHeightRanges;
  static const _religions = partnerPrefReligions;
  static const _castes = partnerPrefCastes;
  static const _educations = partnerPrefEducations;
  static const _occupations = partnerPrefOccupations;
  static const _incomes = partnerPrefIncomes;
  static const _locations = partnerPrefLocations;
  static const _tongues = partnerPrefMotherTongues;
  static const _maritalStatuses = partnerPrefMaritalStatuses;

  @override
  void initState() {
    super.initState();
    _ageRange = widget.details.preferredAgeRange;
    _heightRange = widget.details.preferredHeightRange;
    _religionPref = widget.details.religionPref;
    _castePref = widget.details.castePref;
    _educationPref = widget.details.educationPref;
    _occupationPref = widget.details.occupationPref;
    _incomePref = widget.details.incomePref;
    _locationPref = widget.details.locationPref;
    _motherTonguePref = widget.details.motherTonguePref;
    _maritalStatusPref = widget.details.maritalStatusPref;
  }

  void _emit() {
    // `extended` (advanced preferences edited from the standalone Partner
    // Preferences page) is passed through unchanged — this step only ever
    // edits the 10 base fields, and must not reset it back to its default.
    widget.onChanged(PartnerPreference(preferredAgeRange: _ageRange, preferredHeightRange: _heightRange, religionPref: _religionPref, castePref: _castePref, educationPref: _educationPref, occupationPref: _occupationPref, incomePref: _incomePref, locationPref: _locationPref, motherTonguePref: _motherTonguePref, maritalStatusPref: _maritalStatusPref, extended: widget.details.extended));
  }

  /// Chip section with an optional value->label mapper (values stay English).
  Widget _section(String title, List<String> opts, String selected,
      void Function(String) onSelect,
      {String Function(String)? labelOf}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: opts.map((o) { final sel = selected == o; return ChoiceChip(label: Text(labelOf?.call(o) ?? o), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { onSelect(o); _emit(); }); }).toList()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.registrationWizardPartnerHeadline, style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.registrationWizardPartnerHook, style: AppTypography.bodyMedium.copyWith(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipPartnerPref),
          const SizedBox(height: 24),
          // Numeric age/height/income ranges kept as-is (only 'Any' localized).
          _section(l10n.registrationPrefAgeLabel, _ageRanges, _ageRange, (v) => setState(() => _ageRange = v), labelOf: (v) => anyOrSelfLabel(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefHeightLabel, _heightRanges, _heightRange, (v) => setState(() => _heightRange = v), labelOf: (v) => anyOrSelfLabel(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefReligionLabel, _religions, _religionPref, (v) => setState(() => _religionPref = v), labelOf: (v) => religionPrefLabel(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefCasteLabel, _castes, _castePref, (v) => setState(() => _castePref = v), labelOf: (v) => castePrefLabel(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefEducationLabel, _educations, _educationPref, (v) => setState(() => _educationPref = v), labelOf: (v) => educationPrefLabel(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefOccupationLabel, _occupations, _occupationPref, (v) => setState(() => _occupationPref = v), labelOf: (v) => occupationPrefLabel(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefIncomeLabel, _incomes, _incomePref, (v) => setState(() => _incomePref = v), labelOf: (v) => anyOrSelfLabel(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefLocationLabel, _locations, _locationPref, (v) => setState(() => _locationPref = v), labelOf: (v) => locationPrefLabel(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefMotherTongueLabel, _tongues, _motherTonguePref, (v) => setState(() => _motherTonguePref = v), labelOf: (v) => motherTonguePrefLabel(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefMaritalLabel, _maritalStatuses, _maritalStatusPref, (v) => setState(() => _maritalStatusPref = v), labelOf: (v) => maritalStatusPrefLabel(l10n, v)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
