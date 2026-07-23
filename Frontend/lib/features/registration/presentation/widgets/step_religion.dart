import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
import 'other_option_field.dart';
import 'registration_helper_tip.dart';

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

  /// Localized display label for a stored religion value (value stays English).
  String _religionLabel(AppLocalizations l10n, String value) => switch (value) {
        'Hindu' => l10n.religionHindu,
        'Christian' => l10n.religionChristian,
        'Muslim' => l10n.religionMuslim,
        'Jain' => l10n.religionJain,
        'Sikh' => l10n.religionSikh,
        'Buddhist' => l10n.religionBuddhist,
        'Inter-Religion' => l10n.religionInterReligion,
        'Other' => l10n.religionOther,
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
          Text(l10n.registrationWizardReligionHeadline, style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.registrationWizardReligionHook, style: AppTypography.bodyMedium.copyWith(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipReligion),
          const SizedBox(height: 24),
          OtherOptionField(
            title: l10n.registrationReligionLabel,
            options: _religions,
            value: _religion,
            labelOf: (v) => _religionLabel(l10n, v),
            customFieldLabel: l10n.registrationSpecifyReligionLabel,
            customFieldHint: l10n.registrationSpecifyReligionHint,
            onChanged: (v) { setState(() => _religion = v); _emit(); },
          ),
          const SizedBox(height: 20),
          NmTextField(label: l10n.registrationCasteLabel, hint: l10n.registrationCasteHint, controller: _casteCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationSubCasteLabel, hint: l10n.registrationSubCasteHint, controller: _subCasteCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationGothraLabel, hint: l10n.registrationGothraHint, controller: _gothraCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationDenominationLabel, hint: l10n.registrationDenominationHint, controller: _denominationCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationCommunityLabel, hint: l10n.registrationCommunityHint, controller: _communityCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
