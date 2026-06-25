import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../domain/models/profile_draft.dart';

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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Family Details', style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Tell us about your family', style: AppTypography.bodyMedium.copyWith(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
          const SizedBox(height: 24),
          NmTextField(label: 'Father\'s Name (Optional)', hint: 'Enter father\'s name', controller: _fatherNameCtrl, onChanged: (_) => _emit(), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s'-]"))]),
          const SizedBox(height: 16),
          NmTextField(label: 'Father\'s Occupation (Optional)', hint: 'e.g., Retired Government Officer', controller: _fatherOccCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: 'Mother\'s Name (Optional)', hint: 'Enter mother\'s name', controller: _motherNameCtrl, onChanged: (_) => _emit(), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s'-]"))]),
          const SizedBox(height: 16),
          NmTextField(label: 'Mother\'s Occupation (Optional)', hint: 'e.g., Homemaker', controller: _motherOccCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 20),
          Text('Family Type', style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _familyTypes.map((t) { final sel = _familyType == t; return ChoiceChip(label: Text(t), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { setState(() => _familyType = t); _emit(); }); }).toList()),
          const SizedBox(height: 20),
          Text('Family Values', style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _familyValuesList.map((v) { final sel = _familyValues == v; return ChoiceChip(label: Text(v), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { setState(() => _familyValues = v); _emit(); }); }).toList()),
          const SizedBox(height: 20),
          Text('Family Status', style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _familyStatuses.map((s) { final sel = _familyStatus == s; return ChoiceChip(label: Text(s), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { setState(() => _familyStatus = s); _emit(); }); }).toList()),
          const SizedBox(height: 20),
          _counterRow('No. of Brothers', _brothers, (v) => setState(() => _brothers = v)),
          _counterRow('No. of Sisters', _sisters, (v) => setState(() => _sisters = v)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
