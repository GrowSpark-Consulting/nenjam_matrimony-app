import 'package:flutter/material.dart';

import 'app_text_field.dart';

/// Reusable Bio text area input with character limit counter.
class NmBioTextArea extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final int maxLength;
  final void Function(String)? onChanged;

  const NmBioTextArea({
    super.key,
    this.controller,
    this.label = 'About Me',
    this.hint = 'Describe your values, hobbies, family background, and partner preferences...',
    this.maxLength = 500,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return NmTextField(
      controller: controller,
      label: label,
      hint: hint,
      maxLines: 5,
      maxLength: maxLength,
      onChanged: onChanged,
    );
  }
}
