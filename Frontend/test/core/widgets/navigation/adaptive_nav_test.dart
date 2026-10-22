import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/widgets/navigation/app_bottom_nav.dart';

import '../../../support/responsive_harness.dart';

const _rail = ValueKey('desktop-nav-rail');
const _extendedRail = ValueKey('desktop-nav-rail-extended');

void main() {
  group('NavRailMetrics', () {
    test('widths are explicit', () {
      expect(NavRailMetrics.compactWidth, 96);
      expect(NavRailMetrics.extendedWidth, 240);
    });
  });

  group('NmNavigationRail', () {
    // Returns the harness's exceptions rather than asserting here:
    // pumpAtSize drains the exception queue, so the check has to run on the
    // returned list (expectNoOverflowIn), never on a later expectNoOverflow.
    Future<List<Object>> pumpRail(
      WidgetTester tester, {
      required bool extended,
      Size size = const Size(1440, 900),
    }) {
      return pumpAtSize(
        tester,
        size,
        Scaffold(
          body: Row(
            children: [
              NmNavigationRail(
                extended: extended,
                children: const [
                  Text('Discover'),
                  Text('Matches'),
                  Text('Inbox'),
                  Text('Premium'),
                ],
              ),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      );
    }

    testWidgets('compact variant is 96px and keeps the legacy key', (
      tester,
    ) async {
      expectNoOverflowIn(await pumpRail(tester, extended: false));
      expect(find.byKey(_rail), findsOneWidget);
      expect(find.byKey(_extendedRail), findsNothing);
      expect(
        tester.getSize(find.byKey(_rail)).width,
        NavRailMetrics.compactWidth,
      );
    });

    testWidgets('extended variant is 240px and carries both keys', (
      tester,
    ) async {
      expectNoOverflowIn(await pumpRail(tester, extended: true));
      expect(find.byKey(_rail), findsOneWidget);
      expect(find.byKey(_extendedRail), findsOneWidget);
      expect(
        tester.getSize(find.byKey(_rail)).width,
        NavRailMetrics.extendedWidth,
      );
    });

    testWidgets('extended rail does not overflow on a short window', (
      tester,
    ) async {
      expectNoOverflowIn(
        await pumpRail(tester, extended: true, size: kShortDesktop),
      );
    });

    testWidgets('compact rail does not overflow on a short window', (
      tester,
    ) async {
      expectNoOverflowIn(
        await pumpRail(tester, extended: false, size: kShortDesktop),
      );
    });
  });
}
