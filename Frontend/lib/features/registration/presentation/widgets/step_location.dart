import 'package:flutter/material.dart';

import '../../../../core/constants/profile_options.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
import 'onboarding_scaffold.dart';
import 'other_option_field.dart';
import 'registration_helper_tip.dart';
import 'step_body.dart';

/// Step 4 — Location Details
class StepLocation extends StatefulWidget {
  final LocationDetails details;
  final void Function(LocationDetails) onChanged;
  /// See [StepBody.scrollable].
  final bool scrollable;

  const StepLocation({
    super.key,
    required this.details,
    required this.onChanged,
    this.scrollable = true,
  });

  @override
  State<StepLocation> createState() => _StepLocationState();
}

class _StepLocationState extends State<StepLocation> {
  late String _country;
  late String _state;
  late String _city;
  late final TextEditingController _areaCtrl;
  late final TextEditingController _pinCtrl;
  late final TextEditingController _nativePlaceCtrl;

  static const _countries = [...ProfileOptions.countries, 'Other'];
  // Shared list plus this step's own "Other" escape — OtherOptionField pairs
  // that chip with a free-text field, so the literal "Other" is never what
  // gets persisted (see OtherOptionField's doc).
  /// Scoped to the chosen country, plus this step's "Other" escape and
  /// whatever is already stored. `optionsWith` is what stops an edit from
  /// discarding a state the curated list does not carry — see its doc for the
  /// silent data loss that caused.
  List<String> get _stateOptions => OnboardingScaffold.optionsWith(
        [...ProfileOptions.statesFor(_country), 'Other'],
        _state,
      );

  List<String> get _cityOptions => OnboardingScaffold.optionsWith(
        [...ProfileOptions.citiesFor(_state), 'Other'],
        _city,
      );

  @override
  void initState() {
    super.initState();
    _country = widget.details.country.isEmpty ? 'India' : widget.details.country;
    _state = widget.details.state;
    _city = widget.details.city;
    _areaCtrl = TextEditingController(text: widget.details.area);
    _pinCtrl = TextEditingController(text: widget.details.pinCode);
    _nativePlaceCtrl = TextEditingController(text: widget.details.nativePlace);
  }

  @override
  void dispose() {
    _areaCtrl.dispose();
    _pinCtrl.dispose();
    _nativePlaceCtrl.dispose();
    super.dispose();
  }

  /// Changing country clears a state the new country does not offer, and the
  /// city with it. A state that is still valid is kept — re-picking the same
  /// country, or one that shares the state, should not cost an answer that
  /// remains true.
  void _onCountryChanged(String country) {
    setState(() {
      _country = country;
      if (!ProfileOptions.isStateInCountry(country, _state)) {
        _state = '';
        _city = '';
      } else if (!ProfileOptions.isCityInState(_state, _city)) {
        _city = '';
      }
    });
    _emit();
  }

  /// Changing state clears a city the new state does not offer.
  void _onStateChanged(String state) {
    setState(() {
      _state = state;
      if (!ProfileOptions.isCityInState(state, _city)) _city = '';
    });
    _emit();
  }

  void _emit() {
    widget.onChanged(LocationDetails(country: _country, state: _state, city: _city, area: _areaCtrl.text.trim(), pinCode: _pinCtrl.text.trim(), nativePlace: _nativePlaceCtrl.text.trim()));
  }

  /// Localized display label for a stored country value (value stays English).
  String _countryLabel(AppLocalizations l10n, String value) => switch (value) {
        'India' => l10n.countryIndia,
        'United States' => l10n.countryUsa,
        'United Kingdom' => l10n.countryUk,
        'Singapore' => l10n.countrySingapore,
        'UAE' => l10n.countryUae,
        'Malaysia' => l10n.countryMalaysia,
        'Australia' => l10n.countryAustralia,
        'Canada' => l10n.countryCanada,
        'Other' => l10n.countryOther,
        _ => value,
      };

  /// Localized display label for a stored state value (value stays English).
  String _stateLabel(AppLocalizations l10n, String value) => switch (value) {
        'Tamil Nadu' => l10n.stateTamilNadu,
        'Karnataka' => l10n.stateKarnataka,
        'Kerala' => l10n.stateKerala,
        'Andhra Pradesh' => l10n.stateAndhraPradesh,
        'Telangana' => l10n.stateTelangana,
        'Maharashtra' => l10n.stateMaharashtra,
        'Delhi' => l10n.stateDelhi,
        'Gujarat' => l10n.stateGujarat,
        'West Bengal' => l10n.stateWestBengal,
        'Rajasthan' => l10n.stateRajasthan,
        'UP' => l10n.stateUp,
        'Other' => l10n.stateOther,
        _ => value,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return StepBody(
      scrollable: widget.scrollable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.registrationWizardLocationHeadline, style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.registrationWizardLocationHook, style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondaryLight)),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipLocation),
          const SizedBox(height: 24),
          OtherOptionField(
            title: l10n.registrationCountryLabel,
            options: _countries,
            value: _country,
            labelOf: (v) => _countryLabel(l10n, v),
            onChanged: _onCountryChanged,
          ),
          const SizedBox(height: 20),
          // Keyed on the country so the dropdown rebuilds its options when the
          // country changes rather than holding a value the new list cannot
          // show.
          OtherOptionField(
            key: ValueKey('state-$_country'),
            title: l10n.registrationStateLabel,
            options: _stateOptions,
            value: _state,
            labelOf: (v) => _stateLabel(l10n, v),
            onChanged: _onStateChanged,
          ),
          const SizedBox(height: 20),
          OtherOptionField(
            key: ValueKey('city-$_state'),
            title: l10n.registrationCityLabel,
            options: _cityOptions,
            value: _city,
            customFieldLabel: l10n.registrationCityLabel,
            customFieldHint: l10n.registrationCityHint,
            onChanged: (v) { setState(() => _city = v); _emit(); },
          ),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationAreaLabel, hint: l10n.registrationAreaHint, controller: _areaCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationPinLabel, hint: l10n.registrationPinHint, controller: _pinCtrl, keyboardType: TextInputType.number, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationNativePlaceLabel, hint: l10n.registrationNativePlaceHint, controller: _nativePlaceCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
