import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/widgets/relationship_intelligence/psychology_section.dart';
import 'package:nenjam_matrimony/features/psychology/domain/models/personality_result.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import 'psychology_test_support.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('not taken + callback shows the take-quiz CTA', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      PsychologySection(result: null, onTakeQuizTap: () => taps++),
    );
    expect(find.text('Share your marriage expectations'), findsOneWidget);
    await tester.tap(find.byType(GestureDetector).first);
    expect(taps, 1);
  });

  testWidgets('not taken without a callback renders nothing', (tester) async {
    await _pump(tester, const PsychologySection(result: null));
    expect(find.text('Share your marriage expectations'), findsNothing);
    expect(find.textContaining('Completed'), findsNothing);
  });

  testWidgets('completed shows Completed + updated date + Retake, no traits', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      PsychologySection(
        result: PsychologyQuizResponse.fromJson(myResponseJson()),
        onTakeQuizTap: () => taps++,
      ),
    );
    expect(find.text('Marriage Compatibility Quiz'), findsOneWidget);
    expect(find.text('Completed · Updated Sep 23, 2026'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('Openness'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.text('Retake'));
    expect(taps, 1);
  });

  testWidgets('completed without a callback hides Retake', (tester) async {
    await _pump(
      tester,
      PsychologySection(
        result: PsychologyQuizResponse.fromJson(myResponseJson()),
      ),
    );
    expect(find.text('Completed · Updated Sep 23, 2026'), findsOneWidget);
    expect(find.text('Retake'), findsNothing);
  });
}
