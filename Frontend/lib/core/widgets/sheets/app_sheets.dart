import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// A single row in [AppSheets.showActionSheet].
class AppSheetAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const AppSheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });
}

/// Nenjam Matrimony — Reusable Bottom Sheets Kit
abstract final class AppSheets {
  /// Base styled Bottom Sheet wrapper.
  ///
  /// The drag handle is NOT drawn here — `AppTheme`'s `bottomSheetTheme`
  /// sets `showDragHandle: true` globally, so Flutter's `Material` already
  /// draws one above `builder`'s content for every modal bottom sheet in
  /// the app. Drawing a second one here (as this used to) produced two
  /// stacked handles. Same reasoning for `shape` — the theme's
  /// `bottomSheetTheme.shape` already matches what was hardcoded here, so
  /// `showModalBottomSheet` falls back to it without needing to repeat it.
  static Future<T?> show<T>(
    BuildContext context, {
    required Widget child,
    String? title,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null) ...[
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(title, style: AppTypography.titleLarge),
                ),
                const Divider(height: 1),
              ],
              // Flexible (not Expanded) so RenderFlex computes this
              // sheet-body's max height as "whatever's left after the
              // handle bar/title above" and caps `child` to exactly that —
              // the overflow this fixes was `child` never seeing that
              // reduction (a bare Column child gets the *full* incoming
              // height, not the remainder after siblings), so any
              // sizeable `child` could ask for a fraction more than the
              // handle bar/title actually left. Loose fit (Flexible's
              // default) still lets small children — the option lists
              // from showSelection() — size to their own content instead
              // of being stretched to fill the sheet.
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }

  /// Reusable Selection Sheet.
  static Future<String?> showSelection(
    BuildContext context, {
    required String title,
    required List<String> options,
    String? selectedValue,
  }) {
    return show<String>(
      context,
      title: title,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: options.length,
        itemBuilder: (context, index) {
          final opt = options[index];
          final isSelected = opt == selectedValue;
          return ListTile(
            title: Text(
              opt,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isSelected ? AppColors.primary : null,
              ),
            ),
            trailing: isSelected
                ? const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.primary,
                  )
                : null,
            onTap: () => Navigator.pop(context, opt),
          );
        },
      ),
    );
  }

  /// Gender Selection Sheet.
  static Future<String?> showGender(BuildContext context, {String? selected}) {
    return showSelection(
      context,
      title: AppLocalizations.of(context).fieldGenderHint,
      options: ['Male', 'Female'],
      selectedValue: selected,
    );
  }

  /// Religion Selection Sheet.
  static Future<String?> showReligion(
    BuildContext context, {
    String? selected,
  }) {
    return showSelection(
      context,
      title: AppLocalizations.of(context).fieldReligionHint,
      options: ['Hindu', 'Christian', 'Muslim', 'Jain', 'Sikh'],
      selectedValue: selected,
    );
  }

  /// Language Selection Sheet.
  static Future<String?> showLanguage(
    BuildContext context, {
    String? selected,
  }) {
    return showSelection(
      context,
      title: AppLocalizations.of(context).fieldMotherTongue,
      options: ['Tamil', 'Telugu', 'Malayalam', 'Kannada', 'Hindi', 'English'],
      selectedValue: selected,
    );
  }

  /// Searchable Selection Sheet — like [showSelection], but with a filter
  /// text field above the list for long option lists (e.g. city,
  /// community, star/rashi) where scrolling to find one entry is tedious.
  static Future<String?> showSearchableSelection(
    BuildContext context, {
    required String title,
    required List<String> options,
    String? selectedValue,
  }) {
    return show<String>(
      context,
      title: title,
      child: _SearchableSelectionBody(
        options: options,
        selectedValue: selectedValue,
      ),
    );
  }

  /// Multi-Select Sheet — like [showSelection], but lets the user toggle any
  /// number of options on/off (checkboxes) before confirming with a bottom
  /// "Done" button. Returns null if dismissed without confirming.
  static Future<List<String>?> showMultiSelection(
    BuildContext context, {
    required String title,
    required List<String> options,
    List<String> selectedValues = const [],
  }) {
    return show<List<String>>(
      context,
      title: title,
      child: _MultiSelectionBody(
        options: options,
        selectedValues: selectedValues,
      ),
    );
  }

  /// Free-text Input Sheet — a single-line text field with a "Done" button,
  /// for optional free-text preference fields (sub-caste, colleges, field of
  /// study) that don't fit a fixed option list.
  static Future<String?> showTextInput(
    BuildContext context, {
    required String title,
    String? initialValue,
    String? hint,
  }) {
    return show<String>(
      context,
      title: title,
      child: _TextInputBody(initialValue: initialValue, hint: hint),
    );
  }

  /// Generic icon+label options sheet — e.g. a long-press "View Profile /
  /// Mute / Archive / Block / Delete" menu. Each row pops the sheet, then
  /// runs its own [AppSheetAction.onTap].
  static Future<void> showActionSheet(
    BuildContext context, {
    String? title,
    required List<AppSheetAction> actions,
  }) {
    return show<void>(
      context,
      title: title,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: actions.length,
        itemBuilder: (context, index) {
          final action = actions[index];
          final color = action.isDestructive
              ? AppColors.error
              : AppColors.primary;
          return ListTile(
            leading: Icon(action.icon, color: color),
            title: Text(
              action.label,
              style: AppTypography.bodyMedium.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              action.onTap();
            },
          );
        },
      ),
    );
  }

  /// Date Sheet picker modal.
  ///
  /// [firstDate] and [lastDate] default to the age band every date-of-birth
  /// field in the app has always used — 1950 to eighteen years ago — and are
  /// overridable only so a caller that owns a stricter or more precise
  /// statement of the same rule can hand it in rather than keep a second
  /// picker of its own. Onboarding's Your Name step does exactly that: its
  /// `OnboardingNameForm` allows up to eighteen years ago *to the day*, and
  /// the picker must not disable a date the form would accept.
  static Future<DateTime?> showDate(
    BuildContext context, {
    DateTime? initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
  }) async {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime(now.year - 25),
      firstDate: firstDate ?? DateTime(1950),
      lastDate: lastDate ?? DateTime(now.year - 18),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppColors.primary,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
  }
}

