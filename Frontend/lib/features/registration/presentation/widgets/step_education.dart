import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
import 'registration_helper_tip.dart';

/// Step 5 — Education & Career
class StepEducation extends StatefulWidget {
  final EducationDetails details;
  final void Function(EducationDetails) onChanged;

  const StepEducation({super.key, required this.details, required this.onChanged});

  @override
  State<StepEducation> createState() => _StepEducationState();
}

class _StepEducationState extends State<StepEducation> {
  late String _qualification;
  late final TextEditingController _collegeCtrl;
  late String _occupation;
  late final TextEditingController _companyCtrl;
  late String _employmentType;
  late String _annualIncome;
  late final TextEditingController _workLocationCtrl;

  static const _qualifications = ['B.E / B.Tech', 'M.Tech / M.E', 'MBBS / MD', 'MBA / PGDM', 'B.Sc / M.Sc', 'CA / CFA', 'B.Com / M.Com', 'Ph.D', 'Diploma', 'Other'];
  static const _occupations = ['Software Engineer', 'Doctor', 'IAS / IPS / Govt', 'Business Owner', 'Finance / Banking', 'Civil / Mechanical Engg', 'Teacher / Professor', 'Lawyer', 'Architect', 'Other'];
  static const _employmentTypes = ['Private', 'Government', 'Business', 'Self-Employed', 'Not Working', 'Student'];
  static const _incomeRanges = ['Below 5 Lakhs', '5 - 10 Lakhs', '10 - 20 Lakhs', '20 - 50 Lakhs', '50 Lakhs - 1 Crore', '1 Crore+', 'Prefer not to say'];

  @override
  void initState() {
    super.initState();
    _qualification = widget.details.qualification;
    _collegeCtrl = TextEditingController(text: widget.details.college);
    _occupation = widget.details.occupation;
    _companyCtrl = TextEditingController(text: widget.details.company);
    _employmentType = widget.details.employmentType;
    _annualIncome = widget.details.annualIncome;
    _workLocationCtrl = TextEditingController(text: widget.details.workLocation);
  }

  @override
  void dispose() {
    _collegeCtrl.dispose();
    _companyCtrl.dispose();
    _workLocationCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(EducationDetails(qualification: _qualification, college: _collegeCtrl.text.trim(), occupation: _occupation, company: _companyCtrl.text.trim(), employmentType: _employmentType, annualIncome: _annualIncome, workLocation: _workLocationCtrl.text.trim()));
  }

  /// Localized display label for a stored occupation value (value stays English).
  String _occupationLabel(AppLocalizations l10n, String value) =>
      switch (value) {
        'Software Engineer' => l10n.occSoftwareEngineer,
        'Doctor' => l10n.occDoctor,
        'IAS / IPS / Govt' => l10n.occGovt,
        'Business Owner' => l10n.occBusinessOwner,
        'Finance / Banking' => l10n.occFinanceBanking,
        'Civil / Mechanical Engg' => l10n.occCivilMechEngg,
        'Teacher / Professor' => l10n.occTeacherProfessor,
        'Lawyer' => l10n.occLawyer,
        'Architect' => l10n.occArchitect,
        'Other' => l10n.occOther,
        _ => value,
      };

  /// Localized display label for a stored employment-type value.
  String _employmentLabel(AppLocalizations l10n, String value) =>
      switch (value) {
        'Private' => l10n.empPrivate,
        'Government' => l10n.empGovernment,
        'Business' => l10n.empBusiness,
        'Self-Employed' => l10n.empSelfEmployed,
        'Not Working' => l10n.empNotWorking,
        'Student' => l10n.empStudent,
        _ => value,
      };

  /// Localized display label for a stored income-range value.
  String _incomeLabel(AppLocalizations l10n, String value) => switch (value) {
        'Below 5 Lakhs' => l10n.income5Below,
        '5 - 10 Lakhs' => l10n.income5to10,
        '10 - 20 Lakhs' => l10n.income10to20,
        '20 - 50 Lakhs' => l10n.income20to50,
        '50 Lakhs - 1 Crore' => l10n.income50to100,
        '1 Crore+' => l10n.income100Plus,
        'Prefer not to say' => l10n.incomePreferNotSay,
        _ => value,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.registrationWizardEducationHeadline, style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.registrationWizardEducationHook, style: AppTypography.bodyMedium.copyWith(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipEducation),
          const SizedBox(height: 24),
          Text(l10n.registrationQualificationLabel, style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          // Degree acronyms (B.E, MBBS, MBA…) stay English by convention.
          Wrap(spacing: 8, runSpacing: 8, children: _qualifications.map((q) { final sel = _qualification == q; return ChoiceChip(label: Text(q), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { setState(() => _qualification = q); _emit(); }); }).toList()),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationCollegeLabel, hint: l10n.registrationCollegeHint, controller: _collegeCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 20),
          Text(l10n.registrationOccupationLabel, style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _occupations.map((o) { final sel = _occupation == o; return ChoiceChip(label: Text(_occupationLabel(l10n, o)), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { setState(() => _occupation = o); _emit(); }); }).toList()),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationCompanyLabel, hint: l10n.registrationCompanyHint, controller: _companyCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 20),
          Text(l10n.registrationEmploymentTypeLabel, style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _employmentTypes.map((e) { final sel = _employmentType == e; return ChoiceChip(label: Text(_employmentLabel(l10n, e)), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { setState(() => _employmentType = e); _emit(); }); }).toList()),
          const SizedBox(height: 20),
          Text(l10n.registrationAnnualIncomeLabel, style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _incomeRanges.map((i) { final sel = _annualIncome == i; return ChoiceChip(label: Text(_incomeLabel(l10n, i)), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { setState(() => _annualIncome = i); _emit(); }); }).toList()),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationWorkLocationLabel, hint: l10n.registrationWorkLocationHint, controller: _workLocationCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
