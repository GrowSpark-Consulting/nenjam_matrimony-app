import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../location/domain/models/location_models.dart';
import '../../../location/presentation/providers/location_providers.dart';
import '../../domain/models/onboarding_forms.dart';
import '../providers/registration_provider.dart';
import '../widgets/onboarding_location_field.dart';
import '../widgets/onboarding_scaffold.dart';

/// Step 5 — "Now let's build your Profile": State, City and Sub-community.
///
/// Gender moved to [CreateProfileForPage], which asks it first. Caste and
/// mother tongue are not collected in onboarding at all — see
/// [ProfileBasicsForm] for what that means for the profile write, which is
/// the one consequence worth knowing before adding a field back.
///
/// Sub-community stays optional: `sub_caste` is nullable and the gate in
/// [PostAuthDestination] does not test it, so requiring it here would block a
/// member on a field the router will happily wave them past.
class ProfileBasicsPage extends ConsumerStatefulWidget {
  const ProfileBasicsPage({super.key});

  @override
  ConsumerState<ProfileBasicsPage> createState() => _ProfileBasicsPageState();
}

class _ProfileBasicsPageState extends ConsumerState<ProfileBasicsPage> {
  ProfileBasicsForm _form = const ProfileBasicsForm();

  final _subCommunityCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Restored verbatim. The state and city lists now come from the backend's
    // master data, which is not loaded when this runs, so the stored label is
    // matched against the API's own list once it arrives (see
    // [resolveStoredLocation]) and shown as the member's answer meanwhile.
    // Nothing is filtered away up front, which is what used to blank a stored
    // answer and let the next save overwrite it.
    final draft = ref.read(registrationProvider);
    final location = draft.locationDetails;
    _subCommunityCtrl.text = draft.religionDetails.subCaste;
    _form = ProfileBasicsForm(
      state: location.state,
      city: location.city,
      stateCode: location.stateCode,
      cityCode: location.cityCode,
      // Verbatim: free text, so there is no list to filter against.
      subCommunity: draft.religionDetails.subCaste,
    );
  }

  @override
  void dispose() {
    _subCommunityCtrl.dispose();
    super.dispose();
  }

  String _fieldLabel(AppLocalizations l10n, ProfileBasicsField field) =>
      switch (field) {
        ProfileBasicsField.state => l10n.registrationStateLabel,
        ProfileBasicsField.city => l10n.registrationCityLabel,
      };

  /// Changing the state clears the city.
  ///
  /// Unconditionally, unlike the old curated-list behaviour that kept a city
  /// still present in the new list. A city code is scoped to its state
  /// (`IN-GJ-BHAVNAGAR`), so a city carried across a state change would be a
  /// combination the server rejects — and re-picking is one tap, whereas a
  /// silently invalid answer surfaces as a failed save much later.
  ///
  /// Re-picking the state already selected is still a no-op, so tapping your
  /// own state never costs you your city.
  void _onStateChanged(LocationOption? option) {
    final code = option?.code ?? '';
    if (code == _form.stateCode && (option?.label ?? '') == _form.state) return;

    setState(() {
      _form = _form.copyWith(
        state: option?.label ?? '',
        stateCode: code,
        city: '',
        cityCode: '',
      );
    });
  }

  void _onCityChanged(LocationOption? option) {
    setState(() {
      _form = _form.copyWith(
        city: option?.label ?? '',
        cityCode: option?.code ?? '',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // The country was chosen two steps earlier, on the Religion step. It is
    // read from the draft rather than passed along, so resuming mid-flow (or
    // arriving via PostAuthDestination's rehydrate) works identically to
    // walking the steps in order.
    final storedCountry = ref.watch(
      registrationProvider.select((d) => d.locationDetails),
    );

    // A draft written before the master data existed holds a country label and
    // no code, and the State field below would be permanently disabled for
    // those members — a dead end reachable by resuming straight onto this
    // step, where re-picking the country is not even offered. So the label is
    // resolved against the country list.
    //
    // ONLY in that case, though. Watching `countriesProvider` unconditionally
    // fired a country request on every open of this step to answer a question
    // the draft had already answered — a wasted round trip competing with the
    // states request for the same connection, on the step where the member is
    // waiting. The common path (country chosen two steps back, code present)
    // now reads the code straight off the draft and fetches nothing.
    final countryCode = storedCountry.countryCode.isNotEmpty
        ? storedCountry.countryCode
        : resolveStoredLocation(
              ref.watch(countriesProvider),
              '',
              storedCountry.country,
            )?.code ??
            '';

    final states = ref.watch(statesProvider(countryCode));
    final stateOption =
        resolveStoredLocation(states, _form.stateCode, _form.state);

    // Cities are scoped by the RESOLVED state code: a draft whose state was
    // stored as a label only still lists the right cities once that label is
    // matched, rather than showing an empty city list until the member
    // re-picks a state their screen already shows.
    final stateCode = stateOption?.code ?? '';
    final cities = ref.watch(citiesProvider(stateCode));
    final cityOption =
        resolveStoredLocation(cities, _form.cityCode, _form.city);

    return OnboardingStepScaffold(
      headline: l10n.profileBasicsHeadline,
      crestIcon: Icons.place_rounded,
      backRoute: RouteNames.onboardingContact,
      nextRoute: RouteNames.onboardingMarital,
      isComplete: _form.isComplete,
      validationNames:
          _form.missingFields.map((f) => _fieldLabel(l10n, f)).toList(),
      // Saved with the RESOLVED state and city so a draft that carried only
      // labels gains its codes here, the same way the country does on the
      // Religion step.
      onSave: () => ref.read(registrationProvider.notifier).applyProfileBasics(
            _form.copyWith(
              state: stateOption?.label ?? _form.state,
              stateCode: stateOption?.code ?? _form.stateCode,
              city: cityOption?.label ?? _form.city,
              cityCode: cityOption?.code ?? _form.cityCode,
            ),
          ),
      fields: [
        OnboardingLocationField(
          label: l10n.registrationStateLabel,
          hint: l10n.profileBasicsStateHint,
          options: states,
          optionsProvider: statesProvider(countryCode),
          value: stateOption,
          legacyValue: stateOption == null ? _form.state : '',
          // A country stored as free text still lets the member open the
          // state list and answer in place, rather than sending them back a
          // step to re-pick a country their screen already shows.
          enabled: countryCode.isNotEmpty,
          disabledHint: l10n.onboardingLivingInHint,
          isRequired: true,
          onRetry: () => ref.invalidate(statesProvider(countryCode)),
          onChanged: _onStateChanged,
          loadingMessage: l10n.loadingStates,
          emptyMessage: l10n.noStatesAvailable,
          errorMessage: l10n.couldntLoadStates,
        ),
        OnboardingLocationField(
          label: l10n.registrationCityLabel,
          hint: l10n.profileBasicsCityHint,
          options: cities,
          optionsProvider: citiesProvider(stateCode),
          value: cityOption,
          legacyValue: cityOption == null ? _form.city : '',
          enabled: stateCode.isNotEmpty,
          disabledHint: l10n.profileBasicsStateHint,
          isRequired: true,
          onRetry: () => ref.invalidate(citiesProvider(stateCode)),
          onChanged: _onCityChanged,
          // Named after the state the member just picked, so switching
          // states shows "Finding cities in Gujarat..." rather than a
          // caption that could belong to any field.
          loadingMessage: l10n.findingCitiesIn(
            stateOption?.label ?? _form.state,
          ),
          emptyMessage: l10n.noCitiesFoundForState,
          errorMessage: l10n.couldntLoadCities,
        ),
        // Free text, like the wizard's own sub-caste field: there is no
        // authoritative list in this app, and inventing one is not an option.
        // Optional — see the class doc — so it carries no asterisk and no
        // entry in [missingFields].
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.profileBasicsSubCommunityLabel,
              style: AppTypography.titleMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            NmTextField(
              label: l10n.registrationSubCasteLabel,
              hint: l10n.profileBasicsSubCommunityHint,
              controller: _subCommunityCtrl,
              textCapitalization: TextCapitalization.words,
              onChanged: (v) =>
                  setState(() => _form = _form.copyWith(subCommunity: v)),
            ),
          ],
        ),
      ],
    );
  }
}
