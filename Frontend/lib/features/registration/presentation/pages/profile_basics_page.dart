import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/profile_options.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/onboarding_forms.dart';
import '../providers/registration_provider.dart';
import '../widgets/onboarding_scaffold.dart';

/// Step 4 — "Now let's build your Profile": name, gender, date of birth,
/// State and City.
///
/// Name, gender and date of birth are asked here because `first_name`,
/// `last_name`, `gender` and `dob` are NOT NULL on `user_profiles`. Onboarding
/// never collected them, so the backend could not write the profile row and a
/// member who finished onboarding got a 404 from `GET /profiles/me` forever —
/// no profile screen, and invisible to Discover. See [ProfileBasicsForm].
///
/// Sub-community is deliberately not asked. It is not required to get a
/// member into the app, and `ReligionDetails.subCaste` stays on the draft for
/// Edit Profile to fill in later — onboarding asks only what the gate in
/// [PostAuthDestination] tests, so a member can never be bounced back to a
/// step for a field this screen never collected.
class ProfileBasicsPage extends ConsumerStatefulWidget {
  const ProfileBasicsPage({super.key});

  @override
  ConsumerState<ProfileBasicsPage> createState() => _ProfileBasicsPageState();
}

class _ProfileBasicsPageState extends ConsumerState<ProfileBasicsPage> {
  ProfileBasicsForm _form = const ProfileBasicsForm();

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Restored verbatim, NOT filtered through OnboardingScaffold.restore.
    // The state/city lists are a curated subset, and real profiles hold
    // answers outside it, so filtering blanked a stored answer and the next
    // save overwrote it. The dropdowns below widen their options to include
    // whatever was stored — see OnboardingScaffold.optionsWith.
    final draft = ref.read(registrationProvider);
    final location = draft.locationDetails;
    final basic = draft.basicDetails;
    _firstNameCtrl.text = basic.firstName;
    _lastNameCtrl.text = basic.lastName;
    _form = ProfileBasicsForm(
      firstName: basic.firstName,
      lastName: basic.lastName,
      gender: basic.gender,
      dob: basic.dob,
      state: location.state,
      city: location.city,
    );
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  String _fieldLabel(AppLocalizations l10n, ProfileBasicsField field) =>
      switch (field) {
        ProfileBasicsField.firstName => l10n.registrationFirstNameLabel,
        ProfileBasicsField.lastName => l10n.registrationLastNameLabel,
        ProfileBasicsField.gender => l10n.registrationGenderLabel,
        ProfileBasicsField.dob => l10n.registrationDobLabel,
        ProfileBasicsField.state => l10n.registrationStateLabel,
        ProfileBasicsField.city => l10n.registrationCityLabel,
      };

  /// Localized display label for a stored gender value (value stays English,
  /// exactly as the wizard's Basic Info step stores it — `BasicDetails.toJson`
  /// is what maps it to the API's MALE / FEMALE).
  String _genderLabel(AppLocalizations l10n, String value) => switch (value) {
        'Male' => l10n.genderMale,
        'Female' => l10n.genderFemale,
        _ => value,
      };

  /// Same bounds as the wizard's picker: 18 is the floor for a matrimony
  /// profile, so the calendar cannot offer a younger date at all.
  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _form.dob ?? DateTime(now.year - 25),
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year - 18),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppColors.primary,
                onPrimary: Colors.white,
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _form = _form.copyWith(dob: picked));
  }

  /// Changing state re-scopes the city list. The current answer is cleared
  /// only when the new list no longer offers it, so correcting a typo'd
  /// state does not silently discard a city that is still valid.
  void _onStateChanged(String state) {
    // Re-picking the state already selected changes nothing, so it must not
    // cost the member their city. That matters now that a stored city outside
    // the curated list survives rehydration: someone who saved "Bengaluru"
    // and re-opened the step would lose it simply by tapping their own state,
    // because the list for Karnataka offers "Bangalore" and not "Bengaluru".
    if (state == _form.state) return;

    setState(() {
      final stillValid = ProfileOptions.citiesFor(state).contains(_form.city);
      _form = _form.copyWith(state: state, city: stillValid ? _form.city : '');
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dob = _form.dob;

    return OnboardingStepScaffold(
      headline: l10n.profileBasicsHeadline,
      crestIcon: Icons.place_rounded,
      backRoute: RouteNames.onboardingContact,
      nextRoute: RouteNames.onboardingMarital,
      isComplete: _form.isComplete,
      validationNames:
          _form.missingFields.map((f) => _fieldLabel(l10n, f)).toList(),
      onSave: () =>
          ref.read(registrationProvider.notifier).applyProfileBasics(_form),
      fields: [
        NmTextField(
          label: l10n.registrationFirstNameLabel,
          hint: l10n.registrationFirstNameHint,
          controller: _firstNameCtrl,
          onChanged: (v) => setState(() => _form = _form.copyWith(firstName: v)),
        ),
        NmTextField(
          label: l10n.registrationLastNameLabel,
          hint: l10n.registrationLastNameHint,
          controller: _lastNameCtrl,
          onChanged: (v) => setState(() => _form = _form.copyWith(lastName: v)),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.registrationGenderLabel,
                style: AppTypography.labelLarge),
            const SizedBox(height: 8),
            Row(
              // Values stay English (stored/emitted); only the label is
              // localized.
              children: ['Male', 'Female'].map((g) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Center(child: Text(_genderLabel(l10n, g))),
                      selected: _form.gender == g,
                      selectedColor: AppColors.primarySurface,
                      onSelected: (_) =>
                          setState(() => _form = _form.copyWith(gender: g)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        GestureDetector(
          onTap: _pickDob,
          child: AbsorbPointer(
            child: NmTextField(
              label: l10n.registrationDobLabel,
              hint: l10n.registrationDobHint,
              readOnly: true,
              controller: TextEditingController(
                text: dob != null
                    ? '${dob.day.toString().padLeft(2, '0')} / '
                        '${dob.month.toString().padLeft(2, '0')} / ${dob.year}'
                    : '',
              ),
              suffix: const Icon(Icons.calendar_today_rounded, size: 20),
            ),
          ),
        ),
        OnboardingDropdownField(
          label: l10n.registrationStateLabel,
          hint: l10n.profileBasicsStateHint,
          value: _form.state,
          options: OnboardingScaffold.optionsWith(
            ProfileOptions.states,
            _form.state,
          ),
          isRequired: true,
          onChanged: (v) => _onStateChanged(v ?? ''),
        ),
        OnboardingDropdownField(
          label: l10n.registrationCityLabel,
          hint: l10n.profileBasicsCityHint,
          value: _form.city,
          options: OnboardingScaffold.optionsWith(
            ProfileOptions.citiesFor(_form.state),
            _form.city,
          ),
          isRequired: true,
          onChanged: (v) =>
              setState(() => _form = _form.copyWith(city: v ?? '')),
        ),
      ],
    );
  }
}
