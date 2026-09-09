import 'package:flutter/material.dart';

import '../../../../core/constants/profile_options.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/birth_date.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../core/widgets/inputs/birth_date_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
import '../../domain/models/profile_for_relation.dart';
import 'onboarding_scaffold.dart';
import 'other_option_field.dart';
import 'registration_helper_tip.dart';
import 'step_body.dart';

/// Step 1 — Basic Information
class StepBasicInfo extends StatefulWidget {
  final BasicDetails details;
  final void Function(BasicDetails) onChanged;
  /// See [StepBody.scrollable].
  final bool scrollable;

  const StepBasicInfo({
    super.key,
    required this.details,
    required this.onChanged,
    this.scrollable = true,
  });

  @override
  State<StepBasicInfo> createState() => _StepBasicInfoState();
}

class _StepBasicInfoState extends State<StepBasicInfo> {
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late String _gender;
  late String _maritalStatus;
  late String _profileCreatedFor;
  late BirthDateInput _dob;

  @override
  void initState() {
    super.initState();
    _firstNameCtrl = TextEditingController(text: widget.details.firstName);
    _lastNameCtrl = TextEditingController(text: widget.details.lastName);
    _gender = widget.details.gender;
    _maritalStatus = widget.details.maritalStatus;
    _profileCreatedFor = widget.details.profileCreatedFor;
    _dob = BirthDateInput.fromDate(widget.details.dob);
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      BasicDetails(
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        gender: _gender,
        dob: _dob.date,
        maritalStatus: _maritalStatus,
        profileCreatedFor: _profileCreatedFor,
      ),
    );
  }

  /// Every registration field is optional — this only enforces name format
  /// (letters/length) when the user actually types something, rather than
  /// requiring a value the way [Validators.name] does.
  String? _optionalName(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return Validators.name(value);
  }

  /// The age the entered date works out to, or null while it is not yet a
  /// date the rule accepts. Uses the app's one age calculation.
  int? get _age {
    final date = _dob.date;
    return date == null ? null : ageInYears(date);
  }

  /// Localized display label for a stored "profile for" value. Values stay
  /// English on the draft; only the label is translated.
  String _profileForLabel(AppLocalizations l10n, String value) =>
      switch (value) {
        'Myself' => l10n.profileForOptionMyself,
        'Son' => l10n.profileForOptionSon,
        'Daughter' => l10n.profileForOptionDaughter,
        'Brother' => l10n.profileForOptionBrother,
        'Sister' => l10n.profileForOptionSister,
        'Friend' => l10n.profileForOptionFriend,
        'Relative' => l10n.profileForOptionRelative,
        _ => value,
      };

  /// Localized display label for a stored gender value (value stays English).
  String _genderLabel(AppLocalizations l10n, String value) => switch (value) {
    'Male' => l10n.genderMale,
    'Female' => l10n.genderFemale,
    _ => value,
  };

  /// Localized display label for a stored marital-status value.
  String _maritalLabel(AppLocalizations l10n, String value) => switch (value) {
    'Never Married' => l10n.maritalNeverMarried,
    'Divorced' => l10n.maritalDivorced,
    'Widowed' => l10n.maritalWidowed,
    'Awaiting Divorce' => l10n.maritalAwaitingDivorce,
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
          Text(
            l10n.registrationWizardBasicInfoHeadline,
            style: AppTypography.headlineSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.registrationWizardBasicInfoHook,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipBasicInfo),
          const SizedBox(height: 24),
          // Field 1. The same seven relations CreateProfileForPage offers,
          // written with the same `storageValue` strings, so an edit and a
          // signup are indistinguishable to the draft and the backend.
          // `optionsWith` keeps a stored value the enum no longer lists
          // rather than blanking it on open.
          OtherOptionField(
            title: l10n.registrationProfileForLabel,
            options: OnboardingScaffold.optionsWith(
              ProfileForRelation.values.map((r) => r.storageValue).toList(),
              _profileCreatedFor,
            ),
            value: _profileCreatedFor,
            labelOf: (v) => _profileForLabel(l10n, v),
            onChanged: (v) {
              setState(() => _profileCreatedFor = v);
              _emit();
            },
          ),
          const SizedBox(height: 20),
          NmTextField(
            label: l10n.registrationFirstNameLabel,
            hint: l10n.registrationFirstNameHint,
            controller: _firstNameCtrl,
            validator: _optionalName,
            onChanged: (_) => _emit(),
          ),
          const SizedBox(height: 16),
          NmTextField(
            label: l10n.registrationLastNameLabel,
            hint: l10n.registrationLastNameHint,
            controller: _lastNameCtrl,
            validator: _optionalName,
            onChanged: (_) => _emit(),
          ),
          const SizedBox(height: 20),
          Text(l10n.registrationGenderLabel, style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Row(
            // Values stay English (stored/emitted); only the label is localized.
            children: ['Male', 'Female'].map((g) {
              final sel = _gender == g;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Center(child: Text(_genderLabel(l10n, g))),
                    selected: sel,
                    selectedColor: AppColors.primarySurface,
                    onSelected: (_) {
                      setState(() => _gender = g);
                      _emit();
                    },
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text(l10n.registrationDobLabel, style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          // The same typed DD / MM / YYYY field onboarding uses, so a member
          // editing their profile meets the input they filled in at signup
          // and the same rule decides what it accepts. The calendar this
          // replaced enforced a floor of its own (18) that had drifted from
          // the one the server applies.
          NmBirthDateField(
            value: _dob,
            onChanged: (v) {
              setState(() => _dob = v);
              _emit();
            },
          ),
          if (_age != null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.registrationAgeYears(_age!),
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            l10n.registrationMaritalStatusLabel,
            style: AppTypography.labelLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            // Values stay English (stored/emitted); only the label is localized.
            children:
                ProfileOptions.maritalStatuses.map((s) {
                  final sel = _maritalStatus == s;
                  return ChoiceChip(
                    label: Text(_maritalLabel(l10n, s)),
                    selected: sel,
                    selectedColor: AppColors.primarySurface,
                    onSelected: (_) {
                      setState(() => _maritalStatus = s);
                      _emit();
                    },
                  );
                }).toList(),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
