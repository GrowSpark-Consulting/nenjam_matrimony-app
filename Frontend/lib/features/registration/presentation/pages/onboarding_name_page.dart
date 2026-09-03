import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
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
/// The date is three boxes rather than a calendar because that is what the
/// reference shows and, on a matrimony profile, what a member actually knows:
/// scrolling a picker back 25 years to reach their own birthday is worse than
/// typing it. [OnboardingNameForm] owns the rule for which typed dates are
/// real ones — 31 February, a year in the future and anyone under 18 are all
/// rejected there, not here.
class OnboardingNamePage extends ConsumerStatefulWidget {
  const OnboardingNamePage({super.key});

  @override
  ConsumerState<OnboardingNamePage> createState() => _OnboardingNamePageState();
}

class _OnboardingNamePageState extends ConsumerState<OnboardingNamePage> {
  late OnboardingNameForm _form;

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _dayCtrl = TextEditingController();
  final _monthCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();

  final _monthFocus = FocusNode();
  final _yearFocus = FocusNode();

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
    _dayCtrl.text = _form.day;
    _monthCtrl.text = _form.month;
    _yearCtrl.text = _form.year;
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _dayCtrl.dispose();
    _monthCtrl.dispose();
    _yearCtrl.dispose();
    _monthFocus.dispose();
    _yearFocus.dispose();
    super.dispose();
  }

  String _fieldLabel(AppLocalizations l10n, OnboardingNameField field) =>
      switch (field) {
        OnboardingNameField.firstName => l10n.registrationFirstNameLabel,
        OnboardingNameField.lastName => l10n.registrationLastNameLabel,
        OnboardingNameField.dob => l10n.registrationDobLabel,
      };

  /// The inline line under the date row. Only ever shown for a date the
  /// member has finished typing and that is genuinely wrong — a half-entered
  /// `05 / 02 / 20` is not an error, it is someone still typing.
  String? _dateErrorText(AppLocalizations l10n) => switch (_form.dateError) {
        OnboardingNameDateError.invalid => l10n.onboardingNameDobInvalid,
        OnboardingNameDateError.tooYoung => l10n.onboardingNameDobTooYoung,
        OnboardingNameDateError.tooOld => l10n.onboardingNameDobTooOld,
        null => null,
      };

  /// Moves to the next box once a part can hold no more digits, so the date
  /// is typed straight through instead of tapped between three fields.
  void _advance(String value, int width, FocusNode? next) {
    if (value.length >= width && next != null) next.requestFocus();
  }

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
          dayController: _dayCtrl,
          monthController: _monthCtrl,
          yearController: _yearCtrl,
          monthFocus: _monthFocus,
          yearFocus: _yearFocus,
          errorText: _dateErrorText(l10n),
          onDayChanged: (v) {
            setState(() => _form = _form.copyWith(day: v));
            _advance(v, 2, _monthFocus);
          },
          onMonthChanged: (v) {
            setState(() => _form = _form.copyWith(month: v));
            _advance(v, 2, _yearFocus);
          },
          onYearChanged: (v) => setState(() => _form = _form.copyWith(year: v)),
        ),
      ],
    );
  }
}

/// "Date of birth" over three compact boxes on one row — the reference's
/// layout, built from the same [NmTextField] the names above it use so the
/// input styling is the theme's and not this screen's.
class _DateOfBirthSection extends StatelessWidget {
  const _DateOfBirthSection({
    required this.dayController,
    required this.monthController,
    required this.yearController,
    required this.monthFocus,
    required this.yearFocus,
    required this.errorText,
    required this.onDayChanged,
    required this.onMonthChanged,
    required this.onYearChanged,
  });

  final TextEditingController dayController;
  final TextEditingController monthController;
  final TextEditingController yearController;
  final FocusNode monthFocus;
  final FocusNode yearFocus;
  final String? errorText;
  final ValueChanged<String> onDayChanged;
  final ValueChanged<String> onMonthChanged;
  final ValueChanged<String> onYearChanged;

  /// Wide enough for four digits and their padding, narrow enough that the
  /// row reads as three small boxes rather than three stretched fields.
  static const double _rowMaxWidth = 320;

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
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _rowMaxWidth),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _DatePart(
                  label: l10n.onboardingNameDobDay,
                  controller: dayController,
                  maxLength: 2,
                  onChanged: onDayChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 3,
                child: _DatePart(
                  label: l10n.onboardingNameDobMonth,
                  controller: monthController,
                  maxLength: 2,
                  focusNode: monthFocus,
                  onChanged: onMonthChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 4,
                child: _DatePart(
                  label: l10n.onboardingNameDobYear,
                  controller: yearController,
                  maxLength: 4,
                  focusNode: yearFocus,
                  textInputAction: TextInputAction.done,
                  onChanged: onYearChanged,
                ),
              ),
            ],
          ),
        ),
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

/// One of the three date boxes. Digits only, capped at its own width, so a
/// month can never be typed as `022` and the parse in [OnboardingNameForm]
/// only ever has to reject dates a calendar disagrees with.
class _DatePart extends StatelessWidget {
  const _DatePart({
    required this.label,
    required this.controller,
    required this.maxLength,
    required this.onChanged,
    this.focusNode,
    this.textInputAction = TextInputAction.next,
  });

  final String label;
  final TextEditingController controller;
  final int maxLength;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    return NmTextField(
      label: label,
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      textAlign: TextAlign.center,
      maxLength: maxLength,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: onChanged,
    );
  }
}
