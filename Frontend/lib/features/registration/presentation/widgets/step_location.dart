import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
import 'other_option_field.dart';
import 'registration_helper_tip.dart';

/// Step 4 — Location Details
class StepLocation extends StatefulWidget {
  final LocationDetails details;
  final void Function(LocationDetails) onChanged;

  const StepLocation({super.key, required this.details, required this.onChanged});

  @override
  State<StepLocation> createState() => _StepLocationState();
}

class _StepLocationState extends State<StepLocation> {
  late String _country;
  late String _state;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _areaCtrl;
  late final TextEditingController _pinCtrl;
  late final TextEditingController _nativePlaceCtrl;

  static const _countries = ['India', 'United States', 'United Kingdom', 'Singapore', 'UAE', 'Malaysia', 'Australia', 'Canada', 'Other'];
  static const _states = ['Tamil Nadu', 'Karnataka', 'Kerala', 'Andhra Pradesh', 'Telangana', 'Maharashtra', 'Delhi', 'Gujarat', 'West Bengal', 'Rajasthan', 'UP', 'Other'];

  @override
  void initState() {
    super.initState();
    _country = widget.details.country.isEmpty ? 'India' : widget.details.country;
    _state = widget.details.state;
    _cityCtrl = TextEditingController(text: widget.details.city);
    _areaCtrl = TextEditingController(text: widget.details.area);
    _pinCtrl = TextEditingController(text: widget.details.pinCode);
    _nativePlaceCtrl = TextEditingController(text: widget.details.nativePlace);
  }

  @override
  void dispose() {
    _cityCtrl.dispose();
    _areaCtrl.dispose();
    _pinCtrl.dispose();
    _nativePlaceCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(LocationDetails(country: _country, state: _state, city: _cityCtrl.text.trim(), area: _areaCtrl.text.trim(), pinCode: _pinCtrl.text.trim(), nativePlace: _nativePlaceCtrl.text.trim()));
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.registrationWizardLocationHeadline, style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.registrationWizardLocationHook, style: AppTypography.bodyMedium.copyWith(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipLocation),
          const SizedBox(height: 24),
          OtherOptionField(
            title: l10n.registrationCountryLabel,
            options: _countries,
            value: _country,
            labelOf: (v) => _countryLabel(l10n, v),
            onChanged: (v) { setState(() => _country = v); _emit(); },
          ),
          const SizedBox(height: 20),
          OtherOptionField(
            title: l10n.registrationStateLabel,
            options: _states,
            value: _state,
            labelOf: (v) => _stateLabel(l10n, v),
            onChanged: (v) { setState(() => _state = v); _emit(); },
          ),
          const SizedBox(height: 20),
          NmTextField(label: l10n.registrationCityLabel, hint: l10n.registrationCityHint, controller: _cityCtrl, onChanged: (_) => _emit()),
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
