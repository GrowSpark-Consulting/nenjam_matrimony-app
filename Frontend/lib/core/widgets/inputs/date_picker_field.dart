import 'package:flutter/material.dart';

import 'app_text_field.dart';

/// Read-only, fully tappable date input: the field a member taps to open a
/// calendar, showing the date they chose back to them.
///
/// [value] is the already-formatted date rather than a [DateTime], because
/// how a date reads ("23 February 2000") depends on the active locale and is
/// the caller's decision — this widget only has to look like every other
/// field on the screen, which it does by being an [NmTextField].
///
/// Stateful only to own its controller: a controller built inside `build`
/// would be replaced on every frame and never disposed.
class NmDatePickerField extends StatefulWidget {
  /// The chosen date, formatted for display. Null or empty shows [hint].
  final String? value;

  /// Floating label. Null when the screen already titles the field itself —
  /// the onboarding step puts "Date of birth" above it as a section heading
  /// and would otherwise say it twice.
  final String? label;

  /// What the empty field says. Should read as an instruction to tap, not as
  /// a typing format: nothing here is typed.
  final String? hint;

  final VoidCallback onTap;

  const NmDatePickerField({
    super.key,
    required this.value,
    required this.onTap,
    this.label,
    this.hint,
  });

  @override
  State<NmDatePickerField> createState() => _NmDatePickerFieldState();
}

class _NmDatePickerFieldState extends State<NmDatePickerField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value ?? '');

  @override
  void didUpdateWidget(covariant NmDatePickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _controller.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NmTextField(
      controller: _controller,
      label: widget.label,
      hint: widget.hint,
      // Read-only rather than disabled: the field keeps the enabled field's
      // colours and stays tappable across its whole width, including the
      // calendar icon, which is not a button of its own.
      readOnly: true,
      onTap: widget.onTap,
      suffix: const Icon(Icons.calendar_today_rounded, size: 20),
    );
  }
}
