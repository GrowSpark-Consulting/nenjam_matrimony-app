import 'package:flutter/material.dart';

import 'app_text_field.dart';

/// Password input field with toggleable obscuration.
class NmPasswordField extends StatefulWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  const NmPasswordField({
    super.key,
    this.controller,
    this.label = 'Password',
    this.hint = 'Enter your secret password',
    this.validator,
    this.onChanged,
  });

  @override
  State<NmPasswordField> createState() => _NmPasswordFieldState();
}

class _NmPasswordFieldState extends State<NmPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return NmTextField(
      controller: widget.controller,
      label: widget.label,
      hint: widget.hint,
      obscureText: _obscure,
      keyboardType: TextInputType.visiblePassword,
      validator: widget.validator,
      onChanged: widget.onChanged,
      prefixIcon: Icons.lock_outline_rounded,
      suffix: IconButton(
        icon: Icon(
          _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 20,
        ),
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    );
  }
}
