import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
import 'registration_helper_tip.dart';
import 'step_body.dart';

/// Step 7 — Lifestyle
class StepLifestyle extends StatefulWidget {
  final LifestyleDetails details;
  final void Function(LifestyleDetails) onChanged;
  /// See [StepBody.scrollable].
  final bool scrollable;

  const StepLifestyle({
    super.key,
    required this.details,
    required this.onChanged,
    this.scrollable = true,
  });

  @override
  State<StepLifestyle> createState() => _StepLifestyleState();
}

class _StepLifestyleState extends State<StepLifestyle> {
  late String _eatingHabit;
  late String _smoking;
  late String _drinking;
  late String _fitness;
  late List<String> _hobbies;
  late final TextEditingController _aboutMeCtrl;

  static const _eatingHabits = ['Vegetarian', 'Non-Vegetarian', 'Eggetarian', 'Vegan', 'Jain'];
  static const _smokingOpts = ['No', 'Occasionally', 'Yes'];
  static const _drinkingOpts = ['No', 'Occasionally', 'Yes'];
  static const _fitnessOpts = ['Daily', 'Regularly', 'Occasionally', 'No'];
  static const _hobbiesOpts = ['Reading', 'Travelling', 'Cooking', 'Music', 'Sports', 'Gaming', 'Photography', 'Painting', 'Dancing', 'Yoga', 'Movies', 'Gardening'];

  @override
  void initState() {
    super.initState();
    _eatingHabit = widget.details.eatingHabit;
    _smoking = widget.details.smoking;
    _drinking = widget.details.drinking;
    _fitness = widget.details.fitness;
    _hobbies = List.from(widget.details.hobbies);
    _aboutMeCtrl = TextEditingController(text: widget.details.aboutMe);
  }

  @override
  void dispose() {
    _aboutMeCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(LifestyleDetails(eatingHabit: _eatingHabit, smoking: _smoking, drinking: _drinking, fitness: _fitness, hobbies: List.from(_hobbies), aboutMe: _aboutMeCtrl.text.trim()));
  }

  /// Chip section with an optional value->label mapper (values stay English).
  Widget _choiceSection(String title, List<String> opts, String selected,
      void Function(String) onSelect,
      {String Function(String)? labelOf}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: opts.map((o) { final sel = selected == o; return ChoiceChip(label: Text(labelOf?.call(o) ?? o), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { onSelect(o); _emit(); }); }).toList()),
      ],
    );
  }

  String _eatingLabel(AppLocalizations l10n, String v) => switch (v) {
        'Vegetarian' => l10n.eatVegetarian,
        'Non-Vegetarian' => l10n.eatNonVegetarian,
        'Eggetarian' => l10n.eatEggetarian,
        'Vegan' => l10n.eatVegan,
        'Jain' => l10n.eatJain,
        _ => v,
      };

  /// Shared Yes / No / Occasionally (+ Daily / Regularly) label mapper.
  String _frequencyLabel(AppLocalizations l10n, String v) => switch (v) {
        'Yes' => l10n.commonYes,
        'No' => l10n.commonNo,
        'Occasionally' => l10n.commonOccasionally,
        'Daily' => l10n.fitnessDaily,
        'Regularly' => l10n.fitnessRegularly,
        _ => v,
      };

  String _hobbyLabel(AppLocalizations l10n, String v) => switch (v) {
        'Reading' => l10n.hobbyReading,
        'Travelling' => l10n.hobbyTravelling,
        'Cooking' => l10n.hobbyCooking,
        'Music' => l10n.hobbyMusic,
        'Sports' => l10n.hobbySports,
        'Gaming' => l10n.hobbyGaming,
        'Photography' => l10n.hobbyPhotography,
        'Painting' => l10n.hobbyPainting,
        'Dancing' => l10n.hobbyDancing,
        'Yoga' => l10n.hobbyYoga,
        'Movies' => l10n.hobbyMovies,
        'Gardening' => l10n.hobbyGardening,
        _ => v,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return StepBody(
      scrollable: widget.scrollable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.registrationWizardLifestyleHeadline, style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.registrationWizardLifestyleHook, style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondaryLight)),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipLifestyle),
          const SizedBox(height: 24),
          _choiceSection(l10n.registrationEatingHabitLabel, _eatingHabits, _eatingHabit, (v) => setState(() => _eatingHabit = v), labelOf: (v) => _eatingLabel(l10n, v)),
          const SizedBox(height: 20),
          _choiceSection(l10n.registrationSmokingLabel, _smokingOpts, _smoking, (v) => setState(() => _smoking = v), labelOf: (v) => _frequencyLabel(l10n, v)),
          const SizedBox(height: 20),
          _choiceSection(l10n.registrationDrinkingLabel, _drinkingOpts, _drinking, (v) => setState(() => _drinking = v), labelOf: (v) => _frequencyLabel(l10n, v)),
          const SizedBox(height: 20),
          _choiceSection(l10n.registrationFitnessLabel, _fitnessOpts, _fitness, (v) => setState(() => _fitness = v), labelOf: (v) => _frequencyLabel(l10n, v)),
          const SizedBox(height: 20),
          Text(l10n.registrationHobbiesLabel, style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _hobbiesOpts.map((h) {
              final sel = _hobbies.contains(h);
              return FilterChip(label: Text(_hobbyLabel(l10n, h)), selected: sel, selectedColor: AppColors.primarySurface, checkmarkColor: AppColors.primary, onSelected: (v) { setState(() { v ? _hobbies.add(h) : _hobbies.remove(h); }); _emit(); });
            }).toList(),
          ),
          const SizedBox(height: 20),
          NmTextField(label: l10n.registrationAboutMeLabel, hint: l10n.registrationAboutMeHint, controller: _aboutMeCtrl, maxLines: 4, maxLength: 500, onChanged: (_) => _emit()),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
