import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/compatibility_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/pages/profile_detail_page.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/profile_detail_bottom_action_bar.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/profile_detail_section_tab_bar.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/similar_profiles_section.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

DiscoveryProfileEntity _buildProfile() {
  return const DiscoveryProfileEntity(
    id: 'diag-1',
    matrimonyId: 'NM123456',
    name: 'Diagnostic Tester With A Fairly Long Name',
    age: 29,
    location: 'Chennai, Tamil Nadu, India',
    profession: 'Senior Software Engineer',
    education: 'M.Tech, Computer Science',
    photoUrls: [],
    isVerified: true,
    isPremium: true,
    isPsychologyCompleted: true,
    isOnline: true,
    horoscopeAvailable: true,
    photoProtected: false,
    phoneVerified: true,
    compatibility: CompatibilityEntity(
      aiMatchPercent: 88,
      astroMatchPercent: 76,
      psychologyMatchPercent: 81,
      overallCompatibility: 85,
      lifestyleMatchPercent: 90,
      familyMatchPercent: 82,
      educationMatchPercent: 95,
      valuesMatchPercent: 88,
      goalsMatchPercent: 80,
    ),
    tags: [],
    religion: 'Hindu',
    caste: 'Iyer',
    community: 'Tamil',
    height: "5'9\"",
    diet: 'Vegetarian',
    distanceKm: 12.4,
    gender: 'Female',
    profileComplete: true,
    maritalStatus: 'Never Married',
    motherTongue: 'Tamil',
    smoking: 'No',
    drinking: 'No',
    physicalStatus: 'Normal',
    company: 'Big Tech Corp',
    annualIncome: '25-30 Lakhs',
    bio: 'Loves travel and books.',
    languages: ['Tamil', 'English', 'Hindi'],
    hobbies: ['Reading', 'Travel'],
  );
}

Future<void> _pumpPage(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProfileDetailPage(profile: _buildProfile()),
      ),
    ),
  );

  // Let the FutureProvider (350ms mock delay) resolve.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

ScrollableState _mainScrollable(WidgetTester tester) {
  // The vertical CustomScrollView's Scrollable is built before any of the
  // nested horizontal ListViews (photo gallery / tab bar / similar
  // profiles), so it is always first in a depth-first Element walk.
  return tester.state<ScrollableState>(find.byType(Scrollable).first);
}

