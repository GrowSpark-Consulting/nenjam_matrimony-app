import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/widgets/indicators/nm_gradient_progress_bar.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_dashboard_providers.dart';
import 'package:nenjam_matrimony/features/profile_completion/presentation/pages/profile_completion_page.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// The Profile Strength screen answers exactly one question — "how complete
/// is my profile?" — off the backend's `completionPercentage`. These tests
/// pin that contract: the headline figure, tier and bar always come from the
/// backend response, and no trust concept survives anywhere on the screen.

/// A `GET /profiles/draft` response shaped the way the backend's
/// ProfileCompletionService returns it.
Map<String, dynamic> _draft({
  required int percentage,
  List<Map<String, dynamic>> breakdown = const [],
}) => <String, dynamic>{
  'completionPercentage': percentage,
  'completionBreakdown': breakdown,
};

Map<String, dynamic> _module(
  String id,
  double weight,
  bool isComplete,
  int wizardStep,
) => <String, dynamic>{
  'id': id,
  'weight': weight,
  'isComplete': isComplete,
  'wizardStep': wizardStep,
};

Future<void> _pump(WidgetTester tester, Map<String, dynamic> draftJson) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileDraftResponseProvider.overrideWith((ref) async => draftJson),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProfileCompletionPage(),
      ),
    ),
  );
  // Resolve the draft future, then let the hero's progress tween run out.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

double _barValue(WidgetTester tester) => tester
    .widget<NmGradientProgressBar>(find.byType(NmGradientProgressBar))
    .value;

void main() {
  group('headline completion figure', () {
    testWidgets('renders the backend percentage, never a hardcoded one', (
      tester,
    ) async {
      await _pump(
        tester,
        _draft(
          percentage: 72,
          breakdown: [
            _module('registration', 20, true, 0),
            _module('photos', 12, false, 11),
          ],
        ),
      );

      expect(find.text('72%'), findsOneWidget);
      expect(find.text('100%'), findsNothing);
    });

    testWidgets('a different backend percentage moves the figure', (
      tester,
    ) async {
      await _pump(tester, _draft(percentage: 45));

      expect(find.text('45%'), findsOneWidget);
      expect(find.text('72%'), findsNothing);
    });

    testWidgets('100% completion displays correctly', (tester) async {
      await _pump(
        tester,
        _draft(
          percentage: 100,
          breakdown: [
            _module('registration', 20, true, 0),
            _module('education', 10, true, 4),
            _module('verification', 25, true, 12),
          ],
        ),
      );

      expect(find.text('100%'), findsOneWidget);
      expect(_barValue(tester), 1.0);
      // Everything done: nothing is left in "Still Growing".
      expect(find.text('Still Growing'), findsNothing);
      expect(find.text('Your Story So Far'), findsOneWidget);
    });

    testWidgets(
      'the figure stays the backend value even though the verification '
      'card is not shown',
      (tester) async {
        // 75 = everything except the backend's 25-point verification module.
        await _pump(
          tester,
          _draft(
            percentage: 75,
            breakdown: [
              _module('registration', 20, true, 0),
              _module('education', 10, true, 4),
              _module('verification', 25, false, 12),
            ],
          ),
        );

        // Not recomputed from the two visible cards (which would read 100%).
        expect(find.text('75%'), findsOneWidget);
        expect(find.text('100%'), findsNothing);
        expect(_barValue(tester), 0.75);
      },
    );
  });

  group('progress bar', () {
    testWidgets('fill matches the percentage exactly', (tester) async {
      await _pump(tester, _draft(percentage: 72));
      expect(_barValue(tester), closeTo(0.72, 1e-9));
    });

    testWidgets('an empty profile leaves the bar empty', (tester) async {
      await _pump(tester, _draft(percentage: 0));
      expect(find.text('0%'), findsOneWidget);
      expect(_barValue(tester), 0.0);
    });
  });

  group('status label', () {
    // One band per test: each needs its own pump of a fresh tree, and the
    // label must be derived from the percentage rather than fixed.
    for (final band in const [
      (20, 'Building'),
      (45, 'Good'),
      (72, 'Strong'),
      (95, 'Exceptional'),
      (100, 'Exceptional'),
    ]) {
      testWidgets('${band.$1}% reads "${band.$2}"', (tester) async {
        await _pump(tester, _draft(percentage: band.$1));

        expect(find.text('${band.$1}%'), findsOneWidget);
        expect(find.text(band.$2), findsOneWidget);
      });
    }
  });

  group('trust is gone from this screen', () {
    testWidgets('no Highest Impact Improvement, no Build Trust, no trust copy', (
      tester,
    ) async {
      // Verification is the heaviest incomplete module — exactly the case
      // that used to render the "Build Trust" highest-impact card.
      await _pump(
        tester,
        _draft(
          percentage: 60,
          breakdown: [
            _module('registration', 20, true, 0),
            _module('verification', 25, false, 12),
            _module('photos', 12, false, 11),
          ],
        ),
      );

      expect(find.text('Highest Impact Improvement'), findsNothing);
      expect(find.text('Build Trust'), findsNothing);
      expect(
        find.text('Verified profiles earn more trust and better responses.'),
        findsNothing,
      );
      expect(find.text('Verification'), findsNothing);
      expect(find.textContaining('Trust'), findsNothing);
      expect(find.textContaining('trust'), findsNothing);
    });
  });

  group('completion sections', () {
    testWidgets('"Your Story So Far" lists the completed modules', (
      tester,
    ) async {
      await _pump(
        tester,
        _draft(
          percentage: 30,
          breakdown: [
            _module('registration', 20, true, 0),
            _module('education', 10, true, 4),
            _module('photos', 12, false, 11),
          ],
        ),
      );

      expect(find.text('Your Story So Far'), findsOneWidget);
      expect(find.text('Education'), findsOneWidget);
      // 'Your Story' was the generic `registration` card. That module is now
      // rendered as its own field-by-field "Registration information" group,
      // so a card here would say the same thing twice and less usefully —
      // see _isCompletionSection.
      expect(find.text('Your Story'), findsNothing);
    });

    testWidgets(
      '"Still Growing" lists every incomplete module with its action, '
      'heaviest first',
      (tester) async {
        await _pump(
          tester,
          _draft(
            percentage: 20,
            breakdown: [
              _module('registration', 20, true, 0),
              _module('family', 10, false, 7),
              _module('photos', 12, false, 11),
            ],
          ),
        );

        expect(find.text('Still Growing'), findsOneWidget);
        expect(find.text('Boost Your Match Quality'), findsOneWidget);
        expect(find.text('Complete Your Family Details'), findsOneWidget);

        final photos = tester
            .getTopLeft(find.text('Boost Your Match Quality'))
            .dy;
        final family = tester
            .getTopLeft(find.text('Complete Your Family Details'))
            .dy;
        expect(photos, lessThan(family));
      },
    );

    testWidgets(
      'a long action label still fits a Still Growing card on a narrow phone',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        // "Take the Psychology Assessment" is the longest action label in
        // the set, and every missing module now lands in this list.
        await _pump(
          tester,
          _draft(
            percentage: 40,
            breakdown: [_module('psychology', 3, false, 9)],
          ),
        );

        expect(tester.takeException(), isNull);
      },
    );
  });
}
