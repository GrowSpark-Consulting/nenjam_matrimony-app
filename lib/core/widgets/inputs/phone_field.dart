import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import 'app_text_field.dart';

/// Reusable phone number field with country picker prefix.
class NmPhoneNumberField extends StatelessWidget {
  final TextEditingController? controller;
  final String countryCode;
  final VoidCallback? onCountryTap;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  const NmPhoneNumberField({
    super.key,
    this.controller,
    this.countryCode = '+91',
    this.onCountryTap,
    this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onCountryTap,
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
                const Text('🇮🇳', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 6),
                Text(countryCode, style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                const Icon(Icons.arrow_drop_down_rounded, color: AppColors.textSecondaryLight),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: NmTextField(
            controller: controller,
            hint: '98765 43210',
            keyboardType: TextInputType.phone,
            validator: validator,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
