import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../domain/models/profile_draft.dart';

/// Step 7 — Lifestyle
class StepLifestyle extends StatefulWidget {
  final LifestyleDetails details;
  final void Function(LifestyleDetails) onChanged;

  const StepLifestyle({super.key, required this.details, required this.onChanged});

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

  Widget _choiceSection(String title, List<String> opts, String selected, void Function(String) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: opts.map((o) { final sel = selected == o; return ChoiceChip(label: Text(o), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { onSelect(o); _emit(); }); }).toList()),
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
          Text('Lifestyle', style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Your habits and interests', style: AppTypography.bodyMedium.copyWith(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
          const SizedBox(height: 24),
          _choiceSection('Eating Habit', _eatingHabits, _eatingHabit, (v) => setState(() => _eatingHabit = v)),
          const SizedBox(height: 20),
          _choiceSection('Smoking', _smokingOpts, _smoking, (v) => setState(() => _smoking = v)),
          const SizedBox(height: 20),
          _choiceSection('Drinking', _drinkingOpts, _drinking, (v) => setState(() => _drinking = v)),
          const SizedBox(height: 20),
          _choiceSection('Fitness / Exercise', _fitnessOpts, _fitness, (v) => setState(() => _fitness = v)),
          const SizedBox(height: 20),
          Text('Hobbies', style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _hobbiesOpts.map((h) {
              final sel = _hobbies.contains(h);
              return FilterChip(label: Text(h), selected: sel, selectedColor: AppColors.primarySurface, checkmarkColor: AppColors.primary, onSelected: (v) { setState(() { v ? _hobbies.add(h) : _hobbies.remove(h); }); _emit(); });
            }).toList(),
          ),
          const SizedBox(height: 20),
          NmTextField(label: 'About Me', hint: 'Tell us about yourself, your interests, and what you are looking for...', controller: _aboutMeCtrl, maxLines: 4, maxLength: 500, onChanged: (_) => _emit()),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