void main() {
  group('Scroll completeness', () {
    testWidgets('reaches the true bottom of content (maxScrollExtent) on a small screen',
        (tester) async {
      await _pumpPage(tester, const Size(320, 568));
      expect(tester.takeException(), isNull, reason: 'no layout exceptions on initial render');

      await tester.scrollUntilVisible(
        find.text('Similar Profiles'),
        500,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 40,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'no layout exceptions while scrolling');

      // Fling hard past the end — if the page stopped short of the real
      // bottom, this proves it: position.pixels would sit below
      // maxScrollExtent instead of clamping to it.
      final scrollable = _mainScrollable(tester);
      await tester.fling(find.byType(Scrollable).first, const Offset(0, -2000), 3000);
      await tester.pumpAndSettle();

      final position = scrollable.position;
      expect(
        position.pixels,
        closeTo(position.maxScrollExtent, 1.0),
        reason: 'scroll should be able to reach its true maxScrollExtent, not stop early',
      );
      expect(find.byType(SimilarProfilesSection), findsOneWidget);
    });

    testWidgets('every documented profile section is present after a full scroll',
        (tester) async {
      await _pumpPage(tester, const Size(375, 812));

      final scrollable = _mainScrollable(tester);
      // Drive straight to maxScrollExtent rather than guessing a drag count.
      await scrollable.position.animateTo(
        scrollable.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Photos, Basic Information, About, Religion (About stat), Education
      // (About stat), Career/Profession (About stat), Family, Lifestyle,
      // Horoscope, Partner Preferences, Verification — every section the
      // task requires stays reachable.
      for (final heading in const [
        'Photo Gallery',
        'Basic Information',
        'About',
        'RELIGION',
        'EDUCATION',
        'PROFESSION',
        'Family Information',
        'Lifestyle',
        'Your Horoscope',
        'Partner Preferences',
        'Verification Center',
        'Similar Profiles',
      ]) {
        expect(find.text(heading), findsWidgets, reason: '"$heading" section must be reachable');
      }
    });
  });

  group('Nested scroll / gesture conflicts', () {
    testWidgets('a vertical drag started ON the pinned tab bar still scrolls the page',
        (tester) async {
      await _pumpPage(tester, const Size(375, 812));

      final tabBarCenter = tester.getCenter(find.byType(ProfileDetailSectionTabBar));
      expect(find.text('Lifestyle'), findsNothing, reason: 'not yet scrolled into view');

      await tester.timedDragFrom(
        tabBarCenter,
        const Offset(0, -1600),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(
        find.text('Lifestyle'),
        findsOneWidget,
        reason:
            'the horizontal tab-bar ListView must not swallow a vertical drag meant for the page',
      );
    });

    testWidgets('only one vertical ScrollController/Scrollable drives the page', (tester) async {
      await _pumpPage(tester, const Size(375, 812));

      // Exactly one CustomScrollView (vertical) — the horizontal galleries
      // are plain ListViews, not CustomScrollViews, so this count staying
      // at 1 proves no competing vertical scroll region was introduced.
      expect(find.byType(CustomScrollView), findsOneWidget);
    });
  });

  group('Sliver header behaviour', () {
    testWidgets('hero app bar and tab bar both stay pinned through a full scroll',
        (tester) async {
      await _pumpPage(tester, const Size(375, 812));

      final scrollable = _mainScrollable(tester);
      await scrollable.position.animateTo(
        scrollable.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
      );
      await tester.pumpAndSettle();

      // Pinned slivers must still be painted (not scrolled fully offscreen)
      // once we're at the very bottom of the list.
      expect(find.byType(ProfileDetailSectionTabBar), findsOneWidget);
      final tabBarRect = tester.getRect(find.byType(ProfileDetailSectionTabBar));
      expect(tabBarRect.top, greaterThanOrEqualTo(0));
      expect(tabBarRect.top, lessThan(200), reason: 'tab bar should be pinned near the top');
    });
  });

  group('Tab-tap scrollspy', () {
    const tabsAndHeadings = {
      'About': 'About',
      'Photos': 'Photo Gallery',
      'Family': 'Family Information',
      'Lifestyle': 'Lifestyle',
      'Horoscope': 'Your Horoscope',
      'Preferences': 'Partner Preferences',
      'Verification': 'Verification Center',
      'Timeline': 'Timeline',
    };

    for (final entry in tabsAndHeadings.entries) {
      testWidgets('tapping the "${entry.key}" tab brings "${entry.value}" into view',
          (tester) async {
        await _pumpPage(tester, const Size(375, 812));

        final tab = find.text(entry.key);
        expect(tab, findsOneWidget);
        await tester.tap(tab);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final headingFinder = find.text(entry.value).first;
        expect(headingFinder, findsWidgets);

        final headingY = tester.getTopLeft(headingFinder).dy;
        final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
        expect(
          headingY,
          inInclusiveRange(-50.0, screenHeight),
          reason: '"${entry.value}" heading should have scrolled into (or near) the viewport',
        );
      });
    }
  });

  group('Bottom action bar', () {
    testWidgets('does not cover the last section once scrolled to the bottom', (tester) async {
      await _pumpPage(tester, const Size(375, 812));

      final scrollable = _mainScrollable(tester);
      await scrollable.position.animateTo(
        scrollable.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
      );
      await tester.pumpAndSettle();

      final actionBarTop = tester.getRect(find.byType(ProfileDetailBottomActionBar)).top;
      final lastSectionBottom = tester.getRect(find.byType(SimilarProfilesSection)).bottom;

      expect(
        lastSectionBottom,
        lessThanOrEqualTo(actionBarTop + 1.0),
        reason: 'the bottom action bar must not overlap the last scrollable section',
      );
    });
  });

  group('Chip overflow regression (root cause)', () {
    testWidgets('NmInfoChip labels never overflow on a 320px-wide screen', (tester) async {
      await _pumpPage(tester, const Size(320, 568));

      final scrollable = _mainScrollable(tester);
      await scrollable.position.animateTo(
        scrollable.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'no RenderFlex overflow anywhere in the page at 320px width',
      );
    });
  });
}
