import 'package:flutter/material.dart';

import '../../../../core/widgets/inputs/range_slider.dart';
import '../../../../core/widgets/sheets/app_sheets.dart';
import '../../../../l10n/app_localizations.dart';

/// Parses the free-text age-range strings this app already stores (e.g.
/// `"18-22"`, `"30-35"`) into a [RangeValues] — mirrors the backend's
/// `parseIntRange` regex (`profile.service.ts`) so round-tripping through
/// either side never loses precision. Falls back to a sane default for
/// unparseable/empty/"Any" values.
RangeValues parseAgeRange(String value) {
  final match = RegExp(r'(\d+)\D+(\d+)').firstMatch(value);
  if (match == null) return const RangeValues(21, 35);
  return RangeValues(double.parse(match.group(1)!), double.parse(match.group(2)!));
}

/// Opens a bottom sheet with a dual-handle age-range slider, returning a
/// backend-compatible `"min-max"` string (same format the 10 base fields
/// already use) or null if dismissed.
Future<String?> showAgeRangeSheet(BuildContext context, {required String currentValue, required String title}) {
  return AppSheets.show<String>(
    context,
    title: title,
    child: _AgeRangeSheetBody(initial: parseAgeRange(currentValue)),
  );
}

class _AgeRangeSheetBody extends StatefulWidget {
  final RangeValues initial;

  const _AgeRangeSheetBody({required this.initial});

  @override
  State<_AgeRangeSheetBody> createState() => _AgeRangeSheetBodyState();
}

class _AgeRangeSheetBodyState extends State<_AgeRangeSheetBody> {
  late RangeValues _range = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NmRangeSlider(
            label: AppLocalizations.of(context).partnerPrefAgeSheetTitle,
            range: _range,
            min: 18,
            max: 65,
            divisions: 47,
            onChanged: (v) => setState(() => _range = v),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, '${_range.start.round()}-${_range.end.round()}'),
              child: Text(AppLocalizations.of(context).commonDone),
            ),
          ),
          // The slider alone could only ever narrow: there was no way to say
          // "no age limit", so a range once saved could never be cleared.
          // "Any" is sent as an explicit clear (see the repository's request
          // body), which is what makes it different from leaving the row
          // untouched.
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context, 'Any'),
              child: Text(AppLocalizations.of(context).commonAny),
            ),
          ),
        ],
      ),
    );
  }
}
