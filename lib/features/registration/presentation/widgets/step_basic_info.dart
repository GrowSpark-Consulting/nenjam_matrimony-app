import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';

/// Step 1 — Basic Information
class StepBasicInfo extends StatefulWidget {
  final BasicDetails details;
  final void Function(BasicDetails) onChanged;

  const StepBasicInfo({
    super.key,
    required this.details,
    required this.onChanged,
  });

  @override
  State<StepBasicInfo> createState() => _StepBasicInfoState();
}

class _StepBasicInfoState extends State<StepBasicInfo> {
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late String _gender;
  late String _maritalStatus;
  DateTime? _dob;

  @override
  void initState() {
    super.initState();
    _firstNameCtrl = TextEditingController(text: widget.details.firstName);
    _lastNameCtrl = TextEditingController(text: widget.details.lastName);
    _gender = widget.details.gender;
    _maritalStatus = widget.details.maritalStatus;
    _dob = widget.details.dob;
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(BasicDetails(
      firstName: _firstNameCtrl.text.trim(),
      lastName: _lastNameCtrl.text.trim(),
      gender: _gender,
      dob: _dob,
      maritalStatus: _maritalStatus,
      profileCreatedFor: widget.details.profileCreatedFor,
    ));
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25),
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year - 18),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppColors.primary,
                onPrimary: Colors.white,
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _dob = picked);
      _emit();
    }
  }

  int? get _age {
    if (_dob == null) return null;
    final now = DateTime.now();
    int years = now.year - _dob!.year;
    if (now.month < _dob!.month ||
        (now.month == _dob!.month && now.day < _dob!.day)) {
      years--;
    }
    return years;
  }

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.registrationBasicInfoTitle,
              style: AppTypography.headlineSmall
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.registrationBasicInfoSubtitle,
              style: AppTypography.bodyMedium.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight)),
          const SizedBox(height: 24),
          NmTextField(
            label: l10n.registrationFirstNameLabel,
            hint: l10n.registrationFirstNameHint,
            controller: _firstNameCtrl,
            validator: Validators.name,
            onChanged: (_) => _emit(),
          ),
          const SizedBox(height: 16),
          NmTextField(
            label: l10n.registrationLastNameLabel,
            hint: l10n.registrationLastNameHint,
            controller: _lastNameCtrl,
            validator: Validators.name,
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
          GestureDetector(
            onTap: _pickDob,
            child: AbsorbPointer(
              child: NmTextField(
                label: l10n.registrationDobLabel,
                hint: l10n.registrationDobHint,
                readOnly: true,
                controller: TextEditingController(
                  text: _dob != null
                      ? '${_dob!.day.toString().padLeft(2, '0')} / ${_dob!.month.toString().padLeft(2, '0')} / ${_dob!.year}'
                      : '',
                ),
                suffix: const Icon(Icons.calendar_today_rounded, size: 20),
                validator: (v) =>
                    _dob == null ? l10n.registrationDobError : null,
              ),
            ),
          ),
          if (_age != null) ...[
            const SizedBox(height: 8),
            Text(l10n.registrationAgeYears(_age!),
                style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primary, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 20),
          Text(l10n.registrationMaritalStatusLabel,
              style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            // Values stay English (stored/emitted); only the label is localized.
            children: [
              'Never Married',
              'Divorced',
              'Widowed',
              'Awaiting Divorce'
            ].map((s) {
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