/// Filter text field + live-filtered option list, used by
/// [AppSheets.showSearchableSelection]. Kept private/colocated since it's
/// only ever reached through that one entry point.
class _SearchableSelectionBody extends StatefulWidget {
  final List<String> options;
  final String? selectedValue;

  const _SearchableSelectionBody({required this.options, this.selectedValue});

  @override
  State<_SearchableSelectionBody> createState() =>
      _SearchableSelectionBodyState();
}

class _SearchableSelectionBodyState extends State<_SearchableSelectionBody> {
  final _controller = TextEditingController();
  late List<String> _filtered = widget.options;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    final normalized = query.trim().toLowerCase();
    setState(() {
      _filtered = normalized.isEmpty
          ? widget.options
          : widget.options
                .where((o) => o.toLowerCase().contains(normalized))
                .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: TextField(
            controller: _controller,
            onChanged: _onQueryChanged,
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context).commonSearchHint,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            style: AppTypography.bodyMedium,
          ),
        ),
        Flexible(
          child: _filtered.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(AppLocalizations.of(context).commonNoMatches),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filtered.length,
                  itemBuilder: (context, index) {
                    final opt = _filtered[index];
                    final isSelected = opt == widget.selectedValue;
                    return ListTile(
                      title: Text(
                        opt,
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isSelected ? AppColors.primary : null,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.primary,
                            )
                          : null,
                      onTap: () => Navigator.pop(context, opt),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Checkbox option list + "Done" button, used by [AppSheets.showMultiSelection].
class _MultiSelectionBody extends StatefulWidget {
  final List<String> options;
  final List<String> selectedValues;

  const _MultiSelectionBody({
    required this.options,
    required this.selectedValues,
  });

  @override
  State<_MultiSelectionBody> createState() => _MultiSelectionBodyState();
}

class _MultiSelectionBodyState extends State<_MultiSelectionBody> {
  late final Set<String> _selected = widget.selectedValues.toSet();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.options.length,
            itemBuilder: (context, index) {
              final opt = widget.options[index];
              final isSelected = _selected.contains(opt);
              return CheckboxListTile(
                title: Text(
                  opt,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                    color: isSelected ? AppColors.primary : null,
                  ),
                ),
                value: isSelected,
                onChanged: (checked) => setState(() {
                  if (checked ?? false) {
                    _selected.add(opt);
                  } else {
                    _selected.remove(opt);
                  }
                }),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _selected.toList()),
              child: Text(AppLocalizations.of(context).commonDone),
            ),
          ),
        ),
      ],
    );
  }
}

/// Single-line text field + "Done" button, used by [AppSheets.showTextInput].
class _TextInputBody extends StatefulWidget {
  final String? initialValue;
  final String? hint;

  const _TextInputBody({this.initialValue, this.hint});

  @override
  State<_TextInputBody> createState() => _TextInputBodyState();
}

class _TextInputBodyState extends State<_TextInputBody> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: widget.hint,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            style: AppTypography.bodyMedium,
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _controller.text.trim()),
              child: Text(AppLocalizations.of(context).commonDone),
            ),
          ),
        ],
      ),
    );
  }
}
