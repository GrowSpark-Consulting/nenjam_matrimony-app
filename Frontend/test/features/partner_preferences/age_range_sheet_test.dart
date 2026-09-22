import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/partner_preferences/presentation/widgets/age_range_sheet.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// The age sheet used to offer only a slider, which can narrow a range but
/// never remove one — so a saved age limit could not be cleared. "Any" returns
/// the explicit "no limit" value the repository sends as a clear.
void main() {
  Future<String?> openAndPick(WidgetTester tester, String Function(AppLocalizations) label) async {
    String? result = 'untouched';
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showAgeRangeSheet(
                    context,
                    currentValue: '26-30',
                    title: 'Age',
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label(l10n)));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('"Any" returns the explicit no-limit value', (tester) async {
    expect(await openAndPick(tester, (l) => l.commonAny), 'Any');
  });

  testWidgets('Done still returns the chosen range', (tester) async {
    expect(await openAndPick(tester, (l) => l.commonDone), '26-30');
  });
}
