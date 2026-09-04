import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/profile_photos/data/repositories/photo_repository.dart';
import 'package:nenjam_matrimony/features/profile_photos/domain/models/user_photo.dart';
import 'package:nenjam_matrimony/features/profile_photos/presentation/providers/photo_providers.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/profile_edit_page.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';
import 'package:nenjam_matrimony/l10n/app_localizations_en.dart';
import 'package:nenjam_matrimony/l10n/app_localizations_ta.dart';

/// Edit Profile's summary hands the single editable page a section index, and
/// the page must open scrolled to that section's heading.
///
/// This regressed once already, silently: the page built its sections in a
/// [ListView], which only builds what is inside the viewport. On the first
/// frame every section below the fold still had a null
/// `GlobalKey.currentContext`, so `Scrollable.ensureVisible` had nothing to
/// scroll to and returned without error — "Edit" on Family or Photos simply
/// opened the page at the top. These assert on the *rendered position of the
/// heading*, so building a section but failing to scroll to it fails just as
/// loudly as never building it.
void main() {
  /// The heading each editable section is identified by, keyed by the draft
  /// step index the summary passes. Section 11 (photos) is the one that is
  /// not draft-backed, and the furthest down the page — the case the
  /// ListView bug hid completely.
  Map<int, String> headings(AppLocalizations l10n) => {
        0: l10n.registrationWizardBasicInfoHeadline,
        1: l10n.registrationWizardReligionHeadline,
        2: l10n.registrationWizardLanguageHeadline,
        3: l10n.registrationWizardLocationHeadline,
        4: l10n.registrationWizardEducationHeadline,
        5: l10n.registrationWizardPhysicalHeadline,
        6: l10n.registrationWizardLifestyleHeadline,
        7: l10n.registrationWizardFamilyHeadline,
        8: l10n.registrationWizardHoroscopeHeadline,
        11: l10n.registrationWizardPhotosHeadline,
      };

  /// A heading this far down has not been scrolled to — it is simply where
  /// the section happened to land. Comfortably below the AppBar and the
  /// 24dp top padding, comfortably above a second screenful.
  const nearTop = 260.0;

  Future<void> pumpPage(
    WidgetTester tester, {
    int? initialSection,
    Locale locale = const Locale('en'),
    Size size = const Size(390, 844),
    double textScale = 1.0,
  }) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    await tester.binding.setSurfaceSize(size);

    // Tear the previous tree down first. The scroll is posted from
    // initState, and pumpWidget reuses the element for the same widget type
    // — without this, only the first section in a sweep would ever scroll
    // and the rest would trivially "pass" from the previous position.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          photoRepositoryProvider.overrideWithValue(_EmptyPhotoRepository()),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: textScale,
            maxScaleFactor: textScale,
            child: child!,
          ),
          home: ProfileEditPage(initialSection: initialSection),
        ),
      ),
    );

    // The scroll is posted for after the first layout and then animates. A
    // bounded walk rather than pumpAndSettle: the photo section's loading
    // indicator would otherwise never let settle return.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('opens scrolled to the requested section, for every section', (
    tester,
  ) async {
    final expected = headings(AppLocalizationsEn());

    for (final entry in expected.entries) {
      await pumpPage(tester, initialSection: entry.key);

      final heading = find.text(entry.value);
      expect(
        heading,
        findsOneWidget,
        reason: 'section ${entry.key} heading should be built and on screen',
      );

      final dy = tester.getTopLeft(heading).dy;
      expect(
        dy,
        inInclusiveRange(0, nearTop),
        reason: 'section ${entry.key} heading sits at dy=$dy, not near the top',
      );

      // And it is the *right* section, not a neighbour that happens to be
      // near the top too: every other section must sit on the side of the
      // target that the page order puts it on. Sections above the target
      // are scrolled off (negative dy), sections below are further down.
      final order = expected.keys.toList();
      final targetIndex = order.indexOf(entry.key);
      for (final other in expected.entries) {
        if (other.key == entry.key) continue;
        final otherFinder = find.text(other.value);
        if (otherFinder.evaluate().isEmpty) continue;
        final otherDy = tester.getTopLeft(otherFinder).dy;
        final matcher = order.indexOf(other.key) < targetIndex
            ? lessThan(dy)
            : greaterThan(dy);
        expect(
          otherDy,
          matcher,
          reason: 'with section ${entry.key} requested, section ${other.key} '
              'rendered at dy=$otherDy, on the wrong side of dy=$dy',
        );
      }
    }
  });

  testWidgets('without a section, stays at the default scroll position', (
    tester,
  ) async {
    await pumpPage(tester);
    final l10n = AppLocalizationsEn();

    // The first section is at the top and nothing scrolled past it...
    final first = find.text(l10n.registrationWizardBasicInfoHeadline);
    expect(first, findsOneWidget);
    expect(tester.getTopLeft(first).dy, inInclusiveRange(0, nearTop));

    // ...and a later section is still below the fold, where it belongs.
    final later = find.text(l10n.registrationWizardFamilyHeadline);
    expect(tester.getTopLeft(later).dy, greaterThan(nearTop));
  });

  testWidgets('scrolls to the right section in Tamil at a large text scale', (
    tester,
  ) async {
    // The combination most likely to shift offsets: longer strings wrapping
    // to more lines on a narrow screen, so a scroll computed from anything
    // but real laid-out geometry would drift.
    await pumpPage(
      tester,
      initialSection: 7,
      locale: const Locale('ta'),
      textScale: 1.5,
      size: const Size(320, 640),
    );

    final heading = find.text(AppLocalizationsTa().registrationWizardFamilyHeadline);
    expect(heading, findsOneWidget);
    expect(tester.getTopLeft(heading).dy, inInclusiveRange(0, nearTop));
  });

  testWidgets('scrolls to the right section in landscape', (tester) async {
    await pumpPage(tester, initialSection: 8, size: const Size(844, 390));

    final heading =
        find.text(AppLocalizationsEn().registrationWizardHoroscopeHeadline);
    expect(heading, findsOneWidget);
    expect(tester.getTopLeft(heading).dy, inInclusiveRange(0, nearTop));
  });
}

class _EmptyPhotoRepository implements PhotoRepository {
  @override
  Future<List<UserPhoto>> fetchPhotos() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
