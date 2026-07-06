import 'package:flutter/material.dart';

import 'app_text_field.dart';

/// Reusable read-only text input triggering date picker modal.
class NmDatePickerField extends StatelessWidget {
  final String? value;
  final String label;
  final VoidCallback onTap;

  const NmDatePickerField({
    super.key,
    required this.value,
    this.label = 'Date of Birth',
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(text: value);
    return NmTextField(
      controller: controller,
      label: label,
      hint: 'DD / MM / YYYY',
      readOnly: true,
      onTap: onTap,
      suffix: const Icon(Icons.calendar_today_rounded, size: 20),
    );
  }
}
