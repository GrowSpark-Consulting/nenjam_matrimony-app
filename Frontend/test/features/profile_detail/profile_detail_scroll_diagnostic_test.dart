import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/widgets/avatars/gender_placeholder.dart';
import 'package:nenjam_matrimony/core/widgets/cards/profile_hero_content.dart';
import 'package:nenjam_matrimony/core/widgets/images/sized_network_photo.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/compatibility_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/partner_preference_card.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/pages/profile_detail_page.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/about_section.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/basic_information_section.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/compatibility_card_section.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/family_info_section.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/horoscope_section.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/lifestyle_section.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/profile_detail_bottom_action_bar.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/profile_detail_section_tab_bar.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/profile_detail_hero_app_bar.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/profile_photo_gallery_section.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/similar_profiles_section.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/verification_section.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

DiscoveryProfileEntity _buildProfile({List<String> photoUrls = const []}) {
  return DiscoveryProfileEntity(
    photoUrls: photoUrls,
    id: 'diag-1',
    matrimonyId: 'NM123456',
    name: 'Diagnostic Tester With A Fairly Long Name',
    age: 29,
    location: 'Chennai, Tamil Nadu, India',
    profession: 'Senior Software Engineer',
    education: 'M.Tech, Computer Science',
    isVerified: true,
    isPremium: true,
    isPsychologyCompleted: true,
    isOnline: true,
    horoscopeAvailable: true,
    photoProtected: false,
    phoneVerified: true,
    compatibility: const CompatibilityEntity(
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
    tags: const [],
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
    languages: const ['Tamil', 'English', 'Hindi'],
    hobbies: const ['Reading', 'Travel'],
  );
}

/// A profile whose field *lengths* match a realistic one, for the tests that
/// measure how the hero chips wrap.
///
/// `_buildProfile()` deliberately carries oversized strings to stress
/// overflow handling, and widget tests render with a fallback font whose
/// glyphs are square — far wider than the Inter face the app ships — so
/// counting wrapped rows with those values measures the test font, not the
/// layout. These values mirror the design reference.
DiscoveryProfileEntity _buildTypicalProfile({List<String> photoUrls = const []}) {
  final base = _buildProfile(photoUrls: photoUrls);
  return DiscoveryProfileEntity(
    id: base.id,
    matrimonyId: base.matrimonyId,
    name: 'Raja Vijayan',
    age: 22,
    location: 'Chennai, Tamil Nadu',
    profession: 'Software Engineer',
    education: 'B.E/B.Tech',
    photoUrls: photoUrls,
    isVerified: base.isVerified,
    compatibility: base.compatibility,
    religion: 'Hindu',
    caste: base.caste,
    community: 'Tamil',
    height: "5'3\"",
    gender: base.gender,
    maritalStatus: base.maritalStatus,
    motherTongue: 'Tamil',
    bio: base.bio,
  );
}

/// A name/age override for the long-name case, leaving every other field of
/// the profile alone.
extension on DiscoveryProfileEntity {
  DiscoveryProfileEntity copyName(String newName, int newAge) {
    return DiscoveryProfileEntity(
      id: id,
      matrimonyId: matrimonyId,
      name: newName,
      age: newAge,
      location: location,
      profession: profession,
      education: education,
      photoUrls: photoUrls,
      isVerified: isVerified,
      compatibility: compatibility,
      religion: religion,
      caste: caste,
      community: community,
      height: height,
      gender: gender,
      maritalStatus: maritalStatus,
      motherTongue: motherTongue,
      bio: bio,
    );
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  Size size, {
  List<String> photoUrls = const [],
  DiscoveryProfileEntity? profile,
}) async {
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
        home: ProfileDetailPage(
          profile: profile ?? _buildProfile(photoUrls: photoUrls),
        ),
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

/// Scrolls down until the section navigation has been reached and pinned.
///
/// It now lives *below* the photo gallery instead of directly under the hero,
/// so unlike before it is not built at all when the page is at rest — every
/// test that needs to touch it has to bring it into view first.
Future<void> _revealTabBar(WidgetTester tester, {int maxDrags = 20}) async {
  for (var i = 0; i < maxDrags; i++) {
    if (isVisible(tester, find.byType(ProfileDetailSectionTabBar))) return;
    await _dragPage(tester, -300);
  }
}

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
  await _revealTabBar(tester);
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
        'Basic Information': find.byType(BasicInformationSection),
        'Photo Gallery': find.byType(ProfilePhotoGallerySection),
        'Family Information': find.byType(FamilyInfoSection),
        'Lifestyle': find.byType(LifestyleSection),
        'Horoscope': find.byType(HoroscopeSection),
        'Compatibility': find.byType(CompatibilityCardSection),
        'Partner Preferences': find.byType(NmPartnerPreferenceCard),
        'Verification': find.byType(VerificationSection),
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
      await _revealTabBar(tester);

      // The "Lifestyle" *tab* is on screen once the navigation is reached;
      // the Lifestyle *section* is still below the fold. Asserting on the
      // section's widget type keeps those two apart.
      expect(
        isVisible(tester, _tabLabel('Lifestyle')),
        isTrue,
        reason: 'the Lifestyle tab should be visible once the navigation is '
            'pinned',
      );
      expect(
        isVisible(tester, find.byType(LifestyleSection)),
        isFalse,
        reason: 'the Lifestyle section should not be in view before scrolling',
      );

      final position = _mainScrollable(tester).position;
      final startPixels = position.pixels;

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
        greaterThan(startPixels + 100.0),
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
      // Settle first: the hero toolbar now collapses to zero height, so the
      // tab bar pins at the very top of the viewport rather than 56px down,
      // and a ballistic frame still in flight reads as a small negative top.
      await _settle(tester);

      // Pinned slivers must still be painted (not scrolled fully offscreen)
      // once we are at the very bottom of the list.
      expect(find.byType(ProfileDetailSectionTabBar), findsOneWidget);
      final tabBarRect = tester.getRect(find.byType(ProfileDetailSectionTabBar));
      expect(tabBarRect.top, greaterThanOrEqualTo(-0.5));
      expect(tabBarRect.top, lessThan(200), reason: 'tab bar should be pinned near the top');
    });
  });

  group('Tab-tap scrollspy', () {
    // Tab label -> the section widget that tab scrolls to. Labels are read
    // from the live UI (`_ProfileDetailScrollViewState._tabLabels`) — only
    // the six sections that live *below* the navigation are addressable by
    // it; About and Photos now sit above it and are reached by scrolling.
    final tabsAndSections = <String, Finder>{
      'Family': find.byType(FamilyInfoSection),
      'Lifestyle': find.byType(LifestyleSection),
      'Horoscope': find.byType(HoroscopeSection),
      'Compatibility': find.byType(CompatibilityCardSection),
      'Preferences': find.byType(NmPartnerPreferenceCard),
      'Verification': find.byType(VerificationSection),
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

  group('Full-screen photo hero', () {
    final photos = [
      for (var i = 0; i < 9; i++) 'https://example.invalid/photo-$i.jpg',
    ];

    const sizes = <String, Size>{
      'small phone': Size(320, 568),
      'normal phone': Size(375, 812),
      'large phone': Size(430, 932),
    };

    sizes.forEach((label, size) {
      testWidgets('fills the first viewport on a $label', (tester) async {
        await _pumpPage(tester, size, photoUrls: photos);

        final heroRect = tester.getRect(find.byType(FlexibleSpaceBar));
        expect(
          heroRect.height,
          greaterThan(size.height * 0.7),
          reason: 'the photo hero should own essentially the whole first '
              'viewport at $label, not a fraction of it',
        );
        expect(heroRect.width, closeTo(size.width, 1.0),
            reason: 'the hero must be full-bleed horizontally');
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('is built from the shared Matches profile presentation',
        (tester) async {
      await _pumpPage(tester, const Size(375, 812), photoUrls: photos);

      // The point of the extraction: Profile Detail must render the photo,
      // scrim and identity block with the very widgets the Matches reel card
      // uses, so the two screens cannot drift apart. Asserting on the widget
      // types is what makes a divergent re-implementation fail here.
      final hero = find.byType(ProfileDetailHeroAppBar);
      expect(
        find.descendant(of: hero, matching: find.byType(NmProfileHeroPhoto)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hero, matching: find.byType(NmProfileHeroScrim)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hero, matching: find.byType(NmProfileHeroInfo)),
        findsOneWidget,
      );
      // Including the positioning strategy, not just the block: the overlay
      // is what sets the block width and its offset from the bottom.
      expect(
        find.descendant(of: hero, matching: find.byType(NmProfileHeroOverlay)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('feeds the shared info block the profile it is showing',
        (tester) async {
      final profile = _buildTypicalProfile(photoUrls: photos);
      await _pumpPage(tester, const Size(375, 812), profile: profile);

      final info = tester.widget<NmProfileHeroInfo>(
        find
            .descendant(
              of: find.byType(ProfileDetailHeroAppBar),
              matching: find.byType(NmProfileHeroInfo),
            )
            .first,
      );
      expect(info.profile.id, profile.id);
      expect(info.profile.name, 'Raja Vijayan');

      // And it renders that data, rather than the block being present but
      // fed something else.
      final hero = find.byType(ProfileDetailHeroAppBar);
      expect(
        find.descendant(of: hero, matching: find.text('Raja Vijayan, 22')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hero, matching: find.text('Software Engineer')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hero, matching: find.text('Chennai, Tamil Nadu')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the primary photo full-bleed with the shared crop',
        (tester) async {
      await _pumpPage(tester, const Size(375, 812), photoUrls: photos);

      final photo = tester.widget<NmSizedNetworkPhoto>(
        find
            .descendant(
              of: find.byType(ProfileDetailHeroAppBar),
              matching: find.byType(NmSizedNetworkPhoto),
            )
            .first,
      );
      expect(photo.url, photos.first);
      // Whatever the shared component chooses, this screen must not override
      // it with a crop of its own.
      expect(photo.fit, BoxFit.cover);
      expect(photo.alignment, Alignment.center);
      expect(tester.takeException(), isNull);
    });

    testWidgets('borrows none of the Matches action controls', (tester) async {
      await _pumpPage(tester, const Size(375, 812), photoUrls: photos);

      final hero = find.byType(ProfileDetailHeroAppBar);

      // Matches' right-hand action column, and the hero's own former
      // back/bookmark/share/more cluster.
      for (final icon in const [
        Icons.arrow_back_rounded,
        Icons.bookmark_rounded,
        Icons.bookmark_border_rounded,
        Icons.ios_share_rounded,
        Icons.more_vert_rounded,
        Icons.favorite_rounded,
      ]) {
        expect(
          find.descendant(of: hero, matching: find.byIcon(icon)),
          findsNothing,
          reason: 'the hero must not draw any action controls',
        );
      }
      expect(
        find.descendant(of: hero, matching: find.byType(InkWell)),
        findsNothing,
        reason: 'no button placeholders should remain in the hero',
      );
      expect(tester.takeException(), isNull);
    });

    sizes.forEach((label, size) {
      testWidgets('lays the identity block out without overflow on a $label',
          (tester) async {
        await _pumpPage(
          tester,
          size,
          profile: _buildTypicalProfile(photoUrls: photos),
        );

        final infoRect = tester.getRect(
          find
              .descendant(
                of: find.byType(ProfileDetailHeroAppBar),
                matching: find.byType(NmProfileHeroInfo),
              )
              .first,
        );
        expect(infoRect.left, greaterThanOrEqualTo(0.0));
        expect(infoRect.right, lessThanOrEqualTo(size.width));
        expect(
          infoRect.bottom,
          lessThanOrEqualTo(size.height),
          reason: 'the identity block ran off the bottom at $label',
        );
        // Same bottom gap the reel card leaves (plus the device inset,
        // which is zero in tests) but the FULL width: the reel's 80px
        // right-hand gutter exists for its action column, and there is no
        // action column here.
        expect(
          size.height - infoRect.bottom,
          closeTo(NmProfileHeroOverlay.bottomGap, 1.0),
        );
        expect(
          size.width - infoRect.right,
          closeTo(16.0, 1.0),
          reason: 'Profile Detail must not reserve the action-column gutter',
        );
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('shows a long name in full rather than ellipsizing',
        (tester) async {
      // The reel card ellipsizes a long name to keep its card tidy; on the
      // screen devoted to one person that is not acceptable.
      final longName = _buildTypicalProfile(photoUrls: photos).copyName(
        'Aravind Krishnamoorthy',
        25,
      );
      await _pumpPage(tester, const Size(375, 812), profile: longName);

      final hero = find.byType(ProfileDetailHeroAppBar);
      final nameFinder =
          find.descendant(of: hero, matching: find.text('Aravind Krishnamoorthy, 25'));
      expect(
        nameFinder,
        findsOneWidget,
        reason: 'the whole name must be rendered, not a truncation of it',
      );

      final name = tester.widget<Text>(nameFinder.first);
      expect(
        name.maxLines,
        greaterThanOrEqualTo(2),
        reason: 'a long name must be allowed to wrap rather than truncate',
      );

      // And the rendered text must not have been visually truncated.
      final painted = tester.renderObject<RenderParagraph>(nameFinder.first);
      expect(
        painted.didExceedMaxLines,
        isFalse,
        reason: 'the name was clipped to its maxLines and shows an ellipsis',
      );
      expect(tester.takeException(), isNull);
    });

    sizes.forEach((label, size) {
      testWidgets('keeps every metadata chip fully on screen at $label',
          (tester) async {
        await _pumpPage(
          tester,
          size,
          profile: _buildTypicalProfile(photoUrls: photos),
        );

        final hero = find.byType(ProfileDetailHeroAppBar);
        // The last chip in priority order is the one that would fall off the
        // bottom if the block were hung from a fixed offset.
        for (final label in const [
          'Chennai, Tamil Nadu',
          "5'3\"",
          'Hindu',
          'Tamil',
          'B.E/B.Tech',
        ]) {
          final finder = find.descendant(of: hero, matching: find.text(label));
          if (!tester.any(finder)) continue;
          final rect = tester.getRect(finder.first);
          expect(rect.bottom, lessThanOrEqualTo(size.height),
              reason: '"$label" is clipped by the bottom edge');
          expect(rect.top, greaterThanOrEqualTo(0.0),
              reason: '"$label" is off the top');
          expect(rect.right, lessThanOrEqualTo(size.width),
              reason: '"$label" runs off the right edge');
        }
        expect(tester.takeException(), isNull);
      });
    });

    // Every other test here runs with zero system insets, which is exactly
    // why the hero could overshoot the viewport unnoticed: SliverAppBar adds
    // the status-bar inset to expandedHeight itself, so the overshoot is
    // invisible when that inset is 0. These pump with a real status bar and
    // navigation bar.
    group('with real system insets', () {
      const topInset = 40.0;
      const bottomInset = 48.0;

      Future<void> pumpInset(WidgetTester tester, Size size) async {
        tester.view.padding = const FakeViewPadding(
          top: topInset,
          bottom: bottomInset,
        );
        addTearDown(tester.view.resetPadding);
        await _pumpPage(
          tester,
          size,
          profile: _buildTypicalProfile(photoUrls: photos),
        );
      }

      sizes.forEach((label, size) {
        testWidgets('the hero is exactly the viewport, never taller, at $label',
            (tester) async {
          await pumpInset(tester, size);

          final heroRect = tester.getRect(find.byType(FlexibleSpaceBar));
          expect(
            heroRect.bottom,
            lessThanOrEqualTo(size.height + 0.5),
            reason: 'the hero box hangs ${heroRect.bottom - size.height}px '
                'below the viewport at $label — anything bottom-aligned in '
                'it is clipped by exactly that much',
          );
          expect(tester.takeException(), isNull);
        });

        testWidgets('no chip is clipped or sits under the navigation bar at '
            '$label', (tester) async {
          await pumpInset(tester, size);

          final hero = find.byType(ProfileDetailHeroAppBar);
          final safeBottom = size.height - bottomInset;
          var checked = 0;
          for (final chip in const [
            'Chennai, Tamil Nadu',
            "5'3\"",
            'Hindu',
            'Tamil',
            'B.E/B.Tech',
          ]) {
            final finder = find.descendant(of: hero, matching: find.text(chip));
            if (!tester.any(finder)) continue;
            checked++;
            final rect = tester.getRect(finder.first);
            expect(
              rect.bottom,
              lessThanOrEqualTo(safeBottom),
              reason: '"$chip" reaches ${rect.bottom}, past the safe-area '
                  'floor of $safeBottom at $label',
            );
          }
          expect(checked, greaterThan(0), reason: 'no chips were rendered');
          expect(tester.takeException(), isNull);
        });
      });

      testWidgets('leaves breathing room under the last chip row',
          (tester) async {
        await pumpInset(tester, const Size(375, 812));

        final infoRect = tester.getRect(
          find
              .descendant(
                of: find.byType(ProfileDetailHeroAppBar),
                matching: find.byType(NmProfileHeroInfo),
              )
              .first,
        );
        // The overlay's own 16px gap, measured from the safe-area floor.
        expect(
          (812.0 - bottomInset) - infoRect.bottom,
          closeTo(NmProfileHeroOverlay.bottomGap, 1.0),
        );
      });
    });

    testWidgets('falls back to the plum placeholder when there is no photo',
        (tester) async {
      await _pumpPage(tester, const Size(375, 812));

      expect(
        find.descendant(
          of: find.byType(ProfileDetailHeroAppBar),
          matching: find.byType(NmGenderPlaceholder),
        ),
        findsOneWidget,
        reason: 'a member with no photo still gets a branded hero',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('About is the first section revealed by a swipe', (tester) async {
      await _pumpPage(tester, const Size(375, 812), photoUrls: photos);

      expect(
        isVisible(tester, find.byType(AboutSection)),
        isFalse,
        reason: 'nothing but the photo should share the first viewport',
      );

      await _dragPage(tester, -812);
      await _settle(tester);

      expect(
        isVisible(tester, find.byType(AboutSection)),
        isTrue,
        reason: 'About should be what the first swipe reveals',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Scroll discovery cue', () {
    final photos = [
      for (var i = 0; i < 9; i++) 'https://example.invalid/photo-$i.jpg',
    ];

    const sizes = <String, Size>{
      'small phone': Size(320, 568),
      'normal phone': Size(375, 812),
      'large phone': Size(430, 932),
    };

    /// The cue stays mounted and fades, so "showing" means opacity, not
    /// presence.
    double cueOpacity(WidgetTester tester) {
      final finder = find.descendant(
        of: find.byType(ProfileDetailHeroAppBar),
        matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
      );
      expect(finder, findsWidgets, reason: 'the chevron cue is not in the tree');
      final opacity = tester.widget<AnimatedOpacity>(
        find
            .ancestor(of: finder.first, matching: find.byType(AnimatedOpacity))
            .first,
      );
      return opacity.opacity;
    }

    testWidgets('is showing while the page is at the top', (tester) async {
      await _pumpPage(tester, const Size(375, 812), photoUrls: photos);
      await _settle(tester);

      expect(cueOpacity(tester), 1.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fades out once the reader scrolls, and stays gone',
        (tester) async {
      await _pumpPage(tester, const Size(375, 812), photoUrls: photos);
      await _settle(tester);
      expect(cueOpacity(tester), 1.0);

      await _dragPage(tester, -60);
      await _settle(tester);
      expect(
        cueOpacity(tester),
        0.0,
        reason: 'the cue has done its job the moment the page moves',
      );

      await _dragPage(tester, -400);
      await _settle(tester);
      expect(cueOpacity(tester), 0.0,
          reason: 'it must not come back mid-profile');
      expect(tester.takeException(), isNull);
    });

    testWidgets('comes back on a full return to the top', (tester) async {
      await _pumpPage(tester, const Size(375, 812), photoUrls: photos);
      await _dragPage(tester, -400);
      await _settle(tester);
      expect(cueOpacity(tester), 0.0);

      _mainScrollable(tester).position.jumpTo(0);
      await _settle(tester);

      expect(cueOpacity(tester), 1.0);
      expect(tester.takeException(), isNull);
    });

    sizes.forEach((label, size) {
      testWidgets('never overlaps the profile content at $label',
          (tester) async {
        await _pumpPage(
          tester,
          size,
          // The long-name profile: the identity block is at its tallest here,
          // which is when a free-floating cue would collide with it.
          profile: _buildTypicalProfile(photoUrls: photos)
              .copyName('Aravind Krishnamoorthy', 25),
        );
        await _settle(tester);

        final hero = find.byType(ProfileDetailHeroAppBar);
        final cueRect = tester.getRect(
          find
              .descendant(
                of: hero,
                matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
              )
              .first,
        );

        for (final line in const [
          'Aravind Krishnamoorthy, 25',
          'Software Engineer',
          'Chennai, Tamil Nadu',
          'B.E/B.Tech',
        ]) {
          final finder = find.descendant(of: hero, matching: find.text(line));
          if (!tester.any(finder)) continue;
          final rect = tester.getRect(finder.first);
          expect(
            cueRect.overlaps(rect),
            isFalse,
            reason: 'the cue sits on top of "$line" at $label',
          );
          expect(
            cueRect.bottom,
            lessThanOrEqualTo(rect.top + 0.5),
            reason: 'the cue must stay above the profile content at $label',
          );
        }
        expect(cueRect.top, greaterThanOrEqualTo(0.0),
            reason: 'the cue is off the top of the hero at $label');
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('never swallows a gesture meant for the page', (tester) async {
      await _pumpPage(tester, const Size(375, 812), photoUrls: photos);
      await _settle(tester);

      final cueCentre = tester.getCenter(
        find
            .descendant(
              of: find.byType(ProfileDetailHeroAppBar),
              matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
            )
            .first,
      );
      final position = _mainScrollable(tester).position;
      await tester.timedDragFrom(
        cueCentre,
        const Offset(0, -300),
        const Duration(milliseconds: 300),
      );
      await _settle(tester);

      expect(
        position.pixels,
        greaterThan(100.0),
        reason: 'a drag started on the cue must still scroll the page',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Restructured layout order', () {
    testWidgets('the section navigation is not on screen at rest — it starts '
        'after the photo gallery', (tester) async {
      await _pumpPage(tester, const Size(375, 812));

      expect(
        isVisible(tester, find.byType(ProfileDetailSectionTabBar)),
        isFalse,
        reason: 'the navigation must no longer occupy the top of the profile',
      );
    });

    testWidgets('about, basic info and gallery all precede the navigation',
        (tester) async {
      await _pumpPage(tester, const Size(375, 812));

      // Scroll until the navigation pins, recording the bottom edge of each
      // identity section as it goes. Everything above the navigation must
      // have been laid out at a smaller scroll offset than it.
      final position = _mainScrollable(tester).position;
      final seenAt = <String, double>{};
      final above = <String, Finder>{
        'about': find.byType(AboutSection),
        'basicInfo': find.byType(BasicInformationSection),
        'gallery': find.byType(ProfilePhotoGallerySection),
      };

      for (var i = 0; i < 20; i++) {
        above.forEach((name, finder) {
          if (tester.any(finder)) {
            seenAt[name] = position.pixels + tester.getRect(finder.first).top;
          }
        });
        if (tester.any(find.byType(ProfileDetailSectionTabBar))) break;
        await _dragPage(tester, -300);
      }

      expect(tester.takeException(), isNull);
      expect(
        seenAt.keys,
        containsAll(above.keys),
        reason: 'every identity section should have been built on the way '
            'down to the navigation',
      );
      expect(seenAt['about']!, lessThan(seenAt['basicInfo']!));
      expect(seenAt['basicInfo']!, lessThan(seenAt['gallery']!));
    });

    testWidgets('no timeline presentation remains anywhere on the page',
        (tester) async {
      await _pumpPage(tester, const Size(375, 812));

      final seenTimelineText = <String>[];
      for (var i = 0; i < 40; i++) {
        if (tester.any(find.text('Timeline'))) seenTimelineText.add('Timeline');
        final position = _mainScrollable(tester).position;
        if ((position.pixels - position.maxScrollExtent).abs() < 1.0) break;
        await _dragPage(tester, -400);
      }

      expect(
        seenTimelineText,
        isEmpty,
        reason: 'the timeline section and its tab were removed from this page',
      );
    });
  });

  group('Responsive layout with photos', () {
    // 1 hero photo + 8 additional, so the mosaic renders its full
    // large + 3-small-row + wide-tile arrangement *and* a "+N" badge.
    final photos = [
      for (var i = 0; i < 9; i++) 'https://example.invalid/photo-$i.jpg',
    ];

    const widths = <String, Size>{
      'small phone': Size(320, 568),
      'normal phone': Size(375, 812),
      'large phone': Size(430, 932),
    };

    widths.forEach((name, size) {
      testWidgets('scrolls end to end on a $name without overflow or clipping',
          (tester) async {
        await _pumpPage(tester, size, photoUrls: photos);
        expect(tester.takeException(), isNull,
            reason: 'no layout exceptions on initial render at $name');

        // The gallery is above the navigation, so it is passed on the way
        // down — its mosaic laying out is what this width sweep is for.
        var sawGallery = false;
        final position = _mainScrollable(tester).position;
        for (var i = 0; i < 40; i++) {
          if (tester.any(find.byType(ProfilePhotoGallerySection))) {
            sawGallery = true;
          }
          if ((position.pixels - position.maxScrollExtent).abs() < 1.0) break;
          await _dragPage(tester, -400);
        }
        await _settle(tester);

        expect(sawGallery, isTrue,
            reason: 'the photo gallery should have been reached at $name');
        expect(tester.takeException(), isNull,
            reason: 'no layout exceptions while scrolling at $name');
      });
    });
  });

  group('Bottom action bar reveal', () {
    final photos = [
      for (var i = 0; i < 9; i++) 'https://example.invalid/photo-$i.jpg',
    ];

    testWidgets('is hidden over the hero, then revealed once scrolled past it',
        (tester) async {
      await _pumpPage(tester, const Size(375, 812), photoUrls: photos);
      await _settle(tester);

      // The hero is a full-viewport photo with the member's name and
      // profession overlaid across its lower edge — precisely where the bar
      // sits. Nothing may cover that on the first screen.
      expect(
        isVisible(tester, find.byType(ProfileDetailBottomActionBar)),
        isFalse,
        reason: 'nothing should cover the hero photo in the first viewport',
      );

      await _scrollToBottom(tester);
      await _settle(tester);

      // Delayed, not removed: Interest and Message are reachable as soon as
      // the reader is actually reading.
      expect(
        isVisible(tester, find.byType(ProfileDetailBottomActionBar)),
        isTrue,
        reason: 'the action bar should be on screen once the hero is gone',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides again on the way back up to the hero', (tester) async {
      await _pumpPage(tester, const Size(375, 812), photoUrls: photos);
      await _scrollToBottom(tester);
      await _settle(tester);
      expect(
        isVisible(tester, find.byType(ProfileDetailBottomActionBar)),
        isTrue,
      );

      // Back to the top, where the photograph owns the screen again.
      _mainScrollable(tester).position.jumpTo(0);
      await _settle(tester);

      expect(
        isVisible(tester, find.byType(ProfileDetailBottomActionBar)),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the last section reaches the bottom of the viewport',
        (tester) async {
      await _pumpPage(tester, const Size(375, 812), photoUrls: photos);

      await _scrollToBottom(tester);
      await _settle(tester);

      expect(find.byType(SimilarProfilesSection), findsOneWidget);
      expect(
        tester.getRect(find.byType(SimilarProfilesSection)).bottom,
        lessThanOrEqualTo(812.0),
        reason: 'the last section must still fit inside the viewport',
      );
      // ...and clear of the action bar, which floats over the content rather
      // than occupying a bottom-nav slot. The scroll view reserves the bar's
      // height at its end precisely so this holds.
      expect(
        tester.getRect(find.byType(SimilarProfilesSection)).bottom,
        lessThanOrEqualTo(
          812.0 - ProfileDetailBottomActionBar.contentHeight,
        ),
        reason: 'the last section must not end up underneath the action bar',
      );
      expect(tester.takeException(), isNull);
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
