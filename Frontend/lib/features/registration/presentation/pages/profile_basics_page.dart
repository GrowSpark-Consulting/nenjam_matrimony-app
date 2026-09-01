import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/profile_options.dart';
import '../../../../core/router/route_names.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/onboarding_forms.dart';
import '../providers/registration_provider.dart';
import '../widgets/onboarding_scaffold.dart';

/// Step 4 — "Now let's build your Profile": State and City.
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

  @override
  void initState() {
    super.initState();
    final location = ref.read(registrationProvider).locationDetails;
    _form = ProfileBasicsForm(
      state: OnboardingScaffold.restore(location.state, ProfileOptions.states),
      city: OnboardingScaffold.restore(
        location.city,
        ProfileOptions.citiesFor(location.state),
      ),
    );
  }

  String _fieldLabel(AppLocalizations l10n, ProfileBasicsField field) =>
      switch (field) {
        ProfileBasicsField.state => l10n.registrationStateLabel,
        ProfileBasicsField.city => l10n.registrationCityLabel,
      };

  /// Changing state re-scopes the city list. The current answer is cleared
  /// only when the new list no longer offers it, so correcting a typo'd
  /// state does not silently discard a city that is still valid.
  void _onStateChanged(String state) {
    setState(() {
      final stillValid = ProfileOptions.citiesFor(state).contains(_form.city);
      _form = _form.copyWith(state: state, city: stillValid ? _form.city : '');
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

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
        OnboardingDropdownField(
          label: l10n.registrationStateLabel,
          hint: l10n.profileBasicsStateHint,
          value: _form.state,
          options: ProfileOptions.states,
          isRequired: true,
          onChanged: (v) => _onStateChanged(v ?? ''),
        ),
        OnboardingDropdownField(
          label: l10n.registrationCityLabel,
          hint: l10n.profileBasicsCityHint,
          value: _form.city,
          options: ProfileOptions.citiesFor(_form.state),
          isRequired: true,
          onChanged: (v) =>
              setState(() => _form = _form.copyWith(city: v ?? '')),
        ),
      ],
    );
  }
}
