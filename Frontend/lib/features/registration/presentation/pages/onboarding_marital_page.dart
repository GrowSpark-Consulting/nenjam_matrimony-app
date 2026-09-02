import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/profile_options.dart';
import '../../../../core/router/route_names.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/onboarding_forms.dart';
import '../providers/registration_provider.dart';
import '../widgets/onboarding_scaffold.dart';

/// Step 5 — "Marital status", which the reference screen asks together with
/// height and diet. Marital status and height are required; diet is offered
/// on the same screen but never blocks Continue.
class OnboardingMaritalPage extends ConsumerStatefulWidget {
  const OnboardingMaritalPage({super.key});

  @override
  ConsumerState<OnboardingMaritalPage> createState() =>
      _OnboardingMaritalPageState();
}

class _OnboardingMaritalPageState extends ConsumerState<OnboardingMaritalPage> {
  OnboardingMaritalForm _form = const OnboardingMaritalForm();

  @override
  void initState() {
    super.initState();
    final draft = ref.read(registrationProvider);
    _form = OnboardingMaritalForm(
      maritalStatus: OnboardingScaffold.restore(
        draft.basicDetails.maritalStatus,
        ProfileOptions.maritalStatuses,
      ),
      height: OnboardingScaffold.restore(
        draft.physicalDetails.height,
        ProfileOptions.heights,
      ),
      diet: OnboardingScaffold.restore(
        draft.lifestyleDetails.eatingHabit,
        ProfileOptions.diets,
      ),
    );
  }

  String _label(AppLocalizations l10n, OnboardingMaritalField field) =>
      switch (field) {
        OnboardingMaritalField.maritalStatus => l10n.onboardingMaritalLabel,
        OnboardingMaritalField.height => l10n.onboardingHeightFieldLabel,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return OnboardingStepScaffold(
      headline: l10n.onboardingMaritalHeadline,
      crestIcon: Icons.favorite_border_rounded,
      backRoute: RouteNames.profileBasics,
      nextRoute: RouteNames.onboardingEducation,
      isComplete: _form.isComplete,
      validationNames:
          _form.missingFields.map((f) => _label(l10n, f)).toList(),
      onSave: () =>
          ref.read(registrationProvider.notifier).applyOnboardingMarital(_form),
      fields: [
        // The headline already says "Marital status", so the first field
        // carries no repeated section heading.
        OnboardingDropdownField(
          label: l10n.onboardingMaritalLabel,
          hint: l10n.onboardingMaritalHint,
          value: _form.maritalStatus,
          options: ProfileOptions.maritalStatuses,
          showHeading: false,
          isRequired: true,
          onChanged: (v) =>
              setState(() => _form = _form.copyWith(maritalStatus: v ?? '')),
        ),
        OnboardingDropdownField(
          heading: l10n.onboardingHeightLabel,
          label: l10n.onboardingHeightFieldLabel,
          hint: l10n.onboardingHeightHint,
          value: _form.height,
          options: ProfileOptions.heights,
          isRequired: true,
          onChanged: (v) =>
              setState(() => _form = _form.copyWith(height: v ?? '')),
        ),
        OnboardingDropdownField(
          heading: l10n.onboardingDietLabel,
          label: l10n.onboardingDietFieldLabel,
          hint: l10n.onboardingDietHint,
          value: _form.diet,
          options: ProfileOptions.diets,
          onChanged: (v) =>
              setState(() => _form = _form.copyWith(diet: v ?? '')),
        ),
      ],
    );
  }
}
