import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
import 'registration_helper_tip.dart';

/// Step 3 — Language Details
class StepLanguage extends StatefulWidget {
  final LanguageDetails details;
  final void Function(LanguageDetails) onChanged;

  const StepLanguage({super.key, required this.details, required this.onChanged});

  @override
  State<StepLanguage> createState() => _StepLanguageState();
}

class _StepLanguageState extends State<StepLanguage> {
  late String _motherTongue;
  late List<String> _languagesKnown;

  static const _tongues = ['Tamil', 'Telugu', 'Malayalam', 'Kannada', 'Hindi', 'English', 'Marathi', 'Bengali', 'Gujarati', 'Urdu'];
  static const _languages = ['Tamil', 'Telugu', 'Malayalam', 'Kannada', 'Hindi', 'English', 'Marathi', 'Bengali', 'Gujarati', 'Urdu', 'French', 'German', 'Arabic'];

  @override
  void initState() {
    super.initState();
    _motherTongue = widget.details.motherTongue;
    _languagesKnown = List.from(widget.details.languagesKnown);
  }

  void _emit() {
    widget.onChanged(LanguageDetails(motherTongue: _motherTongue, languagesKnown: List.from(_languagesKnown)));
  }

  /// Localized display label for a stored language value (value stays English).
  String _langLabel(AppLocalizations l10n, String value) => switch (value) {
        'Tamil' => l10n.langTamil,
        'Telugu' => l10n.langTelugu,
        'Malayalam' => l10n.langMalayalam,
        'Kannada' => l10n.langKannada,
        'Hindi' => l10n.langHindi,
        'English' => l10n.langEnglish,
        'Marathi' => l10n.langMarathi,
        'Bengali' => l10n.langBengali,
        'Gujarati' => l10n.langGujarati,
        'Urdu' => l10n.langUrdu,
        'French' => l10n.langFrench,
        'German' => l10n.langGerman,
        'Arabic' => l10n.langArabic,
        _ => value,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.registrationWizardLanguageHeadline, style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.registrationWizardLanguageHook, style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondaryLight)),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipLanguage),
          const SizedBox(height: 24),
          Text(l10n.registrationMotherTongueLabel, style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            // Values stay English (stored/emitted); only the label is localized.
            children: _tongues.map((t) {
              final sel = _motherTongue == t;
              return ChoiceChip(label: Text(_langLabel(l10n, t)), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { setState(() => _motherTongue = t); _emit(); });
            }).toList(),
          ),
          const SizedBox(height: 24),
          Text(l10n.registrationLanguagesKnownLabel, style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _languages.map((l) {
              final sel = _languagesKnown.contains(l);
              return FilterChip(
                label: Text(_langLabel(l10n, l)),
                selected: sel,
                selectedColor: AppColors.primarySurface,
                checkmarkColor: AppColors.primary,
                onSelected: (v) {
                  setState(() { v ? _languagesKnown.add(l) : _languagesKnown.remove(l); });
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
