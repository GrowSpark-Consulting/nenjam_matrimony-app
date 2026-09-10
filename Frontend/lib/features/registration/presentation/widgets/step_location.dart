import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../features/location/domain/models/location_models.dart';
import '../../../../features/location/presentation/widgets/location_cascade.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
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
  /// Code-backed selections made from the master data. Null at each level
  /// until the member picks from the real list.
  SelectedLocation _location = const SelectedLocation();

  /// What the draft already held as free text, with no code behind it.
  ///
  /// A draft saved before the master data existed — or by a member who used
  /// the old "Other" escape — has labels only. Those are deliberately not
  /// promoted into [_location]: guessing which city "chennai" meant is
  /// exactly what the server refuses to do, so the member re-picks from the
  /// real list and the answer becomes unambiguous.
  ///
  /// But they are NOT discarded either. They are shown in the field and
  /// re-emitted verbatim until the member replaces them, so that editing an
  /// unrelated field on this step cannot quietly wipe a location someone
  /// already gave us. That silent loss is the whole reason this is here.
  String _legacyCountry = '';
  String _legacyState = '';
  String _legacyCity = '';

  late final TextEditingController _areaCtrl;
  late final TextEditingController _pinCtrl;
  late final TextEditingController _nativePlaceCtrl;

  @override
  void initState() {
    super.initState();
    final details = widget.details;

    // A level with a code is a real selection; a level with only text is
    // legacy. The two are tracked separately, never conflated.
    _location = SelectedLocation(
      country: details.countryCode.isEmpty
          ? null
          : LocationOption(code: details.countryCode, label: details.country),
      state: details.stateCode.isEmpty
          ? null
          : LocationOption(
              code: details.stateCode,
              label: details.state,
              parentCode: details.countryCode,
            ),
      city: details.cityCode.isEmpty
          ? null
          : LocationOption(
              code: details.cityCode,
              label: details.city,
              parentCode: details.stateCode,
            ),
    );
    _legacyCountry = details.countryCode.isEmpty ? details.country : '';
    _legacyState = details.stateCode.isEmpty ? details.state : '';
    _legacyCity = details.cityCode.isEmpty ? details.city : '';

    _areaCtrl = TextEditingController(text: details.area);
    _pinCtrl = TextEditingController(text: details.pinCode);
    _nativePlaceCtrl = TextEditingController(text: details.nativePlace);
  }

  @override
  void dispose() {
    _areaCtrl.dispose();
    _pinCtrl.dispose();
    _nativePlaceCtrl.dispose();
    super.dispose();
  }

  void _onLocationChanged(SelectedLocation next) {
    setState(() {
      // Picking a real country supersedes the legacy text at that level, and
      // the cascade rule applies to legacy children too: a leftover "Panaji"
      // must not survive the member choosing Canada.
      if (next.country?.code != _location.country?.code) {
        _legacyCountry = '';
        _legacyState = '';
        _legacyCity = '';
      } else if (next.state?.code != _location.state?.code) {
        _legacyState = '';
        _legacyCity = '';
      } else if (next.city?.code != _location.city?.code) {
        _legacyCity = '';
      }
      _location = next;
    });
    _emit();
  }

  void _emit() {
    widget.onChanged(LocationDetails(
      // Both forms travel together: the label is what a member reads back on
      // their profile, the code is what the server validates and stores.
      // Where only legacy text exists the code is empty, which the backend
      // reads as "no structured location" and falls back to the text.
      country: _location.country?.label ?? _legacyCountry,
      state: _location.state?.label ?? _legacyState,
      city: _location.city?.label ?? _legacyCity,
      countryCode: _location.country?.code ?? '',
      stateCode: _location.state?.code ?? '',
      cityCode: _location.city?.code ?? '',
      area: _areaCtrl.text.trim(),
      pinCode: _pinCtrl.text.trim(),
      nativePlace: _nativePlaceCtrl.text.trim(),
    ));
  }

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
          LocationCascade(
            value: _location,
            onChanged: _onLocationChanged,
            countryLabel: l10n.registrationCountryLabel,
            stateLabel: l10n.registrationStateLabel,
            cityLabel: l10n.registrationCityLabel,
            countryHint: l10n.registrationCountryHint,
            stateHint: l10n.registrationStateHint,
            cityHint: l10n.registrationCityHint,
            // Shown in place of the hint so a member editing an older profile
            // sees the answer they gave, not an empty field that looks like
            // the app lost it.
            legacyCountry: _legacyCountry,
            legacyState: _legacyState,
            legacyCity: _legacyCity,
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
