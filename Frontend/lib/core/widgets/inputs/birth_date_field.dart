import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../constants/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../utils/birth_date.dart';
import 'app_text_field.dart';

/// Date of birth, typed: three numeric boxes reading `DD / MM / YYYY`.
///
/// The one date-of-birth input in the app — onboarding's Your Name step and
/// the Edit Profile wizard's Basic Info step both build this, so there is a
/// single answer to what the field looks like, what a member may type into
/// it, and what it says when they type something else.
///
/// Typed rather than picked. A calendar cannot express a birthdate the way
/// people hold one: a member who knows they were born on 15/08/1998 spends
/// three taps and a scroll finding it, and someone entering a son's or
/// sister's date fares worse. The rule the calendar used to enforce by
/// omission — no impossible dates, nothing in the future, nobody under
/// [kMinimumProfileAgeYears] — is enforced by [BirthDateInput] instead, which
/// is the same rule the server applies, so nothing is lost by letting the
/// boxes accept keystrokes.
///
/// It owns no answer of its own: [value] in, [onChanged] out, exactly like
/// [NmTextField]. The error shown is read off [value] rather than stored, so
/// a caller cannot leave a stale one on screen.
class NmBirthDateField extends StatefulWidget {
  /// The three boxes' current contents.
  final BirthDateInput value;

  /// Called on every keystroke with the new contents.
  final ValueChanged<BirthDateInput> onChanged;

  /// When true, every rule is reported at once — what a Save button presses
  /// on a form the member has not finished. False (the default) reports only
  /// what [BirthDateInput.liveError] considers finished enough to judge, so
  /// the field stays quiet mid-entry.
  final bool showAllErrors;

  /// Moved to when the year box fills up — the next field on the form. Null
  /// leaves focus where it is.
  final FocusNode? nextFocus;

  const NmBirthDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.showAllErrors = false,
    this.nextFocus,
  });

  @override
  State<NmBirthDateField> createState() => _NmBirthDateFieldState();
}

class _NmBirthDateFieldState extends State<NmBirthDateField> {
  late final _day = TextEditingController(text: widget.value.day);
  late final _month = TextEditingController(text: widget.value.month);
  late final _year = TextEditingController(text: widget.value.year);

  final _dayFocus = FocusNode();
  final _monthFocus = FocusNode();
  final _yearFocus = FocusNode();

  // Backspace-out-of-an-empty-box needs a key listener wrapping each of the
  // two later boxes. Held here rather than built in `build`, which would leak
  // a FocusNode every frame.
  final _monthKeys = FocusNode(skipTraversal: true, canRequestFocus: false);
  final _yearKeys = FocusNode(skipTraversal: true, canRequestFocus: false);

  @override
  void didUpdateWidget(covariant NmBirthDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A caller that rewrites the value out from under the field — restoring a
    // draft, clearing the form — has to be reflected. Guarded on equality so
    // an ordinary keystroke round-trip does not jump the cursor.
    _syncController(_day, widget.value.day);
    _syncController(_month, widget.value.month);
    _syncController(_year, widget.value.year);
  }

  static void _syncController(TextEditingController controller, String text) {
    if (controller.text == text) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  void dispose() {
    for (final controller in [_day, _month, _year]) {
      controller.dispose();
    }
    for (final node in [
      _dayFocus,
      _monthFocus,
      _yearFocus,
      _monthKeys,
      _yearKeys,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  /// Hands focus on once a box is full, so `15081998` typed straight through
  /// lands as 15 / 08 / 1998 without the member reaching for the next box.
  void _advance(String typed, int width, FocusNode? next) {
    if (typed.length < width || next == null) return;
    next.requestFocus();
  }

  /// Backspace in an empty box steps back into the previous one rather than
  /// stranding the cursor — the same behaviour as the OTP input's cells.
  /// Always reports `ignored`, so the field still handles the key itself.
  KeyEventResult _backspaceTo(
    FocusNode previous,
    TextEditingController own,
    KeyEvent event,
  ) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        own.text.isEmpty) {
      previous.requestFocus();
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final error =
        widget.showAllErrors ? widget.value.error : widget.value.liveError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Every box is Expanded, so the row fits the narrowest phone
            // instead of overflowing; the year gets the larger share because
            // four digits need the room.
            Expanded(
              flex: 3,
              child: _box(
                controller: _day,
                focus: _dayFocus,
                label: l10n.birthDateDayLabel,
                hint: l10n.birthDateDayHint,
                width: 2,
                onChanged: (v) {
                  widget.onChanged(widget.value.copyWith(day: v));
                  _advance(v, 2, _monthFocus);
                },
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 3,
              child: Focus(
                focusNode: _monthKeys,
                onKeyEvent: (_, e) => _backspaceTo(_dayFocus, _month, e),
                child: _box(
                  controller: _month,
                  focus: _monthFocus,
                  label: l10n.birthDateMonthLabel,
                  hint: l10n.birthDateMonthHint,
                  width: 2,
                  onChanged: (v) {
                    widget.onChanged(widget.value.copyWith(month: v));
                    _advance(v, 2, _yearFocus);
                  },
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 4,
              child: Focus(
                focusNode: _yearKeys,
                onKeyEvent: (_, e) => _backspaceTo(_monthFocus, _year, e),
                child: _box(
                  controller: _year,
                  focus: _yearFocus,
                  label: l10n.birthDateYearLabel,
                  hint: l10n.birthDateYearHint,
                  width: 4,
                  textInputAction: widget.nextFocus == null
                      ? TextInputAction.done
                      : TextInputAction.next,
                  onChanged: (v) {
                    widget.onChanged(widget.value.copyWith(year: v));
                    _advance(v, 4, widget.nextFocus);
                  },
                ),
              ),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            birthDateErrorMessage(l10n, error),
            style: AppTypography.labelSmall.copyWith(color: colors.error),
          ),
        ],
      ],
    );
  }

  Widget _box({
    required TextEditingController controller,
    required FocusNode focus,
    required String label,
    required String hint,
    required int width,
    required ValueChanged<String> onChanged,
    TextInputAction textInputAction = TextInputAction.next,
  }) {
    return NmTextField(
      controller: controller,
      focusNode: focus,
      label: label,
      hint: hint,
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      textAlign: TextAlign.center,
      maxLength: width,
      // Digits only, so "1o" and a pasted "15/08/1998" never reach the rule
      // as something it has to explain.
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: onChanged,
    );
  }
}

/// What to tell the member about [error], in their language.
///
/// Lives beside the field rather than inside it, so a screen that renders the
/// message somewhere else — a summary line, a snackbar — says the same thing.
String birthDateErrorMessage(AppLocalizations l10n, BirthDateError error) =>
    switch (error) {
      BirthDateError.day => l10n.birthDateErrorDay,
      BirthDateError.month => l10n.birthDateErrorMonth,
      BirthDateError.year => l10n.birthDateErrorYear,
      BirthDateError.invalidDate => l10n.birthDateErrorInvalid,
      BirthDateError.future => l10n.birthDateErrorFuture,
      BirthDateError.tooYoung =>
        l10n.birthDateErrorTooYoung(kMinimumProfileAgeYears),
    };
