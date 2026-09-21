import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/models/location_models.dart';
import '../providers/location_providers.dart';
import 'location_picker_field.dart';

/// Country → State → City, wired to the backend's master data.
///
/// The cascade rule is the same one the server enforces: a state belongs to a
/// country and a city to a state, so changing a parent clears its children
/// rather than leaving a combination the server would reject. That rule lives
/// in [SelectedLocation] so this widget and the server cannot drift apart.
class LocationCascade extends ConsumerWidget {
  const LocationCascade({
    super.key,
    required this.value,
    required this.onChanged,
    required this.countryLabel,
    required this.stateLabel,
    required this.cityLabel,
    required this.countryHint,
    required this.stateHint,
    required this.cityHint,
    this.legacyCountry = '',
    this.legacyState = '',
    this.legacyCity = '',
    this.spacing = 20,
  });

  final SelectedLocation value;
  final ValueChanged<SelectedLocation> onChanged;

  final String countryLabel;
  final String stateLabel;
  final String cityLabel;
  final String countryHint;
  final String stateHint;
  final String cityHint;

  /// Free text a member gave before the master data existed, with no code
  /// behind it. Displayed in place of the hint so an older profile does not
  /// look like the app lost the answer; replaced the moment they pick a real
  /// option. Empty when there is none.
  final String legacyCountry;
  final String legacyState;
  final String legacyCity;

  final double spacing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final countryCode = value.country?.code ?? '';
    final stateCode = value.state?.code ?? '';

    final countries = ref.watch(countriesProvider);
    // Watching with an empty key returns an empty list rather than firing a
    // request — see the providers — so no dependent level fetches before its
    // parent is chosen.
    final states = ref.watch(statesProvider(countryCode));
    final cities = ref.watch(citiesProvider(stateCode));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LocationPickerField(
          label: countryLabel,
          hint: countryHint,
          legacyValue: legacyCountry,
          options: countries,
          optionsProvider: countriesProvider,
          value: value.country,
          onChanged: (country) => onChanged(value.withCountry(country)),
          onRetry: () => ref.invalidate(countriesProvider),
        ),
        SizedBox(height: spacing),
        LocationPickerField(
          label: stateLabel,
          hint: stateHint,
          legacyValue: legacyState,
          options: states,
          optionsProvider: statesProvider(countryCode),
          value: value.state,
          // A legacy country counts as "the parent is answered": the member
          // must be able to open the state list and correct it in place,
          // rather than being forced to re-pick the country first.
          enabled: value.country != null || legacyCountry.isNotEmpty,
          disabledHint: countryHint,
          onChanged: (state) => onChanged(value.withState(state)),
          onRetry: () => ref.invalidate(statesProvider(countryCode)),
          loadingMessage: l10n.loadingStates,
          emptyMessage: l10n.noStatesAvailable,
          errorMessage: l10n.couldntLoadStates,
        ),
        SizedBox(height: spacing),
        LocationPickerField(
          label: cityLabel,
          hint: cityHint,
          legacyValue: legacyCity,
          options: cities,
          optionsProvider: citiesProvider(stateCode),
          value: value.city,
          enabled: value.state != null || legacyState.isNotEmpty,
          disabledHint: stateHint,
          onChanged: (city) => onChanged(value.withCity(city)),
          onRetry: () => ref.invalidate(citiesProvider(stateCode)),
          loadingMessage: l10n.findingCitiesIn(
            value.state?.label ?? legacyState,
          ),
          emptyMessage: l10n.noCitiesFoundForState,
          errorMessage: l10n.couldntLoadCities,
        ),
      ],
    );
  }
}
