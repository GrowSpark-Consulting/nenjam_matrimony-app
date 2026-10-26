import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/widgets/relationship_intelligence/horoscope_compatibility_section.dart';
import 'package:nenjam_matrimony/features/astro/domain/models/compatibility_result.dart';
import 'package:nenjam_matrimony/features/astro/presentation/providers/compatibility_provider.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_dashboard_providers.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// My Profile's horoscope card used to read an in-memory mock that gave every
/// member the same chart (Simha / Magha / no dosham). It must now show the
/// member's own saved Horoscope step — and nothing when they saved none.
void main() {
  Future<HoroscopeSummary> summaryFor(Map<String, dynamic> draft) {
    final container = ProviderContainer(
      overrides: [
        profileDraftResponseProvider.overrideWith((ref) async => draft),
      ],
    );
    addTearDown(container.dispose);
    // Keep the autoDispose provider alive for the read.
    final sub = container.listen(myHoroscopeSummaryProvider, (_, __) {});
    addTearDown(sub.close);
    return container.read(myHoroscopeSummaryProvider.future);
  }

  test('reflects the saved Horoscope step', () async {
    final s = await summaryFor({
      'data': {
        'horoscopeDetails': {
          'rashi': 'Kumbha',
          'nakshatra': 'Sathayam',
          'dosham': 'Yes',
          'birthTime': '05:55',
          'birthPlace': 'Madurai',
          'horoscopeAvailable': true,
        },
      },
    });
    expect(s.rasi, 'Kumbha');
    expect(s.nakshatra, 'Sathayam');
    expect(s.dosham, 'Dosham');
    expect(s.birthTime, '05:55');
    expect(s.birthPlace, 'Madurai');
    expect(s.matchingEnabled, isTrue);
  });

  test(
    'an unfilled Horoscope step yields nothing, not a default chart',
    () async {
      final s = await summaryFor({'data': <String, dynamic>{}});
      expect(s.rasi, isNull);
      expect(s.nakshatra, isNull);
      expect(s.dosham, isNull);
      expect(s.birthTime, isNull);
      expect(s.birthPlace, isNull);
      expect(s.matchingEnabled, isFalse);
    },
  );

  test(
    "'No' dosham is hidden; 'Don't Know' is not shown as an answer",
    () async {
      final no = await summaryFor({
        'horoscopeDetails': {'rashi': 'Mesha', 'dosham': 'No'},
      });
      expect(no.dosham, 'NONE'); // the widget's "hide" sentinel
      final unknown = await summaryFor({
        'horoscopeDetails': {'rashi': 'Mesha', 'dosham': "Don't Know"},
      });
      expect(unknown.dosham, isNull);
    },
  );

  test('a failed draft fetch is an error, never a made-up summary', () async {
    final container = ProviderContainer(
      overrides: [
        profileDraftResponseProvider.overrideWith(
          (ref) async => throw Exception('offline'),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(myHoroscopeSummaryProvider, (_, __) {});
    addTearDown(sub.close);
    await expectLater(
      container.read(myHoroscopeSummaryProvider.future),
      throwsA(isA<Exception>()),
    );
  });

  testWidgets('an empty summary renders the existing empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: HoroscopeCompatibilitySection(matchingEnabled: false),
        ),
      ),
    );
    await tester.pump();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(HoroscopeCompatibilitySection)),
    );
    expect(find.text(l10n.riHoroscopeEmpty), findsOneWidget);
    expect(find.text('Simha'), findsNothing);
    expect(find.text('Magha'), findsNothing);
    expect(find.text('Horoscope not available'), findsOneWidget);
  });

  // The flag is the member's "horoscope available" answer; no matching opt-in
  // setting exists, so the status must not be worded as one.
  testWidgets('the status describes availability, not a matching setting', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: HoroscopeCompatibilitySection(rasi: 'Kumbha')),
      ),
    );
    await tester.pump();
    expect(find.text('Horoscope available'), findsOneWidget);
    expect(find.textContaining('matching enabled'), findsNothing);
    expect(find.textContaining('matching disabled'), findsNothing);
  });
}
