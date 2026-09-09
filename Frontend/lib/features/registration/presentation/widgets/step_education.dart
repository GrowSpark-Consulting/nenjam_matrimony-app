import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/profile_options.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
import 'other_option_field.dart';
import 'registration_helper_tip.dart';
import 'step_body.dart';

/// Step 5 — Education & Career
class StepEducation extends StatefulWidget {
  final EducationDetails details;
  final void Function(EducationDetails) onChanged;
  /// See [StepBody.scrollable].
  final bool scrollable;

  const StepEducation({
    super.key,
    required this.details,
    required this.onChanged,
    this.scrollable = true,
  });

  @override
  State<StepEducation> createState() => _StepEducationState();
}

class _StepEducationState extends State<StepEducation> {
  late String _qualification;
  late final TextEditingController _collegeCtrl;
  late String _occupation;
  late final TextEditingController _companyCtrl;
  late String _employmentType;
  late String _workIndustry;
  late String _annualIncome;
  late final TextEditingController _workLocationCtrl;

  // Shared lists plus this step's own 'Other' escape, which OtherOptionField
  // pairs with a free-text field so the literal 'Other' is never persisted.
  static const _qualifications = [...ProfileOptions.qualifications, 'Other'];
  static const _occupations = [...ProfileOptions.occupations, 'Other'];
  // Wrapped in OtherOptionField like every other dropdown on this step, so
  // the escape persists what the member types rather than the literal
  // placeholder — which the backend counts as unanswered.
  static const _employmentTypes = [...ProfileOptions.employmentTypes, 'Other'];
  static const _industries = [...ProfileOptions.industries, 'Other'];
  static const _incomeRanges = [...ProfileOptions.incomeRanges, 'Other'];

  @override
  void initState() {
    super.initState();
    _qualification = widget.details.qualification;
    _collegeCtrl = TextEditingController(text: widget.details.college);
    _occupation = widget.details.occupation;
    _companyCtrl = TextEditingController(text: widget.details.company);
    _employmentType = widget.details.employmentType;
    _workIndustry = widget.details.workIndustry;
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
    widget.onChanged(EducationDetails(qualification: _qualification, college: _collegeCtrl.text.trim(), occupation: _occupation, company: _companyCtrl.text.trim(), employmentType: _employmentType, workIndustry: _workIndustry, annualIncome: _annualIncome, workLocation: _workLocationCtrl.text.trim()));
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
        'Other' => l10n.incomeOther,
        _ => value,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return StepBody(
      scrollable: widget.scrollable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.registrationWizardEducationHeadline, style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.registrationWizardEducationHook, style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondaryLight)),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipEducation),
          const SizedBox(height: 24),
          // Degree acronyms (B.E, MBBS, MBA…) stay English by convention.
          OtherOptionField(
            title: l10n.registrationQualificationLabel,
            options: _qualifications,
            value: _qualification,
            customFieldLabel: l10n.registrationSpecifyQualificationLabel,
            customFieldHint: l10n.registrationSpecifyQualificationHint,
            onChanged: (v) { setState(() => _qualification = v); _emit(); },
          ),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationCollegeLabel, hint: l10n.registrationCollegeHint, controller: _collegeCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 20),
          OtherOptionField(
            title: l10n.registrationAnnualIncomeLabel,
            options: _incomeRanges,
            value: _annualIncome,
            labelOf: (v) => _incomeLabel(l10n, v),
            customFieldLabel: l10n.registrationAnnualIncomeOtherLabel,
            customFieldHint: l10n.registrationAnnualIncomeOtherHint,
            customFieldKeyboardType: TextInputType.number,
            customFieldInputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) { setState(() => _annualIncome = v); _emit(); },
          ),
          const SizedBox(height: 20),
          // "You work with" — the existing employmentType field, now a real
          // dropdown instead of a chip row. Same field, same stored strings,
          // same column: every value a live profile already holds is still
          // offered (see ProfileOptions.employmentTypes).
          OtherOptionField(
            title: l10n.registrationEmploymentTypeLabel,
            options: _employmentTypes,
            value: _employmentType,
            labelOf: (v) => _employmentLabel(l10n, v),
            customFieldLabel: l10n.registrationSpecifyEmploymentTypeLabel,
            customFieldHint: l10n.registrationSpecifyEmploymentTypeHint,
            onChanged: (v) { setState(() => _employmentType = v); _emit(); },
          ),
          const SizedBox(height: 20),
          OtherOptionField(
            title: l10n.registrationIndustryLabel,
            options: _industries,
            value: _workIndustry,
            customFieldLabel: l10n.registrationSpecifyIndustryLabel,
            customFieldHint: l10n.registrationSpecifyIndustryHint,
            onChanged: (v) { setState(() => _workIndustry = v); _emit(); },
          ),
          const SizedBox(height: 20),
          OtherOptionField(
            title: l10n.registrationOccupationLabel,
            options: _occupations,
            value: _occupation,
            labelOf: (v) => _occupationLabel(l10n, v),
            customFieldLabel: l10n.registrationSpecifyOccupationLabel,
            customFieldHint: l10n.registrationSpecifyOccupationHint,
            onChanged: (v) { setState(() => _occupation = v); _emit(); },
          ),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationCompanyLabel, hint: l10n.registrationCompanyHint, controller: _companyCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationWorkLocationLabel, hint: l10n.registrationWorkLocationHint, controller: _workLocationCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
