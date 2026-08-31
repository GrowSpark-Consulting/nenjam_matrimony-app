import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/widgets/indicators/nm_gradient_progress_bar.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/identity_hero_card.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// The identity hero used to carry two scores side by side: a Trust ring
/// and the profile-completion bar. Only the completion bar survives — these
/// tests pin that split so neither half drifts back into the other.
Future<void> _pumpCard(WidgetTester tester, {int completion = 82}) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: NmIdentityHeroCard(
            name: 'Meera Lakshmi',
            age: 27,
            nmId: 'NM984523',
            location: 'Madurai, Tamil Nadu',
            profileCompletion: completion,
            faith: 'Hindu',
            height: "5'4\"",
            profession: 'Data Scientist',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the profile completion score', (tester) async {
    await _pumpCard(tester, completion: 76);

    expect(find.text('Profile Completion'), findsOneWidget);
    expect(find.text('76%'), findsOneWidget);
    expect(find.byType(NmGradientProgressBar), findsOneWidget);
  });

  testWidgets('completion score tracks the value it is given', (tester) async {
    await _pumpCard(tester, completion: 40);
    expect(find.text('40%'), findsOneWidget);

    final bar = tester.widget<NmGradientProgressBar>(
      find.byType(NmGradientProgressBar),
    );
    expect(bar.value, closeTo(0.4, 0.001));
  });

  testWidgets('shows no trust score ring or TRUST tag', (tester) async {
    await _pumpCard(tester);

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect((text.data ?? '').toLowerCase(), isNot(contains('trust')));
    }
  });
}
