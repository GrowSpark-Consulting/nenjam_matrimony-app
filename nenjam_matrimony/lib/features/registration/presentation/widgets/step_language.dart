import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/profile_draft.dart';

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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Languages', style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Your language preferences', style: AppTypography.bodyMedium.copyWith(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
          const SizedBox(height: 24),
          Text('Mother Tongue', style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tongues.map((t) {
              final sel = _motherTongue == t;
              return ChoiceChip(label: Text(t), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { setState(() => _motherTongue = t); _emit(); });
            }).toList(),
          ),
          const SizedBox(height: 24),
          Text('Languages Known', style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _languages.map((l) {
              final sel = _languagesKnown.contains(l);
              return FilterChip(
                label: Text(l),
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
