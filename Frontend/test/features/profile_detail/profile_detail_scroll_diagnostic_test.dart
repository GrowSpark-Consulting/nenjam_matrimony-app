import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/compatibility_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/partner_preference_card.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/photo_gallery_card.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/pages/profile_detail_page.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/about_section.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/family_info_section.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/horoscope_section.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/lifestyle_section.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/profile_detail_bottom_action_bar.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/profile_detail_section_tab_bar.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/similar_profiles_section.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/timeline_section.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/verification_trust_section.dart';
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
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // InkWell's default splash is InkSparkle, which loads
        // shaders/ink_sparkle.frag at paint time. That asset is not bundled
        // into the widget-test asset manifest, so every tab tap threw a
        // "Unable to load asset" error before the assertion under test could
        // run. None of these tests are about splash rendering.
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
        ),
        home: ProfileDetailPage(profile: _buildProfile()),
      ),
    ),
  );

  // Let the FutureProvider (350ms mock delay) resolve.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Bounded replacement for `pumpAndSettle`.
///
/// `pumpAndSettle` waits for the frame queue to drain, which never happens
/// while any repeating animation is alive — that is what turned four of these
/// tests into 10-minute harness timeouts. A fixed number of frames advances
/// every animation these tests care about (the longest is the 350ms
/// `Scrollable.ensureVisible` a tab tap kicks off) and can never hang.
Future<void> _settle(WidgetTester tester, {int frames = 16}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// True when [finder] matches at least one widget *and* that widget's rect
/// actually intersects the viewport.
///
/// `find.text(...)` alone only proves a widget is mounted in the element
/// tree, which is a different question from "the user can see it" — the
/// distinction these tests kept getting wrong.
bool isVisible(WidgetTester tester, Finder finder) {
  if (!tester.any(finder)) return false;
  final rect = tester.getRect(finder.first);
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  return rect.bottom > 0 &&
      rect.top < size.height &&
      rect.right > 0 &&
      rect.left < size.width;
}

ScrollableState _mainScrollable(WidgetTester tester) {
  return tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
}

/// The tab bar's *own* horizontal Scrollable, as opposed to the page's
/// vertical one.
Finder _tabBarScrollable() => find.descendant(
      of: find.byType(ProfileDetailSectionTabBar),
      matching: find.byType(Scrollable),
    );

/// A tab label, scoped to the tab bar.
///
/// Several section headings reuse the very same l10n string as their tab
/// (`LifestyleSection` renders `profileDetailTabLifestyle` as its title), so a
/// bare `find.text('Lifestyle')` matches the tab *and* the heading. Every tab
/// lookup here is scoped to the tab bar so it can only ever mean the tab.
Finder _tabLabel(String label) => find.descendant(
      of: find.byType(ProfileDetailSectionTabBar),
      matching: find.text(label),
    );

Future<void> _dragPage(WidgetTester tester, double dy) async {
  await tester.drag(
    find.byType(CustomScrollView).first,
    Offset(0, dy),
    warnIfMissed: false,
  );
  await tester.pump(const Duration(milliseconds: 200));
}

/// Drags the page down in bounded steps until it reaches `maxScrollExtent`.
/// Returns whether the true bottom was actually reached.
Future<bool> _scrollToBottom(WidgetTester tester, {int maxDrags = 40}) async {
  final position = _mainScrollable(tester).position;
  for (var i = 0; i < maxDrags; i++) {
    if ((position.pixels - position.maxScrollExtent).abs() < 1.0) return true;
    await _dragPage(tester, -400);
  }
  await _settle(tester);
  return (position.pixels - position.maxScrollExtent).abs() < 1.0;
}

/// Scrolls the tab bar horizontally until [label] is both built and on
/// screen, then returns its finder.
///
/// The tab bar is a lazy horizontal `ListView.separated`: at 375px only the
/// first few tabs are ever built, so `Horoscope`/`Preferences`/`Verification`/
/// `Timeline` matched zero widgets. They are not stale labels — they simply
/// had not been created yet. `tester.ensureVisible` cannot help here, because
/// it needs an element that already exists.
/// Note the tab must end up *fully* on screen, not merely intersecting the
/// viewport: `tester.tap` aims at a widget's centre, and a tab hanging off
/// the right edge has its centre outside the 375px screen, so the tap lands
/// on nothing and silently does nothing.
Future<Finder> _revealTab(WidgetTester tester, String label) async {
  final target = _tabLabel(label);
  final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;

  bool fullyOnScreen() {
    if (!tester.any(target)) return false;
    final r = tester.getRect(target.first);
    return r.left >= 0 && r.right <= viewport.width;
  }

  for (var i = 0; i < 30; i++) {
    if (fullyOnScreen()) break;
    await tester.drag(_tabBarScrollable(), const Offset(-60, 0),
        warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
  }
  // findsWidgets before any .first access — an empty finder would otherwise
  // blow up as "Bad state: No element" inside the matcher's mismatch
  // description, hiding the real reason.
  expect(
    target,
    findsWidgets,
    reason: 'tab "$label" was never built, even after scrolling the tab bar '
        'horizontally 30 times',
  );
  expect(
    fullyOnScreen(),
    isTrue,
    reason: 'tab "$label" never became fully visible '
        '(rect=${tester.getRect(target.first)}, viewport width '
        '${viewport.width}) — a tap would land off screen',
  );
  return target;
}

void main() {
  group('Scroll completeness', () {
    testWidgets('reaches the true bottom of content (maxScrollExtent) on a small screen',
        (tester) async {
      await _pumpPage(tester, const Size(320, 568));
      expect(tester.takeException(), isNull, reason: 'no layout exceptions on initial render');

      final reachedBottom = await _scrollToBottom(tester);
      expect(tester.takeException(), isNull, reason: 'no layout exceptions while scrolling');

      final position = _mainScrollable(tester).position;
      expect(
        reachedBottom,
        isTrue,
        reason: 'scroll stopped at ${position.pixels} instead of reaching its '
            'true maxScrollExtent of ${position.maxScrollExtent}',
      );
      expect(find.byType(SimilarProfilesSection), findsOneWidget);
    });

    testWidgets('every documented profile section is reachable during a full scroll',
        (tester) async {
      await _pumpPage(tester, const Size(375, 812));

      // Targeted by widget type, not heading text. The sections live in a
      // SliverList, so only the ones near the viewport are mounted at any
      // moment — "present after a full scroll" is unsatisfiable at the
      // bottom. What matters is that each one appears at some point on the
      // way down, so they are recorded as the page scrolls past them.
      final sections = <String, Finder>{
        'About': find.byType(AboutSection),
        'Photo Gallery': find.byType(NmPhotoGalleryCard),
        'Family Information': find.byType(FamilyInfoSection),
        'Lifestyle': find.byType(LifestyleSection),
        'Horoscope': find.byType(HoroscopeSection),
        'Partner Preferences': find.byType(NmPartnerPreferenceCard),
        'Verification': find.byType(VerificationTrustSection),
        'Timeline': find.byType(TimelineSection),
        'Similar Profiles': find.byType(SimilarProfilesSection),
      };

      final seen = <String>{};
      void record() {
        sections.forEach((name, finder) {
          if (tester.any(finder)) seen.add(name);
        });
      }

      final position = _mainScrollable(tester).position;
      record();
      for (var i = 0; i < 40; i++) {
        if ((position.pixels - position.maxScrollExtent).abs() < 1.0) break;
        await _dragPage(tester, -400);
        record();
      }
      await _settle(tester);
      record();

      expect(tester.takeException(), isNull);
      final missing = sections.keys.where((k) => !seen.contains(k)).toList();
      expect(
        missing,
        isEmpty,
        reason: 'these sections never appeared during a full scroll: $missing',
      );
    });
  });

  group('Nested scroll / gesture conflicts', () {
    testWidgets('a vertical drag started ON the pinned tab bar still scrolls the page',
        (tester) async {
      await _pumpPage(tester, const Size(375, 812));

      // The "Lifestyle" *tab* is on screen from the start; the Lifestyle
      // *section* is far below the fold. Asserting on the section's widget
      // type keeps those two apart.
      expect(
        isVisible(tester, _tabLabel('Lifestyle')),
        isTrue,
        reason: 'the Lifestyle tab should be visible in the tab bar at rest',
      );
      expect(
        isVisible(tester, find.byType(LifestyleSection)),
        isFalse,
        reason: 'the Lifestyle section should not be in view before scrolling',
      );

      final position = _mainScrollable(tester).position;
      expect(position.pixels, 0.0, reason: 'page starts at the top');

      final tabBarCenter = tester.getCenter(find.byType(ProfileDetailSectionTabBar));
      await tester.timedDragFrom(
        tabBarCenter,
        const Offset(0, -300),
        const Duration(milliseconds: 300),
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);

      // The question this test exists to answer is whether the gesture reaches
      // the page at all. Asserting on the *offset* rather than on which
      // section happens to land in view keeps it independent of fling
      // momentum — a drag large enough to guarantee Lifestyle is reached also
      // carries far enough to sail straight past it.
      expect(
        position.pixels,
        greaterThan(100.0),
        reason: 'the horizontal tab-bar ListView must not swallow a vertical '
            'drag meant for the page',
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

      await _scrollToBottom(tester);

      // Pinned slivers must still be painted (not scrolled fully offscreen)
      // once we're at the very bottom of the list.
      expect(find.byType(ProfileDetailSectionTabBar), findsOneWidget);
      final tabBarRect = tester.getRect(find.byType(ProfileDetailSectionTabBar));
      expect(tabBarRect.top, greaterThanOrEqualTo(0));
      expect(tabBarRect.top, lessThan(200), reason: 'tab bar should be pinned near the top');
    });
  });

  group('Tab-tap scrollspy', () {
    // Tab label -> the section widget that tab scrolls to. Labels are read
    // from the live UI (`_ProfileDetailScrollViewState._tabLabels`); all
    // eight still exist.
    final tabsAndSections = <String, Finder>{
      'About': find.byType(AboutSection),
      'Photos': find.byType(NmPhotoGalleryCard),
      'Family': find.byType(FamilyInfoSection),
      'Lifestyle': find.byType(LifestyleSection),
      'Horoscope': find.byType(HoroscopeSection),
      'Preferences': find.byType(NmPartnerPreferenceCard),
      'Verification': find.byType(VerificationTrustSection),
      'Timeline': find.byType(TimelineSection),
    };

    for (final entry in tabsAndSections.entries) {
      testWidgets('tapping the "${entry.key}" tab brings its section into view',
          (tester) async {
        await _pumpPage(tester, const Size(375, 812));

        final tab = await _revealTab(tester, entry.key);
        await tester.tap(tab.first);
        // 350ms section ensureVisible + 250ms tab reveal, with headroom.
        await _settle(tester, frames: 24);
        expect(tester.takeException(), isNull);

        expect(
          tester.any(entry.value),
          isTrue,
          reason: 'tapping "${entry.key}" should have built its section',
        );
        expect(
          isVisible(tester, entry.value),
          isTrue,
          reason: 'the "${entry.key}" section should have scrolled into the viewport',
        );
      });
    }
  });

  group('Bottom action bar', () {
    testWidgets('does not cover the last section once scrolled to the bottom', (tester) async {
      await _pumpPage(tester, const Size(375, 812));

      await _scrollToBottom(tester);

      expect(find.byType(ProfileDetailBottomActionBar), findsOneWidget);
      expect(find.byType(SimilarProfilesSection), findsOneWidget);

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

      await _scrollToBottom(tester);

      expect(
        tester.takeException(),
        isNull,
        reason: 'no RenderFlex overflow anywhere in the page at 320px width',
      );
    });
  });
}
