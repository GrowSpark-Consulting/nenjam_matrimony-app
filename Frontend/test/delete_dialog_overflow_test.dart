import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/widgets/dialogs/app_dialogs.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

Future<void> _openDelete(
  WidgetTester tester,
  String title, {
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: child!,
      ),
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => AppDialogs.showDelete(
            context,
            title: title,
            message: 'This chat will be removed for you.',
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  // The width from the bug report: a 246.8px title constraint means a
  // ~294.8px dialog, i.e. a ~375px-wide screen.
  testWidgets('delete dialog does not overflow at the reported width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _openDelete(tester, 'Delete conversation?');
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete dialog does not overflow with a large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _openDelete(tester, 'Delete conversation?', textScale: 1.5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete dialog does not overflow on a narrow screen', (
    tester,
  ) async {
    // Narrow Android phone width that produced the 246.8px title constraint.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _openDelete(tester, 'Delete conversation?');
    expect(tester.takeException(), isNull);
    expect(find.text('Delete conversation?'), findsOneWidget);
  });

  testWidgets('delete dialog wraps a very long title without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _openDelete(
      tester,
      'Delete conversation with Priyadharshini Balasubramaniam?',
    );
    expect(tester.takeException(), isNull);
  });
}
