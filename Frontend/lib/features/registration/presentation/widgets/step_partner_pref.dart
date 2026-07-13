import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
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

  static const _ageRanges = ['18-22', '22-26', '26-30', '30-35', '35-40', '40-50', 'Any'];
  static const _heightRanges = ['4\'6"-5\'0"', '5\'0"-5\'4"', '5\'4"-5\'8"', '5\'8"-6\'0"', '6\'0"+', 'Any'];
  static const _religions = ['Hindu', 'Christian', 'Muslim', 'Jain', 'Sikh', 'Any'];
  static const _castes = ['Same Caste', 'Any Caste', 'Inter-Caste OK'];
  static const _educations = ['B.E / B.Tech+', 'MBBS / MD+', 'MBA+', 'Any Degree', 'Any'];
  static const _occupations = ['Software / IT', 'Doctor', 'Government', 'Business', 'Any'];
  static const _incomes = ['5-10 Lakhs', '10-20 Lakhs', '20-50 Lakhs', '50 Lakhs+', 'Any'];
  static const _locations = ['Same City', 'Same State', 'Anywhere in India', 'NRI OK', 'Any'];
  static const _tongues = ['Same Mother Tongue', 'Tamil', 'Telugu', 'Hindi', 'Any'];
  static const _maritalStatuses = ['Never Married', 'Doesn\'t Matter', 'Any'];

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
    widget.onChanged(PartnerPreference(preferredAgeRange: _ageRange, preferredHeightRange: _heightRange, religionPref: _religionPref, castePref: _castePref, educationPref: _educationPref, occupationPref: _occupationPref, incomePref: _incomePref, locationPref: _locationPref, motherTonguePref: _motherTonguePref, maritalStatusPref: _maritalStatusPref));
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

  String _religionLabel(AppLocalizations l10n, String v) => switch (v) {
        'Hindu' => l10n.religionHindu,
        'Christian' => l10n.religionChristian,
        'Muslim' => l10n.religionMuslim,
        'Jain' => l10n.religionJain,
        'Sikh' => l10n.religionSikh,
        'Any' => l10n.commonAny,
        _ => v,
      };

  String _casteLabel(AppLocalizations l10n, String v) => switch (v) {
        'Same Caste' => l10n.prefCasteSame,
        'Any Caste' => l10n.prefCasteAny,
        'Inter-Caste OK' => l10n.prefCasteInter,
        _ => v,
      };

  String _educationLabel(AppLocalizations l10n, String v) => switch (v) {
        'Any Degree' => l10n.prefEduAnyDegree,
        'Any' => l10n.commonAny,
        _ => v, // degree acronyms stay English
      };

  String _occupationLabel(AppLocalizations l10n, String v) => switch (v) {
        'Software / IT' => l10n.prefOccSoftwareIt,
        'Doctor' => l10n.occDoctor,
        'Government' => l10n.empGovernment,
        'Business' => l10n.empBusiness,
        'Any' => l10n.commonAny,
        _ => v,
      };

  String _locationLabel(AppLocalizations l10n, String v) => switch (v) {
        'Same City' => l10n.prefLocSameCity,
        'Same State' => l10n.prefLocSameState,
        'Anywhere in India' => l10n.prefLocAnywhereIndia,
        'NRI OK' => l10n.prefLocNri,
        'Any' => l10n.commonAny,
        _ => v,
      };

  String _tongueLabel(AppLocalizations l10n, String v) => switch (v) {
        'Same Mother Tongue' => l10n.prefTongueSame,
        'Tamil' => l10n.langTamil,
        'Telugu' => l10n.langTelugu,
        'Hindi' => l10n.langHindi,
        'Any' => l10n.commonAny,
        _ => v,
      };

  String _maritalLabel(AppLocalizations l10n, String v) => switch (v) {
        'Never Married' => l10n.maritalNeverMarried,
        'Doesn\'t Matter' => l10n.prefMaritalDoesntMatter,
        'Any' => l10n.commonAny,
        _ => v,
      };

  /// 'Any' -> localized, numeric ranges kept as-is.
  String _anyOrSelf(AppLocalizations l10n, String v) =>
      v == 'Any' ? l10n.commonAny : v;

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
          _section(l10n.registrationPrefAgeLabel, _ageRanges, _ageRange, (v) => setState(() => _ageRange = v), labelOf: (v) => _anyOrSelf(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefHeightLabel, _heightRanges, _heightRange, (v) => setState(() => _heightRange = v), labelOf: (v) => _anyOrSelf(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefReligionLabel, _religions, _religionPref, (v) => setState(() => _religionPref = v), labelOf: (v) => _religionLabel(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefCasteLabel, _castes, _castePref, (v) => setState(() => _castePref = v), labelOf: (v) => _casteLabel(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefEducationLabel, _educations, _educationPref, (v) => setState(() => _educationPref = v), labelOf: (v) => _educationLabel(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefOccupationLabel, _occupations, _occupationPref, (v) => setState(() => _occupationPref = v), labelOf: (v) => _occupationLabel(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefIncomeLabel, _incomes, _incomePref, (v) => setState(() => _incomePref = v), labelOf: (v) => _anyOrSelf(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefLocationLabel, _locations, _locationPref, (v) => setState(() => _locationPref = v), labelOf: (v) => _locationLabel(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefMotherTongueLabel, _tongues, _motherTonguePref, (v) => setState(() => _motherTonguePref = v), labelOf: (v) => _tongueLabel(l10n, v)),
          const SizedBox(height: 20),
          _section(l10n.registrationPrefMaritalLabel, _maritalStatuses, _maritalStatusPref, (v) => setState(() => _maritalStatusPref = v), labelOf: (v) => _maritalLabel(l10n, v)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
