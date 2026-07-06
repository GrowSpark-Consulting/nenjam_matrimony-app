import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../domain/models/profile_draft.dart';

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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Location', style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Where do you live?', style: AppTypography.bodyMedium.copyWith(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
          const SizedBox(height: 24),
          Text('Country', style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _countries.map((c) { final sel = _country == c; return ChoiceChip(label: Text(c), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { setState(() => _country = c); _emit(); }); }).toList()),
          const SizedBox(height: 20),
          Text('State', style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _states.map((s) { final sel = _state == s; return ChoiceChip(label: Text(s), selected: sel, selectedColor: AppColors.primarySurface, onSelected: (_) { setState(() => _state = s); _emit(); }); }).toList()),
          const SizedBox(height: 20),
          NmTextField(label: 'City', hint: 'e.g., Chennai', controller: _cityCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: 'Area (Optional)', hint: 'e.g., T. Nagar', controller: _areaCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: 'PIN Code (Optional)', hint: '600017', controller: _pinCtrl, keyboardType: TextInputType.number, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: 'Native Place (Optional)', hint: 'e.g., Thanjavur', controller: _nativePlaceCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
