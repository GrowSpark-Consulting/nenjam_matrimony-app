import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
import 'registration_helper_tip.dart';

/// Step 9 — Horoscope Details
class StepHoroscope extends StatefulWidget {
  final HoroscopeDetails details;
  final void Function(HoroscopeDetails) onChanged;

  const StepHoroscope({
    super.key,
    required this.details,
    required this.onChanged,
  });

  @override
  State<StepHoroscope> createState() => _StepHoroscopeState();
}

class _StepHoroscopeState extends State<StepHoroscope> {
  late final TextEditingController _birthTimeCtrl;
  late final TextEditingController _birthPlaceCtrl;
  late String _rashi;
  late String _nakshatra;
  late String _star;
  late String _manglik;
  late String _dosham;
  late bool _horoscopeAvailable;

  static const _rashis = [
    'Mesha',
    'Vrishabha',
    'Mithuna',
    'Kataka',
    'Simha',
    'Kanya',
    'Tula',
    'Vrischika',
    'Dhanu',
    'Makara',
    'Kumbha',
    'Meena',
    'Don\'t Know',
  ];
  static const _nakshatras = [
    'Ashwini',
    'Bharani',
    'Krittika',
    'Rohini',
    'Mrigashira',
    'Ardra',
    'Punarvasu',
    'Pushya',
    'Ashlesha',
    'Magha',
    'Poorvaphalguni',
    'Uttaraphalguni',
    'Hasta',
    'Chitra',
    'Swati',
    'Vishakha',
    'Anuradha',
    'Jyeshta',
    'Moola',
    'Poorvashada',
    'Uttarashada',
    'Shravana',
    'Dhanishta',
    'Shatabhisha',
    'Poorvabhadra',
    'Uttarabhadra',
    'Revathi',
    'Don\'t Know',
  ];
  static const _stars = [
    'Aswini',
    'Bharani',
    'Karthigai',
    'Rohini',
    'Mrigasheersham',
    'Thiruvaathirai',
    'Punarpoosam',
    'Poosam',
    'Aayilyam',
    'Magam',
    'Pooram',
    'Uthiram',
    'Hastham',
    'Chithirai',
    'Swaathi',
    'Visaagam',
    'Anusham',
    'Kettai',
    'Moolam',
    'Pooraadam',
    'Uthiraadam',
    'Thiruvonam',
    'Avittam',
    'Sadhayam',
    'Poorattathi',
    'Uthirattathi',
    'Revathi',
    'Don\'t Know',
  ];
  static const _manglikOpts = ['Yes', 'No', 'Don\'t Know'];
  static const _doshamOpts = ['Yes', 'No', 'Don\'t Know'];

  @override
  void initState() {
    super.initState();
    _birthTimeCtrl = TextEditingController(text: widget.details.birthTime);
    _birthPlaceCtrl = TextEditingController(text: widget.details.birthPlace);
    _rashi = widget.details.rashi;
    _nakshatra = widget.details.nakshatra;
    _star = widget.details.star;
    _manglik = widget.details.manglik;
    _dosham = widget.details.dosham;
    _horoscopeAvailable = widget.details.horoscopeAvailable;
  }

  @override
  void dispose() {
    _birthTimeCtrl.dispose();
    _birthPlaceCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      HoroscopeDetails(
        birthTime: _birthTimeCtrl.text.trim(),
        birthPlace: _birthPlaceCtrl.text.trim(),
        rashi: _rashi,
        nakshatra: _nakshatra,
        star: _star,
        manglik: _manglik,
        dosham: _dosham,
        horoscopeAvailable: _horoscopeAvailable,
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      if (!mounted) return;
      _birthTimeCtrl.text = picked.format(context);
      _emit();
    }
  }

  /// Chip section with an optional value->label mapper (values stay English).
  Widget _chipSection(
    String title,
    List<String> opts,
    String selected,
    void Function(String) onSelect, {
    String Function(String)? labelOf,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: opts.map((o) {
            final sel = selected == o;
            return ChoiceChip(
              label: Text(
                labelOf?.call(o) ?? o,
                style: const TextStyle(fontSize: 13),
              ),
              selected: sel,
              selectedColor: AppColors.primarySurface,
              onSelected: (_) {
                onSelect(o);
                _emit();
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  String _rashiLabel(AppLocalizations l10n, String v) => switch (v) {
    'Mesha' => l10n.rashiMesha,
    'Vrishabha' => l10n.rashiVrishabha,
    'Mithuna' => l10n.rashiMithuna,
    'Kataka' => l10n.rashiKataka,
    'Simha' => l10n.rashiSimha,
    'Kanya' => l10n.rashiKanya,
    'Tula' => l10n.rashiTula,
    'Vrischika' => l10n.rashiVrischika,
    'Dhanu' => l10n.rashiDhanu,
    'Makara' => l10n.rashiMakara,
    'Kumbha' => l10n.rashiKumbha,
    'Meena' => l10n.rashiMeena,
    'Don\'t Know' => l10n.commonDontKnow,
    _ => v,
  };

  /// Yes / No / Don't Know for Manglik and Dosham.
  String _ynLabel(AppLocalizations l10n, String v) => switch (v) {
    'Yes' => l10n.commonYes,
    'No' => l10n.commonNo,
    'Don\'t Know' => l10n.commonDontKnow,
    _ => v,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.registrationWizardHoroscopeHeadline,
            style: AppTypography.headlineSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.registrationWizardHoroscopeHook,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipHoroscope),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.registrationHoroscopeAvailable,
                  style: AppTypography.bodyLarge,
                ),
              ),
              Switch.adaptive(
                value: _horoscopeAvailable,
                onChanged: (v) {
                  setState(() => _horoscopeAvailable = v);
                  _emit();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _pickTime,
            child: AbsorbPointer(
              child: NmTextField(
                label: l10n.registrationBirthTimeLabel,
                hint: l10n.registrationBirthTimeHint,
                controller: _birthTimeCtrl,
                readOnly: true,
                suffix: const Icon(Icons.access_time_rounded, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 16),
          NmTextField(
            label: l10n.registrationBirthPlaceLabel,
            hint: l10n.registrationBirthPlaceHint,
            controller: _birthPlaceCtrl,
            onChanged: (_) => _emit(),
          ),
          const SizedBox(height: 20),
          _chipSection(
            l10n.registrationRashiLabel,
            _rashis,
            _rashi,
            (v) => setState(() => _rashi = v),
            labelOf: (v) => _rashiLabel(l10n, v),
          ),
          const SizedBox(height: 20),
          // Nakshatra & Star names are specialized astrological proper nouns;
          // kept in their existing form pending a native astrology review.
          _chipSection(
            l10n.registrationNakshatraLabel,
            _nakshatras,
            _nakshatra,
            (v) => setState(() => _nakshatra = v),
          ),
          const SizedBox(height: 20),
          _chipSection(
            l10n.registrationStarLabel,
            _stars,
            _star,
            (v) => setState(() => _star = v),
          ),
          const SizedBox(height: 20),
          _chipSection(
            l10n.registrationManglikLabel,
            _manglikOpts,
            _manglik,
            (v) => setState(() => _manglik = v),
            labelOf: (v) => _ynLabel(l10n, v),
          ),
          const SizedBox(height: 20),
          _chipSection(
            l10n.registrationDoshamLabel,
            _doshamOpts,
            _dosham,
            (v) => setState(() => _dosham = v),
            labelOf: (v) => _ynLabel(l10n, v),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
