import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/birth_date.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../core/widgets/inputs/birth_date_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/onboarding_forms.dart';
import '../providers/registration_provider.dart';
import '../widgets/onboarding_scaffold.dart';

/// Step 2 — "Your name" and "Date of birth".
///
/// The one screen the reference gives a whole page to, and the reason it is
/// its own step: `first_name`, `last_name` and `dob` are NOT NULL on
/// `user_profiles`, they are what every Discover card renders, and asking
/// them beside a state-and-city picker (where they used to live, on
/// [ProfileBasicsPage]) buried them.
///
/// It introduces no state of its own. The three answers go to
/// `BasicDetails` — the same section, written by the same
/// `PATCH /profiles/draft/basic-details`, that the wizard's Basic Info step
/// has always used. See [RegistrationNotifier.applyOnboardingName].
///
/// The date is typed into three boxes rather than picked off a calendar: a
/// member who knows their own date of birth should be able to enter it, and
/// someone creating a profile for a son or a sister should not have to scroll
/// a picker back two decades to do it. Nothing about which dates are
/// *allowed* is decided here — [NmBirthDateField] and [BirthDateInput] own
/// that, `PostAuthDestination` reconstructs the same form to decide whether
/// this step has been answered, and the server re-checks it on the way in.
class OnboardingNamePage extends ConsumerStatefulWidget {
  const OnboardingNamePage({super.key});

  @override
  ConsumerState<OnboardingNamePage> createState() => _OnboardingNamePageState();
}

class _OnboardingNamePageState extends ConsumerState<OnboardingNamePage> {
  late OnboardingNameForm _form;

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Reopening the step shows the answers already given: a member who taps
    // Back from Religion, or relaunches mid-signup, must not retype their own
    // name. The draft is the source — it survives both, because every step
    // snapshots to disk (see RegistrationNotifier._snapshot).
    final basic = ref.read(registrationProvider).basicDetails;
    _form = OnboardingNameForm.fromDraft(
      firstName: basic.firstName,
      lastName: basic.lastName,
      dob: basic.dob,
    );
    _firstNameCtrl.text = _form.firstName;
    _lastNameCtrl.text = _form.lastName;
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  String _fieldLabel(AppLocalizations l10n, OnboardingNameField field) =>
      switch (field) {
        OnboardingNameField.firstName => l10n.registrationFirstNameLabel,
        OnboardingNameField.lastName => l10n.registrationLastNameLabel,
        OnboardingNameField.dob => l10n.registrationDobLabel,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return OnboardingStepScaffold(
      headline: l10n.onboardingNameHeadline,
      crestIcon: Icons.recent_actors_rounded,
      backRoute: RouteNames.createProfileFor,
      nextRoute: RouteNames.onboardingReligion,
      isComplete: _form.isComplete,
      validationNames:
          _form.missingFields.map((f) => _fieldLabel(l10n, f)).toList(),
      onSave: () => ref
          .read(registrationProvider.notifier)
          .applyOnboardingName(_form),
      fields: [
        NmTextField(
          label: l10n.registrationFirstNameLabel,
          controller: _firstNameCtrl,
          textCapitalization: TextCapitalization.words,
          onChanged: (v) => setState(() => _form = _form.copyWith(firstName: v)),
        ),
        NmTextField(
          label: l10n.registrationLastNameLabel,
          controller: _lastNameCtrl,
          textCapitalization: TextCapitalization.words,
          onChanged: (v) => setState(() => _form = _form.copyWith(lastName: v)),
        ),
        _DateOfBirthSection(
          value: _form.birthDate,
          onChanged: (v) =>
              setState(() => _form = _form.copyWith(birthDate: v)),
        ),
      ],
    );
  }
}

/// "Date of birth" over the three typed boxes — the reference's heading and
/// its band of space above, with [NmBirthDateField] doing the input and the
/// validating so this screen holds no copy of either.
class _DateOfBirthSection extends StatelessWidget {
  const _DateOfBirthSection({required this.value, required this.onChanged});

  final BirthDateInput value;
  final ValueChanged<BirthDateInput> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The reference sets the date apart from the names with a clear band
        // of empty space rather than a divider — whitespace over borders.
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.onboardingNameDobSection,
          style: AppTypography.headlineSmall.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // Says the format once, above the boxes, so the three labels do not
        // have to carry it and a member knows before typing rather than after
        // being corrected.
        Text(
          l10n.onboardingNameDobHelp,
          style: AppTypography.bodySmall.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        NmBirthDateField(value: value, onChanged: onChanged),
      ],
    );
  }
}
