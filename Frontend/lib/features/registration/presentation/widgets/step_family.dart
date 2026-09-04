import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
import 'registration_helper_tip.dart';
import 'step_body.dart';

/// A single dynamic sibling row's editing state — owns its own controllers
/// so add/remove doesn't disturb sibling rows above/below it.
class _SiblingRow {
  SiblingRelation relation;
  final TextEditingController nameCtrl;
  final TextEditingController ageCtrl;
  final TextEditingController occupationCtrl;

  _SiblingRow({
    this.relation = SiblingRelation.brother,
    String name = '',
    int? age,
    String occupation = '',
  })  : nameCtrl = TextEditingController(text: name),
        ageCtrl = TextEditingController(text: age?.toString() ?? ''),
        occupationCtrl = TextEditingController(text: occupation);

  SiblingMember toMember() => SiblingMember(
        relation: relation,
        name: nameCtrl.text.trim(),
        age: int.tryParse(ageCtrl.text.trim()),
        occupation: occupationCtrl.text.trim(),
      );

  void dispose() {
    nameCtrl.dispose();
    ageCtrl.dispose();
    occupationCtrl.dispose();
  }
}

/// Step 8 — Family Details. Entire step is skippable; nothing here is
/// required-if-filled (unlike Education/Lifestyle), so partial entries are
/// fine — see registration_rules docs for why.
class StepFamily extends StatefulWidget {
  final FamilyDetails details;
  final void Function(FamilyDetails) onChanged;
  /// See [StepBody.scrollable].
  final bool scrollable;

  const StepFamily({
    super.key,
    required this.details,
    required this.onChanged,
    this.scrollable = true,
  });

  @override
  State<StepFamily> createState() => _StepFamilyState();
}

class _StepFamilyState extends State<StepFamily> {
  late final TextEditingController _fatherNameCtrl;
  late final TextEditingController _fatherAgeCtrl;
  late final TextEditingController _fatherOccCtrl;
  late final TextEditingController _motherNameCtrl;
  late final TextEditingController _motherAgeCtrl;
  late final TextEditingController _motherOccCtrl;
  late String _familyType;
  late String _familyValues;
  late String _familyStatus;
  late List<_SiblingRow> _siblings;

  static const _familyTypes = ['Joint Family', 'Nuclear Family'];
  static const _familyValuesList = ['Traditional', 'Moderate', 'Liberal'];
  static const _familyStatuses = ['Middle Class', 'Upper Middle Class', 'Rich', 'Affluent'];

  @override
  void initState() {
    super.initState();
    _fatherNameCtrl = TextEditingController(text: widget.details.father.name);
    _fatherAgeCtrl =
        TextEditingController(text: widget.details.father.age?.toString() ?? '');
    _fatherOccCtrl = TextEditingController(text: widget.details.father.occupation);
    _motherNameCtrl = TextEditingController(text: widget.details.mother.name);
    _motherAgeCtrl =
        TextEditingController(text: widget.details.mother.age?.toString() ?? '');
    _motherOccCtrl = TextEditingController(text: widget.details.mother.occupation);
    _familyType = widget.details.familyType;
    _familyValues = widget.details.familyValues;
    _familyStatus = widget.details.familyStatus;
    _siblings = widget.details.siblings
        .map((s) => _SiblingRow(
              relation: s.relation,
              name: s.name,
              age: s.age,
              occupation: s.occupation,
            ))
        .toList();
  }

  @override
  void dispose() {
    _fatherNameCtrl.dispose();
    _fatherAgeCtrl.dispose();
    _fatherOccCtrl.dispose();
    _motherNameCtrl.dispose();
    _motherAgeCtrl.dispose();
    _motherOccCtrl.dispose();
    for (final row in _siblings) {
      row.dispose();
    }
    super.dispose();
  }

