import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/layout/content_width.dart';
import 'package:nenjam_matrimony/core/widgets/feedback/error_widget.dart';
import 'package:nenjam_matrimony/core/widgets/feedback/loading_widget.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discover_feed_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/discover/presentation/providers/discover_providers.dart';
import 'package:nenjam_matrimony/features/profile_detail/domain/entities/profile_detail_entity.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/pages/profile_detail_page.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/providers/profile_detail_providers.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/about_section.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/family_info_section.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/profile_detail_section_tab_bar.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/widgets/verification_section.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import '../../support/responsive_harness.dart';

/// Profile detail stays ONE vertical scroll column with a pinned section tab
/// bar; on wide windows its content is bounded to [ContentWidth.detail]
/// instead of stretching.
///
/// It is deliberately not split into two columns: the tab bar's
/// `_scrollToSection` walks the viewport vertically, and "above" and "below"
/// are undefined across a horizontal split.
void main() {
  group('content width', () {
    // The padded width up to 1232 (1200 content + 2 * 16 gutter), then the
    // 1200 cap. Written out as literals so the expectation is independent of
    // the implementation's arithmetic.
    final expectedContentWidth = <double, double>{
      320: 288,
      375: 343,
      768: 736,
      1024: 992,
      1199: 1167,
      1200: 1168,
      1232: 1200,
      1233: 1200,
      1440: 1200,
      1920: 1200,
      2560: 1200,
      3440: 1200,
    };

    for (final entry in expectedContentWidth.entries) {
      final width = entry.key;
      final content = entry.value;
      testWidgets('${width.toInt()}px: sections are $content wide, centred', (
        tester,
      ) async {
        final errors = await _pumpDetail(tester, Size(width, 900));
        expectNoOverflowIn(errors);
        await _scrollTo(tester, 900);

        final about = find.byType(AboutSection);
        expect(about, findsOneWidget);
        final rect = tester.getRect(about);
        expect(rect.width, closeTo(content, 0.01));
        expect(rect.left, closeTo((width - content) / 2, 0.01));
        expect(
          rect.width,
          lessThanOrEqualTo(ContentWidth.detail),
          reason: 'content must never exceed the detail cap',
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('boundary widths neither overflow nor jump', (tester) async {
      for (final width in [...kBoundaryWidths, 1231.0, 1232.0, 1233.0]) {
        final errors = await _pumpDetail(tester, Size(width, 900));
        expectNoOverflowIn(errors);
        await _scrollTo(tester, 900);
        expect(
          tester.getSize(find.byType(AboutSection)).width,
          closeTo(width - 32 < 1200 ? width - 32 : 1200, 0.01),
          reason: 'content width at ${width}px',
        );
        expectNoOverflow(tester);
      }
    });

    testWidgets('deeper sections are bounded too', (tester) async {
      final errors = await _pumpDetail(tester, const Size(1920, 900));
      expectNoOverflowIn(errors);
      await _revealTabBar(tester);
      await _scrollTo(tester, _position(tester).pixels + 600);

      final family = find.byType(FamilyInfoSection);
      expect(family, findsOneWidget);
      final rect = tester.getRect(family);
      expect(rect.width, lessThanOrEqualTo(ContentWidth.detail));
      expect(rect.left, closeTo((1920 - rect.width) / 2, 0.01));
    });
  });

  group('section tab bar', () {
    testWidgets('stays present and pinned on a wide window', (tester) async {
      final errors = await _pumpDetail(tester, const Size(1440, 900));
      expectNoOverflowIn(errors);

      await _revealTabBar(tester);
      final bar = find.byType(ProfileDetailSectionTabBar);
      expect(bar, findsOneWidget);

      // Scroll far enough for the bar to reach the top, then keep going: a
      // pinned bar stays at the top while the content moves beneath it.
      await _scrollTo(tester, _position(tester).pixels + 900);
      expect(tester.getTopLeft(bar).dy, closeTo(0, 0.01));
      await _scrollTo(tester, _position(tester).pixels + 300);
      expect(tester.getTopLeft(bar).dy, closeTo(0, 0.01));
    });

    testWidgets('spans content plus its own padding, and no wider', (
      tester,
    ) async {
      for (final entry in {
        375.0: 375.0,
        1000.0: 1000.0,
        1440.0: 1232.0,
        3440.0: 1232.0,
      }.entries) {
        final errors = await _pumpDetail(tester, Size(entry.key, 900));
        expectNoOverflowIn(errors);
        await _revealTabBar(tester);
        final rect = tester.getRect(find.byType(ProfileDetailSectionTabBar));
        expect(
          rect.width,
          closeTo(entry.value, 0.01),
          reason: '${entry.key}px',
        );
        expect(rect.center.dx, closeTo(entry.key / 2, 0.01));
      }
    });

    testWidgets('tapping a tab scrolls to its section on a wide window', (
      tester,
    ) async {
      final errors = await _pumpDetail(tester, const Size(1440, 900));
      expectNoOverflowIn(errors);
      await _revealTabBar(tester);

      // Verification is the last addressable section: reaching it exercises
      // the bounded walk that builds lazy slivers on the way down.
      await tester.tap(_tab('Verification'));
      await _settle(tester);
      expectNoOverflow(tester);

      final verification = find.byType(VerificationSection);
      expect(verification, findsOneWidget);
      expect(_isOnScreen(tester, verification), isTrue);
      expect(
        tester.getSize(verification).width,
        lessThanOrEqualTo(ContentWidth.detail),
      );

      // And back up, which walks the other way.
      await tester.tap(_tab('Family'));
      await _settle(tester);
      expectNoOverflow(tester);
      expect(_isOnScreen(tester, find.byType(FamilyInfoSection)), isTrue);
    });

    testWidgets('tapping a tab still works on a phone', (tester) async {
      final errors = await _pumpDetail(tester, const Size(375, 812));
      expectNoOverflowIn(errors);
      await _revealTabBar(tester);

      await tester.tap(_tab('Lifestyle'));
      await _settle(tester);
      expectNoOverflow(tester);
    });
  });

  group('states', () {
    for (final width in [320.0, 1440.0]) {
      testWidgets('${width.toInt()}px: loading', (tester) async {
        final errors = await _pumpDetail(
          tester,
          Size(width, 800),
          detail: () => Completer<ProfileDetailEntity>().future,
        );
        expectNoOverflowIn(errors);
        expect(find.byType(NmLoadingWidget), findsOneWidget);
        expect(find.byType(ProfileDetailSectionTabBar), findsNothing);
      });

      testWidgets('${width.toInt()}px: error offers retry', (tester) async {
        final errors = await _pumpDetail(
          tester,
          Size(width, 800),
          detail: () async {
            throw Exception('boom');
          },
        );
        expectNoOverflowIn(errors);
        expect(find.byType(NmErrorWidget), findsOneWidget);
        expect(find.byType(ProfileDetailSectionTabBar), findsNothing);
      });
    }

    testWidgets('320x568 loaded content does not overflow', (tester) async {
      final errors = await _pumpDetail(tester, const Size(320, 568));
      expectNoOverflowIn(errors);
      await _scrollTo(tester, 568);
      expectNoOverflow(tester);
      await _revealTabBar(tester);
      await _scrollTo(tester, _position(tester).maxScrollExtent);
      expectNoOverflow(tester);
    });
  });
}

// --- helpers ----------------------------------------------------------------

DiscoveryProfileEntity _profile() => const DiscoveryProfileEntity(
  id: 'resp-1',
  matrimonyId: 'NM100001',
  name: 'Responsive Tester',
  age: 29,
  location: 'Chennai, Tamil Nadu',
  profession: 'Software Engineer',
  education: 'B.E.',
  photoUrls: [],
  gender: 'Female',
);

/// Pumps the real [ProfileDetailPage] at [size] and returns the exceptions the
/// pump produced.
///
/// Not `pumpAtSize`: a tab tap runs an InkWell, whose default splash loads a
/// shader asset that the widget-test bundle does not contain, so the theme
/// must turn splashes off. Everything else mirrors the harness.
///
/// With [detail] unset the page resolves through its real mock data source.
Future<List<Object>> _pumpDetail(
  WidgetTester tester,
  Size size, {
  Future<ProfileDetailEntity> Function()? detail,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  await tester.binding.setSurfaceSize(size);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // Tear down first so a repeated overflow is re-reported per size.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        discoverFeedProvider.overrideWith(
          (ref) async => const DiscoverFeedEntity(
            stories: [],
            profileCompletionPercent: 0,
            aiRecommended: [],
            recentlyJoined: [],
            verifiedProfiles: [],
            nearYou: [],
            premiumMembers: [],
          ),
        ),
        if (detail != null)
          profileDetailProvider.overrideWith((ref, base) => detail()),
      ],
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

  // The mock data source answers after 350ms.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return drainExceptions(tester);
}

/// A bounded replacement for `pumpAndSettle` (the shimmer and the pulsing
/// scroll cue never settle).
Future<void> _settle(WidgetTester tester, {int frames = 16}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

Future<void> _scrollTo(WidgetTester tester, double pixels) async {
  final position = _position(tester);
  position.jumpTo(pixels.clamp(0, position.maxScrollExtent));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// The tab bar sits below the first screenful, so it is not built at rest.
Future<void> _revealTabBar(WidgetTester tester) async {
  final viewport = tester.view.physicalSize.height;
  for (var i = 0; i < 40; i++) {
    if (tester.any(find.byType(ProfileDetailSectionTabBar))) {
      final top = tester.getTopLeft(find.byType(ProfileDetailSectionTabBar)).dy;
      if (top >= 0 && top < viewport) return;
    }
    await _scrollTo(tester, _position(tester).pixels + viewport * 0.6);
  }
  fail('the section tab bar was never reached');
}

Finder _tab(String label) => find.descendant(
  of: find.byType(ProfileDetailSectionTabBar),
  matching: find.text(label),
);

bool _isOnScreen(WidgetTester tester, Finder finder) {
  if (!tester.any(finder)) return false;
  final rect = tester.getRect(finder.first);
  final size = tester.view.physicalSize;
  return rect.bottom > 0 &&
      rect.top < size.height &&
      rect.right > 0 &&
      rect.left < size.width;
}
