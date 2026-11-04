import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/discover/presentation/providers/discover_providers.dart';
import 'package:nenjam_matrimony/features/matches/presentation/pages/matches_page.dart';

import '../../support/responsive_harness.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discover_profile_page.dart';

import 'fake_reel_backend.dart';

class _FailingReelBackend extends FakeReelBackend {
  @override
  Future<DiscoverProfilePage> getDiscoverProfilesPage({
    int page = 1,
    int limit = 20,
    String? cursor,
  }) => Future.error(Exception('offline'));
}

/// The viewports the scrolling brief asks for.
const _sizes = [
  Size(320, 568),
  Size(390, 844),
  Size(568, 320),
  Size(768, 1024),
  Size(1024, 768),
  Size(1366, 768),
  Size(1366, 600),
];

Future<void> _pumpReel(
  WidgetTester tester,
  Size size, {
  int count = 5,
  bool failing = false,
}) async {
  final errors = await pumpAtSize(
    tester,
    size,
    const MatchesPage(),
    overrides: [
      discoverRepositoryProvider.overrideWithValue(
        failing ? _FailingReelBackend() : FakeReelBackend(count: count),
      ),
    ],
  );
  expectNoOverflowIn(errors);
  // Phone-landscape and short windows are web-only; a browser reports no
  // safe-area insets.
  if (size.height < 560) {
    tester.view.padding = FakeViewPadding.zero;
    await tester.pump();
  }
}

double _page(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!.page!;

/// Where a gesture that misses the card lands: on the full-bleed layout,
/// the category header drawn over the top of the photo; on the desktop
/// layout, the page margin beside the centered card column.
Offset _offCardPoint(WidgetTester tester, Size size) {
  final column = find.byKey(const ValueKey('matches-reel-column'));
  if (column.evaluate().isNotEmpty) {
    final rect = tester.getRect(column);
    return Offset(rect.left / 2, rect.center.dy);
  }
  final search = tester.getRect(find.byIcon(Icons.search_rounded));
  // Just right of the Search chip, still on the header strip.
  return Offset(size.width / 2, search.center.dy);
}

Offset _cardCentre(WidgetTester tester) =>
    tester.getCenter(find.byType(PageView));

/// A short upward flick, the way a thumb moves to the next reel.
Future<void> _swipeUp(WidgetTester tester, Offset from) =>
    tester.flingFrom(from, const Offset(0, -120), 1500);

Future<void> _wheel(WidgetTester tester, Offset at, double dy) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(at));
  await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
  await tester.pumpAndSettle();
}

void main() {
  group('Matches reel scrolls from anywhere on the page', () {
    for (final size in _sizes) {
      testWidgets('swipe on the card at $size', (tester) async {
        await _pumpReel(tester, size);
        await _swipeUp(tester, _cardCentre(tester));
        await tester.pumpAndSettle();
        expect(_page(tester), 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('swipe off the card at $size', (tester) async {
        await _pumpReel(tester, size);
        await _swipeUp(tester, _offCardPoint(tester, size));
        await tester.pumpAndSettle();
        expect(_page(tester), 1);
      });

      testWidgets('mouse wheel off the card at $size', (tester) async {
        await _pumpReel(tester, size);
        await _wheel(tester, _offCardPoint(tester, size), 100);
        expect(_page(tester), 1);
      });

      testWidgets('mouse wheel on the card at $size', (tester) async {
        await _pumpReel(tester, size);
        await _wheel(tester, _cardCentre(tester), 100);
        expect(_page(tester), 1);
      });
    }
  });

  group('keyboard', () {
    testWidgets('ArrowDown / ArrowUp step one profile, bounded', (
      tester,
    ) async {
      await _pumpReel(tester, const Size(1366, 768));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_page(tester), 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_page(tester), 1);

      // The pager's cooldown runs on the wall clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_page(tester), 0);
    });
  });

  group('action buttons', () {
    testWidgets('tapping Share does not change the page', (tester) async {
      await _pumpReel(tester, const Size(390, 844));
      await tester.tap(find.byIcon(Icons.share_rounded).first);
      await tester.pumpAndSettle();
      expect(_page(tester), 0);
    });
  });

  group('the empty reel is not a dead end', () {
    for (final size in _sizes) {
      testWidgets('$size keeps Search and the categories', (tester) async {
        await _pumpReel(tester, size, count: 0);
        expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      });
    }
  });

  group('a failed load keeps the header and fits', () {
    for (final size in _sizes) {
      testWidgets('$size', (tester) async {
        await _pumpReel(tester, size, failing: true);
        expect(find.byType(PageView), findsNothing);
        expect(find.byIcon(Icons.search_rounded), findsOneWidget);
        // Swiping or wheeling with no reel attached is a harmless no-op.
        await _swipeUp(tester, Offset(size.width / 2, size.height / 2));
        await _wheel(tester, Offset(size.width / 2, size.height / 2), 100);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
