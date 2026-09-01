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

/// Step 6 — "Highest qualification". College is asked on the same screen but
/// is optional: the backend does not require it, so it must not block a
/// member who studied somewhere the list has never heard of.
class OnboardingEducationPage extends ConsumerStatefulWidget {
  const OnboardingEducationPage({super.key});

  @override
  ConsumerState<OnboardingEducationPage> createState() =>
      _OnboardingEducationPageState();
}

class _OnboardingEducationPageState
    extends ConsumerState<OnboardingEducationPage> {
  OnboardingEducationForm _form = const OnboardingEducationForm();
  late final TextEditingController _collegeCtrl;

  @override
  void initState() {
    super.initState();
    final education = ref.read(registrationProvider).educationDetails;
    _form = OnboardingEducationForm(
      qualification: OnboardingScaffold.restore(
        education.qualification,
        ProfileOptions.qualifications,
      ),
      college: education.college,
    );
    _collegeCtrl = TextEditingController(text: _form.college);
  }

  @override
  void dispose() {
    _collegeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return OnboardingStepScaffold(
      eyebrow: l10n.onboardingEducationEyebrow,
      headline: l10n.onboardingEducationHeadline,
      crestIcon: Icons.school_rounded,
      backRoute: RouteNames.onboardingMarital,
      nextRoute: RouteNames.onboardingIncome,
      isComplete: _form.isComplete,
      validationNames: [
        if (!_form.isComplete) l10n.onboardingQualificationLabel,
      ],
      onSave: () => ref
          .read(registrationProvider.notifier)
          .applyOnboardingEducation(_form),
      fields: [
        OnboardingDropdownField(
          label: l10n.onboardingQualificationLabel,
          hint: l10n.onboardingQualificationHint,
          value: _form.qualification,
          options: ProfileOptions.qualifications,
          showHeading: false,
          isRequired: true,
          onChanged: (v) =>
              setState(() => _form = _form.copyWith(qualification: v ?? '')),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.onboardingCollegeLabel,
              style: AppTypography.titleMedium.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Free text rather than a dropdown: there is no college list in
            // the app or the backend, and guessing one would exclude most
            // institutions a member could name.
            NmTextField(
              label: l10n.onboardingCollegeFieldLabel,
              hint: l10n.onboardingCollegeHint,
              controller: _collegeCtrl,
              textInputAction: TextInputAction.done,
              onChanged: (v) => _form = _form.copyWith(college: v.trim()),
            ),
          ],
        ),
      ],
    );
  }
}
