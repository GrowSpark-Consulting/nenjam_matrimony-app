import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
import 'other_option_field.dart';
import 'registration_helper_tip.dart';

/// Step 6 — Physical Details. Skippable: if the user drags either slider,
/// Height/Weight/Disability all become required (Blood Group stays
/// optional) — see PhysicalDetails.isValid. Body Type and Complexion were
/// removed from the product entirely — do not reintroduce them here.
class StepPhysical extends StatefulWidget {
  final PhysicalDetails details;
  final void Function(PhysicalDetails) onChanged;

  const StepPhysical({super.key, required this.details, required this.onChanged});

  @override
  State<StepPhysical> createState() => _StepPhysicalState();
}

class _StepPhysicalState extends State<StepPhysical> {
  late int _heightCm;
  late int _weightKg;
  late bool _heightTouched;
  late bool _weightTouched;
  late String _bloodGroup;
  late String _disability;

  static const _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Not Known'];
  static const _disabilities = ['None', 'Physical', 'Hearing', 'Visual', 'Speech', 'Other'];

  static const _minHeightCm = 122;
  static const _maxHeightCm = 213;
  static const _defaultHeightCm = 170;
  static const _minWeightKg = 35;
  static const _maxWeightKg = 150;
  static const _defaultWeightKg = 65;

  @override
  void initState() {
    super.initState();
    _heightTouched = widget.details.height.isNotEmpty;
    _heightCm = (_heightTouched
            ? _parseHeightCm(widget.details.height, _defaultHeightCm)
            : _defaultHeightCm)
        .clamp(_minHeightCm, _maxHeightCm);
    _weightTouched = widget.details.weight.isNotEmpty;
    _weightKg = (_weightTouched
            ? _parseLeadingInt(widget.details.weight, _defaultWeightKg)
            : _defaultWeightKg)
        .clamp(_minWeightKg, _maxWeightKg);
    _bloodGroup = widget.details.bloodGroup;
    _disability = widget.details.disability.isEmpty ? 'None' : widget.details.disability;
  }

  static int _parseHeightCm(String value, int fallback) {
    final feetInches = RegExp(r"(\d+)\s*'\s*(\d+)").firstMatch(value);
    if (feetInches != null) {
      final feet = int.parse(feetInches.group(1)!);
      final inches = int.parse(feetInches.group(2)!);
      return ((feet * 12 + inches) * 2.54).round();
    }
    return _parseLeadingInt(value, fallback);
  }

  static int _parseLeadingInt(String value, int fallback) {
    final leading = RegExp(r'(\d+)').firstMatch(value);
    return leading != null ? int.parse(leading.group(1)!) : fallback;
  }

  static String _heightLabel(int cm) {
    final totalInches = (cm / 2.54).round();
    final feet = totalInches ~/ 12;
    final inches = totalInches % 12;
    return '$feet\'$inches" ($cm cm)';
  }

  void _emit() {
    widget.onChanged(PhysicalDetails(
      height: _heightTouched ? '$_heightCm cm' : '',
      weight: _weightTouched ? '$_weightKg kg' : '',
      bloodGroup: _bloodGroup,
      disability: _disability,
    ));
  }

  /// Chip section with an optional value->label mapper (values stay English).
  Widget _buildChipSection(String title, List<String> options, String selected,
      void Function(String) onSelect,
      {String Function(String)? labelOf}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: options.map((o) { final sel = selected == o; return ChoiceChip(label: Text(labelOf?.call(o) ?? o), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { onSelect(o); _emit(); }); }).toList()),
      ],
    );
  }

  String _disabilityLabel(AppLocalizations l10n, String v) => switch (v) {
        'None' => l10n.disabilityNone,
        'Physical' => l10n.disabilityPhysical,
        'Hearing' => l10n.disabilityHearing,
        'Visual' => l10n.disabilityVisual,
        'Speech' => l10n.disabilitySpeech,
        'Other' => l10n.disabilityOther,
        _ => v,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.registrationWizardPhysicalHeadline, style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.registrationWizardPhysicalHook, style: AppTypography.bodyMedium.copyWith(color: secondaryColor)),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipPhysical),
          const SizedBox(height: 24),
          Text(l10n.registrationHeightLabel, style: AppTypography.labelLarge),
          const SizedBox(height: 4),
          Text(
            _heightTouched ? _heightLabel(_heightCm) : l10n.registrationTapToSetHeightLabel,
            style: AppTypography.bodyMedium.copyWith(color: secondaryColor),
          ),
          Slider(
            value: _heightCm.toDouble(),
            min: _minHeightCm.toDouble(),
            max: _maxHeightCm.toDouble(),
            divisions: _maxHeightCm - _minHeightCm,
            activeColor: AppColors.primary,
            label: _heightLabel(_heightCm),
            onChanged: (v) {
              setState(() { _heightCm = v.round(); _heightTouched = true; });
              _emit();
            },
          ),
          const SizedBox(height: 16),
          Text(l10n.registrationWeightLabel, style: AppTypography.labelLarge),
          const SizedBox(height: 4),
          Text(
            _weightTouched ? '$_weightKg kg' : l10n.registrationTapToSetWeightLabel,
            style: AppTypography.bodyMedium.copyWith(color: secondaryColor),
          ),
          Slider(
            value: _weightKg.toDouble(),
            min: _minWeightKg.toDouble(),
            max: _maxWeightKg.toDouble(),
            divisions: _maxWeightKg - _minWeightKg,
            activeColor: AppColors.primary,
            label: AppLocalizations.of(context).registrationWeightKg('$_weightKg'),
            onChanged: (v) {
              setState(() { _weightKg = v.round(); _weightTouched = true; });
              _emit();
            },
          ),
          const SizedBox(height: 16),
          _buildChipSection(l10n.registrationBloodGroupLabel, _bloodGroups, _bloodGroup, (v) => setState(() => _bloodGroup = v)),
          const SizedBox(height: 20),
          OtherOptionField(
            title: l10n.registrationDisabilityLabel,
            options: _disabilities,
            value: _disability,
            labelOf: (v) => _disabilityLabel(l10n, v),
            onChanged: (v) { setState(() => _disability = v); _emit(); },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
