import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
import 'registration_helper_tip.dart';

/// Step 8 — Family Details
class StepFamily extends StatefulWidget {
  final FamilyDetails details;
  final void Function(FamilyDetails) onChanged;

  const StepFamily({super.key, required this.details, required this.onChanged});

  @override
  State<StepFamily> createState() => _StepFamilyState();
}

class _StepFamilyState extends State<StepFamily> {
  late final TextEditingController _fatherNameCtrl;
  late final TextEditingController _fatherOccCtrl;
  late final TextEditingController _motherNameCtrl;
  late final TextEditingController _motherOccCtrl;
  late String _familyType;
  late String _familyValues;
  late String _familyStatus;
  late int _brothers;
  late int _sisters;

  static const _familyTypes = ['Joint Family', 'Nuclear Family'];
  static const _familyValuesList = ['Traditional', 'Moderate', 'Liberal'];
  static const _familyStatuses = ['Middle Class', 'Upper Middle Class', 'Rich', 'Affluent'];

  @override
  void initState() {
    super.initState();
    _fatherNameCtrl = TextEditingController(text: widget.details.fatherName);
    _fatherOccCtrl = TextEditingController(text: widget.details.fatherOccupation);
    _motherNameCtrl = TextEditingController(text: widget.details.motherName);
    _motherOccCtrl = TextEditingController(text: widget.details.motherOccupation);
    _familyType = widget.details.familyType;
    _familyValues = widget.details.familyValues;
    _familyStatus = widget.details.familyStatus;
    _brothers = widget.details.brothers;
    _sisters = widget.details.sisters;
  }

  @override
  void dispose() {
    _fatherNameCtrl.dispose();
    _fatherOccCtrl.dispose();
    _motherNameCtrl.dispose();
    _motherOccCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(FamilyDetails(
      fatherName: _fatherNameCtrl.text.trim(),
      fatherOccupation: _fatherOccCtrl.text.trim(),
      motherName: _motherNameCtrl.text.trim(),
      motherOccupation: _motherOccCtrl.text.trim(),
      familyType: _familyType,
      familyValues: _familyValues,
      familyStatus: _familyStatus,
      brothers: _brothers,
      sisters: _sisters,
    ));
  }

  Widget _counterRow(String label, int count, void Function(int) onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.bodyLarge)),
        IconButton(
          onPressed: count > 0 ? () { onChanged(count - 1); _emit(); } : null,
          icon: const Icon(Icons.remove_circle_outline_rounded),
          color: AppColors.primary,
        ),
        SizedBox(
          width: 32,
          child: Text('$count', textAlign: TextAlign.center, style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700)),
        ),
        IconButton(
          onPressed: count < 10 ? () { onChanged(count + 1); _emit(); } : null,
          icon: const Icon(Icons.add_circle_outline_rounded),
          color: AppColors.primary,
        ),
      ],
    );
  }

  String _familyTypeLabel(AppLocalizations l10n, String v) => switch (v) {
        'Joint Family' => l10n.famJoint,
        'Nuclear Family' => l10n.famNuclear,
        _ => v,
      };

  String _familyValuesLabel(AppLocalizations l10n, String v) => switch (v) {
        'Traditional' => l10n.famTraditional,
        'Moderate' => l10n.famModerate,
        'Liberal' => l10n.famLiberal,
        _ => v,
      };

  String _familyStatusLabel(AppLocalizations l10n, String v) => switch (v) {
        'Middle Class' => l10n.famMiddleClass,
        'Upper Middle Class' => l10n.famUpperMiddleClass,
        'Rich' => l10n.famRich,
        'Affluent' => l10n.famAffluent,
        _ => v,
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
          Text(l10n.registrationWizardFamilyHeadline, style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.registrationWizardFamilyHook, style: AppTypography.bodyMedium.copyWith(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipFamily),
          const SizedBox(height: 24),
          NmTextField(label: l10n.registrationFatherNameLabel, hint: l10n.registrationFatherNameHint, controller: _fatherNameCtrl, onChanged: (_) => _emit(), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s'-]"))]),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationFatherOccLabel, hint: l10n.registrationFatherOccHint, controller: _fatherOccCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationMotherNameLabel, hint: l10n.registrationMotherNameHint, controller: _motherNameCtrl, onChanged: (_) => _emit(), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s'-]"))]),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationMotherOccLabel, hint: l10n.registrationMotherOccHint, controller: _motherOccCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 20),
          Text(l10n.registrationFamilyTypeLabel, style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _familyTypes.map((t) { final sel = _familyType == t; return ChoiceChip(label: Text(_familyTypeLabel(l10n, t)), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { setState(() => _familyType = t); _emit(); }); }).toList()),
          const SizedBox(height: 20),
          Text(l10n.registrationFamilyValuesLabel, style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _familyValuesList.map((v) { final sel = _familyValues == v; return ChoiceChip(label: Text(_familyValuesLabel(l10n, v)), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { setState(() => _familyValues = v); _emit(); }); }).toList()),
          const SizedBox(height: 20),
          Text(l10n.registrationFamilyStatusLabel, style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _familyStatuses.map((s) { final sel = _familyStatus == s; return ChoiceChip(label: Text(_familyStatusLabel(l10n, s)), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { setState(() => _familyStatus = s); _emit(); }); }).toList()),
          const SizedBox(height: 20),
          _counterRow(l10n.registrationBrothersLabel, _brothers, (v) => setState(() => _brothers = v)),
          _counterRow(l10n.registrationSistersLabel, _sisters, (v) => setState(() => _sisters = v)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
