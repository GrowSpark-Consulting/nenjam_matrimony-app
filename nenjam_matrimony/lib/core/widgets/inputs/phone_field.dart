import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import 'app_text_field.dart';

/// Country model for the phone field country picker.
class CountryInfo {
  final String flag;
  final String code;
  final String name;
  const CountryInfo(this.flag, this.code, this.name);
}

/// Common country codes list.
const kCountryCodes = [
  CountryInfo('🇮🇳', '+91', 'India'),
  CountryInfo('🇺🇸', '+1', 'United States'),
  CountryInfo('🇬🇧', '+44', 'United Kingdom'),
  CountryInfo('🇦🇪', '+971', 'United Arab Emirates'),
  CountryInfo('🇨🇦', '+1', 'Canada'),
  CountryInfo('🇦🇺', '+61', 'Australia'),
  CountryInfo('🇸🇬', '+65', 'Singapore'),
  CountryInfo('🇲🇾', '+60', 'Malaysia'),
  CountryInfo('🇱🇰', '+94', 'Sri Lanka'),
  CountryInfo('🇸🇦', '+966', 'Saudi Arabia'),
  CountryInfo('🇶🇦', '+974', 'Qatar'),
  CountryInfo('🇰🇼', '+965', 'Kuwait'),
  CountryInfo('🇴🇲', '+968', 'Oman'),
  CountryInfo('🇧🇭', '+973', 'Bahrain'),
  CountryInfo('🇩🇪', '+49', 'Germany'),
  CountryInfo('🇫🇷', '+33', 'France'),
  CountryInfo('🇳🇿', '+64', 'New Zealand'),
  CountryInfo('🇿🇦', '+27', 'South Africa'),
];

/// Shows a searchable country picker bottom sheet.
void showCountryPickerSheet(BuildContext context, {required ValueChanged<CountryInfo> onSelect}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  showModalBottomSheet(
    context: context,
    backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Select Country Code',
              style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: kCountryCodes.length,
                itemBuilder: (context, index) {
                  final c = kCountryCodes[index];
                  return ListTile(
                    leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                    title: Text(c.name, style: AppTypography.bodyLarge),
                    trailing: Text(
                      c.code,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentGold,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      onSelect(c);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Reusable phone number field with country picker prefix.
class NmPhoneNumberField extends StatefulWidget {
  final TextEditingController? controller;
  final String initialCountryCode;
  final ValueChanged<CountryInfo>? onCountryChanged;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  const NmPhoneNumberField({
    super.key,
    this.controller,
    this.initialCountryCode = '+91',
    this.onCountryChanged,
    this.validator,
    this.onChanged,
  });

  @override
  State<NmPhoneNumberField> createState() => _NmPhoneNumberFieldState();
}

class _NmPhoneNumberFieldState extends State<NmPhoneNumberField> {
  late CountryInfo _selectedCountry;

  @override
  void initState() {
    super.initState();
    _selectedCountry = kCountryCodes.firstWhere(
      (c) => c.code == widget.initialCountryCode,
      orElse: () => kCountryCodes.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => showCountryPickerSheet(context, onSelect: (c) {
            setState(() => _selectedCountry = c);
            widget.onCountryChanged?.call(c);
          }),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.borderLight),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_selectedCountry.flag, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 6),
                Text(_selectedCountry.code, style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                const Icon(Icons.arrow_drop_down_rounded, color: AppColors.textSecondaryLight),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: NmTextField(
            controller: widget.controller,
            hint: '98765 43210',
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            validator: widget.validator,
            onChanged: widget.onChanged,
          ),
        ),
      ],
    );
  }
}
