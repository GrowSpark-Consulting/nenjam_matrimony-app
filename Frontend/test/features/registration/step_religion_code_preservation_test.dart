import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/constants/profile_options.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/presentation/widgets/step_religion.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import 'onboarding_test_support.dart';

/// `religionCode`/`communityCode` across the two religion screens.
///
/// The onboarding Religion step picks from the live religion master data and
/// stores both halves — the code the server validates and the label the member
/// reads back. [StepReligion] (Edit Profile) offers [ProfileOptions], which is
/// labels only. It used to rebuild [ReligionDetails] from scratch on every
/// keystroke, so editing *any* field there silently reset both codes to '' and
/// `toJson` then omitted them: the structured pair captured during onboarding
/// was lost on the first edit.
///
/// These pin that the pair survives an unrelated edit, and is dropped only
/// when the label it identifies actually changes.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
    // RegistrationHelperTip fades in through flutter_animate.
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> choose(WidgetTester tester, String option) async {
    final chip = find.widgetWithText(ChoiceChip, option).first;
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  /// A draft as onboarding leaves it: labels *and* master-data codes.
  const onboarded = ReligionDetails(
    religion: 'Hindu',
    community: 'Nadar',
    religionCode: 'REL_HINDU',
    communityCode: 'COM_NADAR',
    caste: 'Nadar',
    gothra: 'Bharadwaj',
  );

  group('codes survive an unrelated edit', () {
    testWidgets('editing a free-text field keeps both codes', (tester) async {
      ReligionDetails? emitted;
      await pump(
        tester,
        StepReligion(details: onboarded, onChanged: (d) => emitted = d),
      );

      // Type into Gothra — nothing to do with religion or community.
      await tester.enterText(find.byType(TextField).at(1), 'Kashyap');
      await tester.pumpAndSettle();

      expect(emitted, isNotNull);
      expect(emitted!.gothra, 'Kashyap');
      // The regression: these used to come back empty.
      expect(emitted!.religionCode, 'REL_HINDU');
      expect(emitted!.communityCode, 'COM_NADAR');
      // And the labels are untouched.
      expect(emitted!.religion, 'Hindu');
      expect(emitted!.community, 'Nadar');
    });

    testWidgets('re-picking the same religion is a no-op for codes', (
      tester,
    ) async {
      ReligionDetails? emitted;
      await pump(
        tester,
        StepReligion(details: onboarded, onChanged: (d) => emitted = d),
      );

      await choose(tester, 'Hindu');

      expect(emitted?.religionCode, 'REL_HINDU');
      expect(emitted?.communityCode, 'COM_NADAR');
    });
  });

  group('codes are dropped when their label changes', () {
    testWidgets('changing religion clears both codes', (tester) async {
      ReligionDetails? emitted;
      await pump(
        tester,
        StepReligion(details: onboarded, onChanged: (d) => emitted = d),
      );

      await choose(tester, 'Jain');

      expect(emitted?.religion, 'Jain');
      // A code identifies the religion it was captured for; this step has no
      // master-data lookup to mint a replacement, so it falls back to free
      // text rather than carrying a code that now names the wrong religion.
      expect(emitted?.religionCode, isEmpty);
      expect(emitted?.communityCode, isEmpty);
    });

    testWidgets('changing community clears only the community code', (
      tester,
    ) async {
      ReligionDetails? emitted;
      await pump(
        tester,
        StepReligion(details: onboarded, onChanged: (d) => emitted = d),
      );

      // Another community offered by the same religion.
      final other = ProfileOptions.communitiesFor(
        'Hindu',
      ).firstWhere((c) => c != 'Nadar');
      await choose(tester, other);

      expect(emitted?.community, other);
      expect(emitted?.communityCode, isEmpty);
      // The religion did not change, so its code stands.
      expect(emitted?.religionCode, 'REL_HINDU');
    });
  });

  group('cascading behaviour is preserved', () {
    testWidgets('changing religion still clears an invalid community', (
      tester,
    ) async {
      ReligionDetails? emitted;
      await pump(
        tester,
        StepReligion(
          details: const ReligionDetails(
            religion: 'Hindu',
            community: 'Nadar',
            subCaste: 'Vadama',
          ),
          onChanged: (d) => emitted = d,
        ),
      );

      await choose(tester, 'Jain');

      expect(emitted?.community, isEmpty);
      expect(emitted?.subCaste, isEmpty);
    });
  });

  group('serialization round trip', () {
    test('codes survive toJson -> fromJson', () {
      final restored = ReligionDetails.fromJson(onboarded.toJson());

      expect(restored.religionCode, 'REL_HINDU');
      expect(restored.communityCode, 'COM_NADAR');
      expect(restored.religion, 'Hindu');
      expect(restored.community, 'Nadar');
    });

    test('empty codes are omitted, not sent as empty strings', () {
      const noCodes = ReligionDetails(religion: 'Hindu', community: 'Nadar');
      final json = noCodes.toJson();

      // The backend reads "absent" as "no structured religion" and keeps
      // using the free text — an empty string is not the same signal.
      expect(json.containsKey('religionCode'), isFalse);
      expect(json.containsKey('communityCode'), isFalse);
    });
  });

  group('canonical option consistency', () {
    test('this step offers ProfileOptions religions, which carry no codes', () {
      // Pins why the codes must be carried rather than re-derived here:
      // the canonical list is labels only.
      expect(ProfileOptions.religions, contains('Hindu'));
      expect(ProfileOptions.communitiesFor('Hindu'), isNotEmpty);
    });
  });
}
