import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/services/storage_service.dart';
import 'package:nenjam_matrimony/core/widgets/cards/subscription_card.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/widgets/message_bubble.dart';
import 'package:nenjam_matrimony/features/matches/presentation/pages/matches_page.dart';
import 'package:nenjam_matrimony/features/premium/presentation/pages/premium_page.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_dashboard_providers.dart';
import 'package:nenjam_matrimony/features/profile_photos/presentation/providers/photo_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_flow_mode.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/edit_profile_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/profile_section_edit_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/features/settings/presentation/pages/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/registration/edit_profile_test_support.dart';
import 'support/responsive_harness.dart';

/// Desktop and tablet layouts of the screens outside Discover.
///
/// `responsive_pages_audit_test.dart` sweeps these pages at phone sizes only;
/// this file covers the widths where they now center or split into columns,
/// and checks that phones keep their previous layout.
///
/// Expected positions are written out as literals on purpose: recomputing
/// them with the layout helpers would make the test agree with the
/// implementation by construction.
void main() {
  setUpAll(() async {
    // SettingsPage reads the global StorageService.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await storageService.init();
  });

  const wideSizes = [
    ...kTabletViewports,
    ...kDesktopViewports,
    ...kUltrawideViewports,
  ];

  final editMode = profileFlowModeProvider.overrideWith(
    (ref) => ProfileFlowMode.edit,
  );
  final editProfileOverrides = [
    editMode,
    profileDraftResponseProvider.overrideWith((ref) async => {}),
    photoRepositoryProvider.overrideWithValue(EmptyPhotoRepository()),
  ];

  group('no overflow at tablet, desktop and ultrawide sizes', () {
    final pages = <String, (Widget Function(), List<Override>)>{
      'MatchesPage': (() => const MatchesPage(), const []),
      'PremiumPage': (() => const PremiumPage(), const []),
      'SettingsPage': (() => const SettingsPage(), const []),
      'EditProfilePage': (() => const EditProfilePage(), editProfileOverrides),
      'BasicInfoEditPage': (() => const BasicInfoEditPage(), [editMode]),
    };
    for (final MapEntry(key: name, value: (build, overrides))
        in pages.entries) {
      testWidgets(name, (tester) async {
        final failures = <String>[];
        for (final size in wideSizes) {
          final errors = await pumpAtSize(
            tester,
            size,
            build(),
            overrides: overrides,
          );
          failures.addAll([
            for (final e in errors)
              '${size.width.toInt()}x${size.height.toInt()}: ${shortError(e)}',
          ]);
        }
        expect(failures, isEmpty, reason: failures.join('\n'));
      });
    }
  });

  group('Chat bubbles', () {
    Future<double> maxWidthAt(WidgetTester tester, Size size) async {
      late double result;
      await pumpAtSize(
        tester,
        size,
        Builder(
          builder: (context) {
            result = bubbleMaxWidth(context);
            return const SizedBox.shrink();
          },
        ),
      );
      return result;
    }

    testWidgets('phones keep 75% of the screen', (tester) async {
      expect(await maxWidthAt(tester, const Size(375, 812)), 281.25);
      expect(await maxWidthAt(tester, const Size(320, 568)), 240);
    });

    testWidgets('wide windows stop at a readable 560px', (tester) async {
      expect(await maxWidthAt(tester, const Size(1440, 900)), 560);
      expect(await maxWidthAt(tester, const Size(3440, 1440)), 560);
    });
  });

  group('Premium', () {
    List<Rect> cardRects(WidgetTester tester) => [
      for (final e in find.byType(NmSubscriptionCard).evaluate())
        tester.getRect(find.byWidget(e.widget)),
    ];

    testWidgets('phone: plans stacked, full width', (tester) async {
      expectNoOverflowIn(
        await pumpAtSize(tester, const Size(390, 844), const PremiumPage()),
      );
      final rects = cardRects(tester);
      expect(rects, hasLength(2));
      expect(rects[1].top, greaterThan(rects[0].bottom));
      // 390 - 2 * 20 page padding, as before.
      expect(rects[0].width, 350);
    });

    testWidgets('desktop: plans side by side in a centered 900px column', (
      tester,
    ) async {
      expectNoOverflowIn(
        await pumpAtSize(tester, const Size(1440, 900), const PremiumPage()),
      );
      final rects = cardRects(tester);
      expect(rects, hasLength(2));
      expect(rects[0].top, rects[1].top);
      // Equal heights, whatever their feature lists.
      expect(rects[0].height, rects[1].height);
      // Column: 900 wide, centered in 1440 - 2 * 20 → starts at 270.
      // Each plan: (900 - 20 gap) / 2.
      expect(rects[0].left, 270);
      expect(rects[0].width, 440);
      expect(rects[1].right, 1170);
    });
  });

  group('Matches reel', () {
    final column = find.byKey(const ValueKey('matches-reel-column'));

    testWidgets('phones and portrait tablets keep the full-bleed reel', (
      tester,
    ) async {
      for (final size in [const Size(390, 844), const Size(820, 1180)]) {
        expectNoOverflowIn(await pumpAtSize(tester, size, const MatchesPage()));
        expect(column, findsNothing, reason: '$size');
      }
    });

    testWidgets('wide pages show a centered 9:16 column', (tester) async {
      expectNoOverflowIn(
        await pumpAtSize(tester, const Size(1440, 900), const MatchesPage()),
      );
      // 900 * 9 / 16, centered in 1440.
      expect(tester.getSize(column).width, 506.25);
      expect(tester.getTopLeft(column).dx, 466.875);
    });

    testWidgets('the column stays within its bounds', (tester) async {
      // Short window: 600 * 9 / 16 = 337.5, held at the 360 minimum.
      await pumpAtSize(tester, const Size(1280, 600), const MatchesPage());
      expect(tester.getSize(column).width, 360);
      // Tall window: 1440 * 9 / 16 = 810, held at the 560 maximum.
      await pumpAtSize(tester, const Size(2560, 1440), const MatchesPage());
      expect(tester.getSize(column).width, 560);
    });
  });

  group('Settings list', () {
    EdgeInsets listPadding(WidgetTester tester) =>
        tester.widget<ListView>(find.byType(ListView).first).padding!
            as EdgeInsets;

    testWidgets('phone keeps its 20px padding', (tester) async {
      await pumpAtSize(tester, const Size(390, 844), const SettingsPage());
      expect(listPadding(tester), const EdgeInsets.all(20));
    });

    testWidgets('desktop centers it at 680px, list still full width', (
      tester,
    ) async {
      await pumpAtSize(tester, const Size(1920, 1080), const SettingsPage());
      // (1920 - 680) / 2 on each side.
      expect(listPadding(tester), const EdgeInsets.fromLTRB(620, 20, 620, 20));
      expect(tester.getSize(find.byType(ListView).first).width, 1920);
    });
  });

  group('Edit Profile sections', () {
    Finder card(int index) => find.byKey(
      ValueKey('edit-profile-section-${EditProfileSection.all[index].id}'),
    );

    testWidgets('phone: one column, as before', (tester) async {
      await pumpAtSize(
        tester,
        const Size(390, 844),
        const EditProfilePage(),
        overrides: editProfileOverrides,
      );
      expect(tester.getTopLeft(card(1)).dx, tester.getTopLeft(card(0)).dx);
      expect(
        tester.getTopLeft(card(1)).dy,
        greaterThan(tester.getBottomLeft(card(0)).dy),
      );
    });

    testWidgets('desktop: two columns inside a centered 900px area', (
      tester,
    ) async {
      await pumpAtSize(
        tester,
        const Size(1440, 900),
        const EditProfilePage(),
        overrides: editProfileOverrides,
      );
      // Reading order runs across: first card left, second right, same row.
      expect(tester.getTopLeft(card(0)).dy, tester.getTopLeft(card(1)).dy);
      // (1440 - 900) / 2 = 270 to the left edge; (900 - 16 gap) / 2 per card.
      expect(tester.getTopLeft(card(0)).dx, 270);
      expect(tester.getSize(card(0)).width, 442);
      expect(tester.getTopRight(card(1)).dx, 1170);
      // The third card starts the next row on the left.
      expect(tester.getTopLeft(card(2)).dx, 270);
    });
  });
}
