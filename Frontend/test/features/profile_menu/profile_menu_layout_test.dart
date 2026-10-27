// Completion-percentage x width matrix — one of the heaviest files in the
// suite. Runs on main/pre-merge, not PRs.
// See .github/workflows/ci.yml for the fast/full split.
@Tags(['heavy'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/widgets/avatars/app_avatars.dart';
import 'package:nenjam_matrimony/core/widgets/indicators/nm_gradient_progress_bar.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_dashboard_providers.dart';
import 'package:nenjam_matrimony/features/profile_menu/presentation/pages/profile_menu_page.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Sizing + Profile Strength contract for the profile menu.
///
/// Route/navigation structure is pinned by `profile_menu_presentation_test`;
/// this file covers what the UI refinement touched — the responsive avatar,
/// the enlarged type, and above all the Profile Strength bar, whose fill has
/// to be the backend's completion percentage and nothing else.
///
/// The widths are the ones the app ships to, 320dp through 480dp.
const _widths = <double>[320, 360, 375, 393, 412, 430, 480];

/// A `GET /profiles/draft` response. [percentage] is the backend's own
/// `completionPercentage` — the single value this page may render.
Map<String, dynamic> _draft(int percentage) => <String, dynamic>{
  'completionPercentage': percentage,
  'completionBreakdown': const <Map<String, dynamic>>[],
  'basicDetails': <String, dynamic>{
    'firstName': 'Dhatri',
    'lastName': 'Patel',
    'gender': 'FEMALE',
    // Fixed date: age is derived, and the exact number never matters here.
    'dob': '1999-04-12T00:00:00.000',
  },
  'religionDetails': <String, dynamic>{'community': 'Patidar Community'},
  'locationDetails': <String, dynamic>{
    'city': 'Bengaluru',
    'state': 'Karnataka',
    'country': 'India',
  },
};

Future<void> _pumpMenu(
  WidgetTester tester, {
  int percentage = 72,
  Size size = const Size(412, 915),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileDraftResponseProvider.overrideWith(
          (ref) async => _draft(percentage),
        ),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProfileMenuPage(),
      ),
    ),
  );
  // Settle the draft future, then run out the bar's fill animation.
  await tester.pump();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Fraction of the track the gradient fill actually covers, measured off the
/// laid-out render boxes rather than read back off the widget's own `value`
/// — a bar whose fill is painted at zero width would still report the right
/// value.
double _filledFraction(WidgetTester tester) {
  final bar = find.byType(NmGradientProgressBar);
  final fill = find.descendant(
    of: bar,
    matching: find.byType(FractionallySizedBox),
  );
  final trackWidth = tester.getSize(bar).width;
  return tester.getSize(fill).width / trackWidth;
}

/// Every layout error recorded this frame, not just the first.
List<Object> _drainExceptions(WidgetTester tester) {
  final out = <Object>[];
  while (out.length < 20) {
    final Object? e = tester.takeException() as Object?;
    if (e == null) break;
    out.add(e);
  }
  return out;
}

void main() {
  group('Profile Strength card', () {
    testWidgets('renders the label, the backend percentage and a bar', (
      tester,
    ) async {
      await _pumpMenu(tester, percentage: 72);

      expect(find.text('Profile Strength'), findsOneWidget);
      expect(find.text('72%'), findsOneWidget);
      expect(find.byType(NmGradientProgressBar), findsOneWidget);
    });

    // The whole point of the card: the line is the score, at every value the
    // backend can hand it.
    for (final pct in const [0, 25, 45, 72, 90, 100]) {
      testWidgets('$pct% fills the bar to $pct% of its width', (tester) async {
        await _pumpMenu(tester, percentage: pct);

        expect(find.text('$pct%'), findsOneWidget);
        expect(
          tester
              .widget<NmGradientProgressBar>(find.byType(NmGradientProgressBar))
              .value,
          closeTo(pct / 100, 1e-9),
        );
        expect(
          _filledFraction(tester),
          closeTo(pct / 100, 0.01),
          reason: 'the painted fill must match the backend percentage',
        );
      });
    }

    testWidgets('0% paints no fill at all', (tester) async {
      await _pumpMenu(tester, percentage: 0);
      expect(_filledFraction(tester), 0.0);
    });

    testWidgets('100% fills the track completely', (tester) async {
      await _pumpMenu(tester, percentage: 100);
      expect(_filledFraction(tester), closeTo(1.0, 1e-9));
    });

    testWidgets('the fill has real height — it is not an empty line', (
      tester,
    ) async {
      await _pumpMenu(tester, percentage: 72);

      final fill = find.descendant(
        of: find.byType(NmGradientProgressBar),
        matching: find.byType(FractionallySizedBox),
      );
      expect(tester.getSize(fill).height, greaterThan(0));
      expect(
        tester.getSize(fill).height,
        tester.getSize(find.byType(NmGradientProgressBar)).height,
      );
    });

    testWidgets('a percentage outside 0–100 is clamped, not extrapolated', (
      tester,
    ) async {
      await _pumpMenu(tester, percentage: 140);
      expect(find.text('100%'), findsOneWidget);
      expect(_filledFraction(tester), closeTo(1.0, 1e-9));
    });
  });

  group('responsive header', () {
    testWidgets('the avatar scales with the device and stays bounded', (
      tester,
    ) async {
      final sizes = <double, double>{};
      for (final w in _widths) {
        await _pumpMenu(tester, size: Size(w, 900));
        sizes[w] = tester
            .widget<NmCircleAvatar>(find.byType(NmCircleAvatar).first)
            .size;
      }

      // Present at every width, never tiny, never huge.
      for (final entry in sizes.entries) {
        expect(
          entry.value,
          inInclusiveRange(69.0, 97.0),
          reason: 'avatar at ${entry.key}dp',
        );
      }
      // And it genuinely tracks the device rather than being one fixed size.
      expect(sizes[320]!, lessThan(sizes[375]!));
      expect(sizes[375]!, lessThan(sizes[430]!));
      // Capped, so a tablet-width viewport cannot keep growing it: 480dp is
      // already past the ceiling and sits on it.
      expect(sizes[480], 97.0);
    });

    testWidgets('the identity text renders at the enlarged sizes', (
      tester,
    ) async {
      await _pumpMenu(tester);

      expect(find.text('Dhatri Patel'), findsOneWidget);
      expect(
        find.textContaining('Bengaluru, Karnataka, India'),
        findsOneWidget,
      );
      expect(find.text('Patidar Community'), findsOneWidget);

      double sizeOf(Finder f) => tester.widget<Text>(f).style!.fontSize!;

      final name = sizeOf(find.text('Dhatri Patel'));
      final subtitle = sizeOf(
        find.textContaining('Bengaluru, Karnataka, India'),
      );
      final community = sizeOf(find.text('Patidar Community'));

      // Bigger than the sizes this refinement started from…
      expect(name, greaterThan(16));
      expect(subtitle, greaterThan(12));
      expect(community, greaterThan(11));
      // …with the hierarchy between them unchanged.
      expect(name, greaterThan(subtitle));
      expect(subtitle, greaterThan(community));
    });

    testWidgets('menu labels and footer grew too, without changing order', (
      tester,
    ) async {
      await _pumpMenu(tester);

      expect(tester.widget<Text>(find.text('My Profile')).style!.fontSize, 15);
      expect(
        tester.widget<Text>(find.textContaining('Rate Us')).style!.fontSize,
        greaterThan(10),
      );

      // Order is part of the contract this refinement must not disturb.
      double y(String label) => tester.getTopLeft(find.text(label)).dy;
      expect(y('My Profile'), lessThan(y('Edit Profile')));
      expect(y('Edit Profile'), lessThan(y('Partner Preferences')));
      expect(y('Partner Preferences'), lessThan(y('Verification Center')));
    });
  });

  group('no overflow at any shipped width', () {
    for (final w in _widths) {
      testWidgets('${w.toInt()}dp portrait lays out cleanly', (tester) async {
        await _pumpMenu(tester, size: Size(w, 900));

        expect(
          _drainExceptions(tester).map((e) => e.toString().split('\n').first),
          isEmpty,
        );
      });
    }

    testWidgets('landscape lays out cleanly on the smallest phone', (
      tester,
    ) async {
      await _pumpMenu(tester, size: const Size(568, 320));

      expect(
        _drainExceptions(tester).map((e) => e.toString().split('\n').first),
        isEmpty,
      );
    });

    testWidgets('a large system text scale does not clip the card', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileDraftResponseProvider.overrideWith(
              (ref) async => _draft(72),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery.withClampedTextScaling(
              minScaleFactor: 1.3,
              maxScaleFactor: 1.3,
              child: child!,
            ),
            home: const ProfileMenuPage(),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('72%'), findsOneWidget);
      expect(
        _drainExceptions(tester).map((e) => e.toString().split('\n').first),
        isEmpty,
      );
    });
  });
}