  void _emit() {
    widget.onChanged(FamilyDetails(
      father: FamilyMember(
        name: _fatherNameCtrl.text.trim(),
        age: int.tryParse(_fatherAgeCtrl.text.trim()),
        occupation: _fatherOccCtrl.text.trim(),
      ),
      mother: FamilyMember(
        name: _motherNameCtrl.text.trim(),
        age: int.tryParse(_motherAgeCtrl.text.trim()),
        occupation: _motherOccCtrl.text.trim(),
      ),
      siblings: _siblings.map((row) => row.toMember()).toList(),
      familyType: _familyType,
      familyValues: _familyValues,
      familyStatus: _familyStatus,
    ));
  }

  void _addSibling() {
    setState(() => _siblings.add(_SiblingRow()));
    _emit();
  }

  void _removeSibling(int index) {
    setState(() => _siblings.removeAt(index).dispose());
    _emit();
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

  Widget _siblingRow(AppLocalizations l10n, int index) {
    final row = _siblings[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariantLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ChoiceChip(
                label: Text(l10n.registrationSiblingBrotherLabel),
                selected: row.relation == SiblingRelation.brother,
                selectedColor: AppColors.primarySurface,
                onSelected: (_) {
                  setState(() => row.relation = SiblingRelation.brother);
                  _emit();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(l10n.registrationSiblingSisterLabel),
                selected: row.relation == SiblingRelation.sister,
                selectedColor: AppColors.primarySurface,
                onSelected: (_) {
                  setState(() => row.relation = SiblingRelation.sister);
                  _emit();
                },
              ),
              const Spacer(),
              IconButton(
                onPressed: () => _removeSibling(index),
                icon: const Icon(Icons.delete_outline_rounded),
                color: AppColors.error,
                tooltip: l10n.registrationRemoveSiblingLabel,
              ),
            ],
          ),
          const SizedBox(height: 12),
          NmTextField(
            label: l10n.registrationSiblingNameLabel,
            hint: l10n.registrationSiblingNameHint,
            controller: row.nameCtrl,
            onChanged: (_) => _emit(),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s'-]"))],
          ),
          const SizedBox(height: 12),
          NmTextField(
            label: l10n.registrationSiblingAgeLabel,
            hint: l10n.registrationSiblingAgeHint,
            controller: row.ageCtrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => _emit(),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 12),
          NmTextField(
            label: l10n.registrationSiblingOccupationLabel,
            hint: l10n.registrationSiblingOccupationHint,
            controller: row.occupationCtrl,
            onChanged: (_) => _emit(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return StepBody(
      scrollable: widget.scrollable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.registrationWizardFamilyHeadline, style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.registrationWizardFamilyHook, style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondaryLight)),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipFamily),
          const SizedBox(height: 24),
          Text(l10n.registrationFatherSectionLabel, style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          NmTextField(label: l10n.registrationFatherNameLabel, hint: l10n.registrationFatherNameHint, controller: _fatherNameCtrl, onChanged: (_) => _emit(), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s'-]"))]),
          const SizedBox(height: 12),
          NmTextField(label: l10n.registrationFatherAgeLabel, hint: l10n.registrationFatherAgeHint, controller: _fatherAgeCtrl, keyboardType: TextInputType.number, onChanged: (_) => _emit(), inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
          const SizedBox(height: 12),
          NmTextField(label: l10n.registrationFatherOccLabel, hint: l10n.registrationFatherOccHint, controller: _fatherOccCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 24),
          Text(l10n.registrationMotherSectionLabel, style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          NmTextField(label: l10n.registrationMotherNameLabel, hint: l10n.registrationMotherNameHint, controller: _motherNameCtrl, onChanged: (_) => _emit(), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s'-]"))]),
          const SizedBox(height: 12),
          NmTextField(label: l10n.registrationMotherAgeLabel, hint: l10n.registrationMotherAgeHint, controller: _motherAgeCtrl, keyboardType: TextInputType.number, onChanged: (_) => _emit(), inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
          const SizedBox(height: 12),
          NmTextField(label: l10n.registrationMotherOccLabel, hint: l10n.registrationMotherOccHint, controller: _motherOccCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 24),
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
          const SizedBox(height: 24),
          Text(l10n.registrationSiblingsSectionLabel, style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          for (var i = 0; i < _siblings.length; i++) _siblingRow(l10n, i),
          OutlinedButton.icon(
            onPressed: _addSibling,
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.registrationAddSiblingLabel),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
