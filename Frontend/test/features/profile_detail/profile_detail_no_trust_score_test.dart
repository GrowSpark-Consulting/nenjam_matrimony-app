import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/compatibility_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/pages/profile_detail_page.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/profile_detail_section_tab_bar.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/similar_profiles_section.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/verification_section.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Trust Score was removed from the app entirely. The verification
/// checklist — a different feature — stays, so these tests assert the score
/// headline and every piece of trust copy is gone *without* taking the
/// checklist with it.
DiscoveryProfileEntity _profile() => const DiscoveryProfileEntity(
      photoUrls: [],
      id: 'trust-1',
      matrimonyId: 'NM777001',
      name: 'Verification Tester',
      age: 30,
      location: 'Coimbatore, Tamil Nadu',
      profession: 'Architect',
      education: 'B.Arch',
      isVerified: true,
      isPremium: false,
      phoneVerified: true,
      horoscopeAvailable: true,
      compatibility: CompatibilityEntity(
        aiMatchPercent: 84,
        astroMatchPercent: 72,
        overallCompatibility: 88,
      ),
      religion: 'Hindu',
      caste: 'Iyer',
      community: 'Tamil',
      height: "5'6\"",
    );

Future<void> _pumpDetailPage(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
        ),
        home: ProfileDetailPage(profile: _profile()),
      ),
    ),
  );

  // Let the FutureProvider's 350ms mock delay resolve.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Every `Text` currently in the tree, including off-screen slivers that
/// have been built but not painted.
Iterable<String> _renderedText(WidgetTester tester) sync* {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final data = text.data;
    if (data != null) yield data;
  }
}

void main() {
  group('profile detail has no Trust Score', () {
    testWidgets('no trust copy anywhere on the page, at any scroll offset',
        (tester) async {
      await _pumpDetailPage(tester);

      final scrollable = find.byType(Scrollable).first;
      // Walk the whole page so lazily-built sections are inspected too.
      for (var i = 0; i < 20; i++) {
        for (final label in _renderedText(tester)) {
          expect(
            label.toLowerCase(),
            isNot(contains('trust')),
            reason: 'found trust copy "$label" on the profile detail page',
          );
          expect(
            label.toLowerCase(),
            isNot(contains('credibility')),
            reason: 'found trust-score credibility copy "$label"',
          );
        }
        await tester.drag(scrollable, const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 120));
      }

      expect(tester.takeException(), isNull);
      // The scroll actually made it to the end of the page, so the sweep
      // above really did cover every section rather than stalling early.
      expect(find.byType(SimilarProfilesSection), findsOneWidget);
    });

    testWidgets('the section tab bar exposes no Trust destination',
        (tester) async {
      await _pumpDetailPage(tester);

      // The tab bar is a pinned sliver below the hero, so it is not built
      // until the page has been scrolled down to it.
      final scrollable = find.byType(Scrollable).first;
      for (var i = 0;
          i < 20 && !tester.any(find.byType(ProfileDetailSectionTabBar));
          i++) {
        await tester.drag(scrollable, const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 120));
      }

      final tabBar = tester.widget<ProfileDetailSectionTabBar>(
        find.byType(ProfileDetailSectionTabBar),
      );

      for (final label in tabBar.labels) {
        expect(label.toLowerCase(), isNot(contains('trust')));
      }
      // Verification is still a destination, and every tab still has a
      // section key behind it — no hole was left in the index mapping.
      expect(tabBar.labels, contains('Verification'));
      expect(tabBar.itemKeys.length, tabBar.labels.length);
    });

    testWidgets('the verification checklist survives the removal',
        (tester) async {
      await _pumpDetailPage(tester);

      final scrollable = find.byType(Scrollable).first;
      var found = false;
      for (var i = 0; i < 20 && !found; i++) {
        found = tester.any(find.byType(VerificationSection));
        await tester.drag(scrollable, const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 120));
      }

      expect(found, isTrue,
          reason: 'VerificationSection should still render on the page');
    });
  });
}
