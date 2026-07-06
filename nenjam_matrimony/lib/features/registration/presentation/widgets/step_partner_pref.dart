import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/profile_draft.dart';

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

  Widget _section(String title, List<String> opts, String selected, void Function(String) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: opts.map((o) { final sel = selected == o; return ChoiceChip(label: Text(o), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { onSelect(o); _emit(); }); }).toList()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Partner Preferences', style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('What are you looking for in a partner?', style: AppTypography.bodyMedium.copyWith(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
          const SizedBox(height: 24),
          _section('Preferred Age Range', _ageRanges, _ageRange, (v) => setState(() => _ageRange = v)),
          const SizedBox(height: 20),
          _section('Preferred Height', _heightRanges, _heightRange, (v) => setState(() => _heightRange = v)),
          const SizedBox(height: 20),
          _section('Religion', _religions, _religionPref, (v) => setState(() => _religionPref = v)),
          const SizedBox(height: 20),
          _section('Caste', _castes, _castePref, (v) => setState(() => _castePref = v)),
          const SizedBox(height: 20),
          _section('Education', _educations, _educationPref, (v) => setState(() => _educationPref = v)),
          const SizedBox(height: 20),
          _section('Occupation', _occupations, _occupationPref, (v) => setState(() => _occupationPref = v)),
          const SizedBox(height: 20),
          _section('Annual Income', _incomes, _incomePref, (v) => setState(() => _incomePref = v)),
          const SizedBox(height: 20),
          _section('Location', _locations, _locationPref, (v) => setState(() => _locationPref = v)),
          const SizedBox(height: 20),
          _section('Mother Tongue', _tongues, _motherTonguePref, (v) => setState(() => _motherTonguePref = v)),
          const SizedBox(height: 20),
          _section('Marital Status', _maritalStatuses, _maritalStatusPref, (v) => setState(() => _maritalStatusPref = v)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
