import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/discover/presentation/providers/discover_providers.dart';
import 'package:nenjam_matrimony/features/matches/presentation/pages/matches_page.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import '../../support/responsive_harness.dart';
import 'fake_reel_backend.dart';

/// The four reel actions, by icon (shortlist is outlined until shortlisted).
const _actionIcons = [
  Icons.favorite_rounded,
  Icons.bookmark_border_rounded,
  Icons.share_rounded,
  Icons.flag_rounded,
];

/// The brief's viewports, on a notched device.
const _briefSizes = [
  Size(320, 568),
  Size(375, 812),
  Size(430, 932),
  Size(600, 960),
  Size(768, 1024),
  Size(1024, 768),
  Size(1366, 768),
  Size(1920, 1080),
];

/// Short windows only the web build can reach (native builds are portrait
/// locked): a phone browser held sideways, and short laptop windows. These
/// are where the action column used to run off the top of the screen.
const _shortWebSizes = [
  Size(568, 320),
  Size(812, 375),
  Size(932, 430),
  Size(900, 450),
  Size(1280, 500),
];

Future<void> _pumpReel(
  WidgetTester tester,
  Size size, {
  bool web = false,
  int count = 3,
}) async {
  final errors = await pumpAtSize(
    tester,
    size,
    const MatchesPage(),
    overrides: [
      discoverRepositoryProvider.overrideWithValue(
        FakeReelBackend(count: count),
      ),
    ],
  );
  expectNoOverflowIn(errors);
  if (web) {
    // A browser reports no safe-area insets.
    tester.view.padding = FakeViewPadding.zero;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  }
}

/// The first (visible) reel card's action icon.
Finder _action(IconData icon) => find.byIcon(icon).first;

/// Whether a tap at [finder]'s centre would land on it, rather than on
/// something drawn over it (the category header absorbs taps where it
/// covers the photo).
bool _receivesTapAtCentre(WidgetTester tester, Finder finder) {
  final target = tester.renderObject(finder);
  final result = tester.hitTestOnBinding(tester.getCenter(finder));
  return result.path.any((entry) => entry.target == target);
}

void _expectActionsReachable(WidgetTester tester, Size size) {
  // The header's chip row ends here on the full-bleed layout; on desktop the
  // same bar is a toolbar above the card. Either way no action may sit
  // above it.
  final headerBottom = tester.getRect(find.byIcon(Icons.search_rounded)).bottom;
  for (final icon in _actionIcons) {
    final rect = tester.getRect(_action(icon));
    final why = '$icon at $size: $rect';
    expect(rect.top, greaterThan(headerBottom), reason: '$why (under header)');
    expect(rect.top, greaterThanOrEqualTo(0), reason: '$why (off top)');
    expect(rect.bottom, lessThanOrEqualTo(size.height), reason: why);
    expect(rect.right, lessThanOrEqualTo(size.width), reason: why);
    expect(_receivesTapAtCentre(tester, _action(icon)), isTrue, reason: why);
  }
}

void main() {
  group('Matches reel actions stay on screen and tappable', () {
    for (final size in _briefSizes) {
      testWidgets('$size', (tester) async {
        await _pumpReel(tester, size);
        _expectActionsReachable(tester, size);
      });
    }
    for (final size in _shortWebSizes) {
      testWidgets('web $size', (tester) async {
        await _pumpReel(tester, size, web: true);
        _expectActionsReachable(tester, size);
      });
    }
  });

  group('captions', () {
    String shareCaption(WidgetTester tester) => AppLocalizations.of(
      tester.element(find.byType(MatchesPage)),
    ).actionShare;

    testWidgets('shown wherever the full column fits', (tester) async {
      for (final size in _briefSizes) {
        await _pumpReel(tester, size);
        expect(
          find.text(shareCaption(tester).toUpperCase()),
          findsWidgets,
          reason: '$size',
        );
      }
    });

    testWidgets('compact column drops the caption but keeps it as the '
        "button's accessibility label", (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpReel(tester, const Size(812, 375), web: true);
      final caption = shareCaption(tester);
      expect(find.text(caption.toUpperCase()), findsNothing);
      expect(find.bySemanticsLabel(caption), findsWidgets);
      // Same 48px button as the full column — only the spacing tightens.
      expect(
        tester.getSize(_action(Icons.share_rounded)).height,
        tester.getSize(_action(Icons.share_rounded)).width,
      );
      semantics.dispose();
    });

    testWidgets('even the shortest window keeps buttons near touch size', (
      tester,
    ) async {
      await _pumpReel(tester, const Size(568, 320), web: true);
      final box = find
          .ancestor(
            of: _action(Icons.share_rounded),
            matching: find.byType(AnimatedContainer),
          )
          .first;
      expect(tester.getSize(box).height, greaterThanOrEqualTo(40));
    });
  });

  testWidgets('a long name never runs under the action column', (tester) async {
    for (final size in [..._briefSizes.take(5), ..._shortWebSizes]) {
      await _pumpReel(tester, size, web: size.height < 560);
      final name = tester.getRect(find.textContaining('Venkatalakshmi').first);
      final actions = tester.getRect(_action(Icons.favorite_rounded));
      expect(name.right, lessThanOrEqualTo(actions.left), reason: '$size');
    }
  });

  testWidgets('the empty state fits every brief size', (tester) async {
    for (final size in [..._briefSizes, ..._shortWebSizes]) {
      await _pumpReel(tester, size, count: 0);
      expect(find.byType(PageView), findsNothing, reason: '$size');
    }
  });

  // The report / block sheet opened from "More" uses the shared action
  // sheet; it must fit the smallest phone and the shortest web window.
  for (final (size, web) in [
    (const Size(320, 568), false),
    (const Size(568, 320), true),
  ]) {
    testWidgets('the More sheet fits on screen at $size', (tester) async {
      await _pumpReel(tester, size, web: web);
      await tester.tap(_action(Icons.flag_rounded));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(MatchesPage)),
      );
      for (final label in [
        l10n.profileDetailActionReport,
        l10n.profileDetailActionBlock,
      ]) {
        final rect = tester.getRect(find.text(label).last);
        expect(rect.top, greaterThanOrEqualTo(0), reason: label);
        expect(rect.bottom, lessThanOrEqualTo(size.height), reason: label);
        expect(
          _receivesTapAtCentre(tester, find.text(label).last),
          isTrue,
          reason: label,
        );
      }
    });
  }
}
