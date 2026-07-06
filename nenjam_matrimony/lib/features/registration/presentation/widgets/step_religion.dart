import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../domain/models/profile_draft.dart';

/// Step 2 — Religion Details
class StepReligion extends StatefulWidget {
  final ReligionDetails details;
  final void Function(ReligionDetails) onChanged;

  const StepReligion({super.key, required this.details, required this.onChanged});

  @override
  State<StepReligion> createState() => _StepReligionState();
}

class _StepReligionState extends State<StepReligion> {
  late String _religion;
  late final TextEditingController _casteCtrl;
  late final TextEditingController _subCasteCtrl;
  late final TextEditingController _gothraCtrl;
  late final TextEditingController _denominationCtrl;
  late final TextEditingController _communityCtrl;

  static const _religions = ['Hindu', 'Christian', 'Muslim', 'Jain', 'Sikh', 'Buddhist', 'Inter-Religion', 'Other'];

  @override
  void initState() {
    super.initState();
    _religion = widget.details.religion;
    _casteCtrl = TextEditingController(text: widget.details.caste);
    _subCasteCtrl = TextEditingController(text: widget.details.subCaste);
    _gothraCtrl = TextEditingController(text: widget.details.gothra);
    _denominationCtrl = TextEditingController(text: widget.details.denomination);
    _communityCtrl = TextEditingController(text: widget.details.community);
  }

  @override
  void dispose() {
    _casteCtrl.dispose();
    _subCasteCtrl.dispose();
    _gothraCtrl.dispose();
    _denominationCtrl.dispose();
    _communityCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(ReligionDetails(
      religion: _religion,
      caste: _casteCtrl.text.trim(),
      subCaste: _subCasteCtrl.text.trim(),
      gothra: _gothraCtrl.text.trim(),
      denomination: _denominationCtrl.text.trim(),
      community: _communityCtrl.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Religion & Community', style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Your religious background', style: AppTypography.bodyMedium.copyWith(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
          const SizedBox(height: 24),
          Text('Religion', style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _religions.map((r) {
              final sel = _religion == r;
              return ChoiceChip(label: Text(r), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { setState(() => _religion = r); _emit(); });
            }).toList(),
          ),
          const SizedBox(height: 20),
          NmTextField(label: 'Caste', hint: 'e.g., Iyer, Iyengar, Mudaliar', controller: _casteCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: 'Sub Caste (Optional)', hint: 'Enter sub caste', controller: _subCasteCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: 'Gothra (Optional)', hint: 'Enter gothra', controller: _gothraCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: 'Denomination (Optional)', hint: 'Enter denomination', controller: _denominationCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: 'Community', hint: 'e.g., Tamil, Telugu, Kannada', controller: _communityCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
