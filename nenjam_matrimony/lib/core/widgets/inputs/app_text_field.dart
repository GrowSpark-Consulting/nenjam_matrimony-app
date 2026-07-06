import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Styled text field with label, prefix/suffix icons, and validation.
class NmTextField extends StatelessWidget {
  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final bool obscureText;
  final bool readOnly;
  final bool enabled;
  final int maxLines;
  final int? maxLength;
  final IconData? prefixIcon;
  final Widget? suffix;
  final Widget? prefix;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final AutovalidateMode autovalidateMode;

  const NmTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.validator,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.obscureText = false,
    this.readOnly = false,
    this.enabled = true,
    this.maxLines = 1,
    this.maxLength,
    this.prefixIcon,
    this.suffix,
    this.prefix,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.inputFormatters,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      readOnly: readOnly,
      enabled: enabled,
      maxLines: maxLines,
      maxLength: maxLength,
      focusNode: focusNode,
      onTap: onTap,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      inputFormatters: inputFormatters,
      autovalidateMode: autovalidateMode,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : prefix,
        suffixIcon: suffix,
        counterText: '',
      ),
    );
  }
}
