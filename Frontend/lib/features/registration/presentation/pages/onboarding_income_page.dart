import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/profile_options.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/onboarding_forms.dart';
import '../providers/registration_provider.dart';
import '../widgets/onboarding_scaffold.dart';

/// Step 7 — "Annual income" and work details. Only the income is required;
/// the three work fields sit on the same screen so a member who is working
/// answers everything at once, while one who is not can still continue.
class OnboardingIncomePage extends ConsumerStatefulWidget {
  const OnboardingIncomePage({super.key});

  @override
  ConsumerState<OnboardingIncomePage> createState() =>
      _OnboardingIncomePageState();
}

class _OnboardingIncomePageState extends ConsumerState<OnboardingIncomePage> {
  OnboardingIncomeForm _form = const OnboardingIncomeForm();
  late final TextEditingController _companyCtrl;

  @override
  void initState() {
    super.initState();
    final education = ref.read(registrationProvider).educationDetails;
    _form = OnboardingIncomeForm(
      annualIncome: OnboardingScaffold.restore(
        education.annualIncome,
        ProfileOptions.incomeRanges,
      ),
      workWith: OnboardingScaffold.restore(
        education.employmentType,
        ProfileOptions.employmentTypes,
      ),
      workAs: OnboardingScaffold.restore(
        education.occupation,
        ProfileOptions.occupations,
      ),
      companyName: education.company,
    );
    _companyCtrl = TextEditingController(text: _form.companyName);
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return OnboardingStepScaffold(
      eyebrow: l10n.onboardingIncomeEyebrow,
      headline: l10n.onboardingIncomeHeadline,
      crestIcon: Icons.work_outline_rounded,
      backRoute: RouteNames.onboardingEducation,
      nextRoute: RouteNames.onboardingPhotos,
      // The reference labels this step's CTA "Create Profile" — it is the
      // last of the typed-answer screens; what follows is photos, a
      // description and verification.
      ctaLabel: l10n.onboardingIncomeCta,
      isComplete: _form.isComplete,
      validationNames: [
        if (!_form.isComplete) l10n.onboardingIncomeLabel,
      ],
      onSave: () =>
          ref.read(registrationProvider.notifier).applyOnboardingIncome(_form),
      fields: [
        OnboardingDropdownField(
          label: l10n.onboardingIncomeLabel,
          hint: l10n.onboardingIncomeHint,
          value: _form.annualIncome,
          options: ProfileOptions.incomeRanges,
          showHeading: false,
          isRequired: true,
          helpText: l10n.onboardingIncomeWhyAnswer,
          onChanged: (v) =>
              setState(() => _form = _form.copyWith(annualIncome: v ?? '')),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.onboardingWorkHeadline,
              style: AppTypography.titleMedium.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OnboardingDropdownField(
              label: l10n.onboardingWorkWithLabel,
              hint: l10n.onboardingWorkWithHint,
              value: _form.workWith,
              options: ProfileOptions.employmentTypes,
              showHeading: false,
              onChanged: (v) =>
                  setState(() => _form = _form.copyWith(workWith: v ?? '')),
            ),
            const SizedBox(height: AppSpacing.base),
            OnboardingDropdownField(
              label: l10n.onboardingWorkAsLabel,
              hint: l10n.onboardingWorkAsHint,
              value: _form.workAs,
              options: ProfileOptions.occupations,
              showHeading: false,
              onChanged: (v) =>
                  setState(() => _form = _form.copyWith(workAs: v ?? '')),
            ),
            const SizedBox(height: AppSpacing.base),
            NmTextField(
              label: l10n.onboardingCompanyLabel,
              hint: l10n.onboardingCompanyHint,
              controller: _companyCtrl,
              textInputAction: TextInputAction.done,
              onChanged: (v) => _form = _form.copyWith(companyName: v.trim()),
            ),
          ],
        ),
      ],
    );
  }
}
