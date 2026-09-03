import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../core/widgets/inputs/date_picker_field.dart';
import '../../../../core/widgets/sheets/app_sheets.dart';
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
/// The date is chosen from a calendar, not typed. It used to be three boxes —
/// Day, Month, Year — which asked the member to get right a format a picker
/// cannot get wrong: 31 February, a date in the future and anyone under 18
/// are now unreachable rather than rejected after the fact.
/// [OnboardingNameForm] still owns the rule for which dates are real ones,
/// because `PostAuthDestination` reconstructs that same form to decide
/// whether this step has been answered; the calendar is bounded by that rule
/// rather than restating it.
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

  /// The inline line under the date field. A picked date can never trip this
  /// — the calendar's own bounds see to that — but a draft restored from an
  /// older profile can carry a date outside them, and the member is owed the
  /// reason before being asked to pick again.
  String? _dateErrorText(AppLocalizations l10n) => switch (_form.dateError) {
        OnboardingNameDateError.invalid => l10n.onboardingNameDobInvalid,
        OnboardingNameDateError.tooYoung => l10n.onboardingNameDobTooYoung,
        OnboardingNameDateError.tooOld => l10n.onboardingNameDobTooOld,
        null => null,
      };

  /// Where the calendar opens when there is no answer yet: mid-twenties, the
  /// same start [AppSheets.showDate] and the wizard's picker have always
  /// used, so a member lands a flick from their own decade rather than
  /// eighteen years away from it.
  static DateTime _defaultInitialDate() => DateTime(DateTime.now().year - 25);

  /// "23 February 2000" — the date as a person says it. Localized where intl
  /// has symbols for the active locale and English where it does not, so the
  /// Tamil build shows a date rather than throwing.
  String _formattedDob(DateTime date, String localeName) {
    final locale = DateFormat.localeExists(localeName) ? localeName : null;
    return DateFormat('d MMMM y', locale).format(date);
  }

  Future<void> _pickDob() async {
    // A name field above may still hold focus; the keyboard left up under
    // the dialog would cover the calendar on a short phone.
    FocusScope.of(context).unfocus();
    final picked = await AppSheets.showDate(
      context,
      initialDate: _form.dob ?? _defaultInitialDate(),
      // Bounded by the form's own rule, so the calendar can only return a
      // date the form accepts — and offers every date it does.
      firstDate: OnboardingNameForm.earliestAllowedDob(),
      lastDate: OnboardingNameForm.latestAllowedDob(),
    );
    if (picked == null || !mounted) return;
    setState(() => _form = _form.withDob(picked));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dob = _form.dob;

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
          value: dob == null ? null : _formattedDob(dob, l10n.localeName),
          hint: l10n.onboardingNameDobHint,
          errorText: _dateErrorText(l10n),
          onTap: _pickDob,
        ),
      ],
    );
  }
}

/// "Date of birth" over one tappable field — the reference's heading and its
/// band of space above, with a calendar behind the field instead of three
/// boxes to type into. Built from [NmDatePickerField] so the input styling is
/// the theme's and not this screen's, exactly as the boxes it replaces were.
class _DateOfBirthSection extends StatelessWidget {
  const _DateOfBirthSection({
    required this.value,
    required this.hint,
    required this.errorText,
    required this.onTap,
  });

  /// The chosen date, already formatted. Null when unanswered.
  final String? value;
  final String hint;
  final String? errorText;
  final VoidCallback onTap;

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
        const SizedBox(height: AppSpacing.base),
        // No floating label: the heading above already says "Date of birth",
        // and the field's job is to show the answer.
        NmDatePickerField(value: value, hint: hint, onTap: onTap),
        if (errorText != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            errorText!,
            style: AppTypography.labelSmall.copyWith(color: colors.error),
          ),
        ],
      ],
    );
  }
}
