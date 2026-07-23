import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';

/// A chip-selection group with an inline text field that appears whenever
/// "Other" is selected — reused across every chip group in the wizard that
/// offers an "Other" option (Religion, Country, State, Qualification,
/// Occupation, Disability, Annual Income).
///
/// The emitted value is NEVER the literal string `"Other"` — selecting
/// "Other" with no custom text yet emits `''` (so required-field validation
/// correctly treats it as incomplete, exactly like any other empty field),
/// and once the user types something, the typed text itself becomes the
/// value. Which chip *looks* selected while the value is still `''` is
/// tracked as local UI state ([_otherSelected]) since the persisted value
/// alone can't distinguish "nothing chosen yet" from "chose Other, still
/// typing". Re-opening a step with an already-custom value correctly shows
/// "Other" selected with the field pre-filled (see [_isCustom]).
class OtherOptionField extends StatefulWidget {
  final String title;
  final List<String> options;
  final String value;
  final void Function(String) onChanged;
  final String Function(String)? labelOf;
  final String otherOptionValue;

  /// Overrides for the custom-value text field — defaults to the generic
  /// "Please specify" copy. Annual Income uses these to prompt for a
  /// specific numeric figure instead.
  final String? customFieldLabel;
  final String? customFieldHint;
  final TextInputType customFieldKeyboardType;
  final List<TextInputFormatter>? customFieldInputFormatters;

  const OtherOptionField({
    super.key,
    required this.title,
    required this.options,
    required this.value,
    required this.onChanged,
    this.labelOf,
    this.otherOptionValue = 'Other',
    this.customFieldLabel,
    this.customFieldHint,
    this.customFieldKeyboardType = TextInputType.text,
    this.customFieldInputFormatters,
  });

  @override
  State<OtherOptionField> createState() => _OtherOptionFieldState();
}

class _OtherOptionFieldState extends State<OtherOptionField> {
  late final TextEditingController _customCtrl;
  late bool _otherSelected;

  bool get _isCustom =>
      widget.value.isNotEmpty && !widget.options.contains(widget.value);

  @override
  void initState() {
    super.initState();
    _otherSelected = _isCustom;
    _customCtrl = TextEditingController(text: _isCustom ? widget.value : '');
  }

  @override
  void didUpdateWidget(covariant OtherOptionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value) return;
    if (_isCustom && _customCtrl.text != widget.value) {
      _customCtrl.text = widget.value;
    }
    // If the value was reset back to a known option (or cleared) from
    // outside this widget — e.g. the wizard's Skip action clearing the
    // whole section — drop the local "Other" selection so the chips
    // reflect the real state instead of getting stuck showing "Other".
    if (widget.value.isEmpty || widget.options.contains(widget.value)) {
      _otherSelected = false;
    }
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final otherIsSelected = _otherSelected || _isCustom;
    final selected = otherIsSelected ? widget.otherOptionValue : widget.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: AppTypography.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.options.map((o) {
            final sel = selected == o;
            return ChoiceChip(
              label: Text(widget.labelOf?.call(o) ?? o),
              selected: sel,
              selectedColor: AppColors.primarySurface,
              onSelected: (_) {
                if (o == widget.otherOptionValue) {
                  setState(() => _otherSelected = true);
                  // Never persist the literal "Other" placeholder — an
                  // empty value correctly keeps this field "incomplete"
                  // until the user types something specific.
                  widget.onChanged(_customCtrl.text.trim());
                } else {
                  setState(() => _otherSelected = false);
                  widget.onChanged(o);
                }
              },
            );
          }).toList(),
        ),
        if (otherIsSelected) ...[
          const SizedBox(height: 12),
          NmTextField(
            label: widget.customFieldLabel ?? l10n.commonPleaseSpecifyLabel,
            hint: widget.customFieldHint ?? l10n.commonPleaseSpecifyHint,
            controller: _customCtrl,
            keyboardType: widget.customFieldKeyboardType,
            inputFormatters: widget.customFieldInputFormatters,
            onChanged: (text) => widget.onChanged(text.trim()),
          ),
        ],
      ],
    );
  }
}
