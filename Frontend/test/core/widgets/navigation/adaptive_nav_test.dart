import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/widgets/navigation/app_bottom_nav.dart';

import '../../../support/responsive_harness.dart';

const _rail = ValueKey('desktop-nav-rail');

void main() {
  test('the rail is 96px wide', () {
    expect(NavRailMetrics.width, 96);
  });

  group('NmNavigationRail', () {
    // Returns the harness's exceptions rather than asserting here:
    // pumpAtSize drains the exception queue, so the check has to run on the
    // returned list (expectNoOverflowIn), never on a later expectNoOverflow.
    Future<List<Object>> pumpRail(
      WidgetTester tester, {
      Size size = const Size(1440, 900),
    }) {
      return pumpAtSize(
        tester,
        size,
        const Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NmNavigationRail(
                leading: Text('Brand'),
                footer: [Text('Profile'), Text('More')],
                children: [
                  Text('Discover'),
                  Text('Matches'),
                  Text('Inbox'),
                  Text('Premium'),
                ],
              ),
              Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      );
    }

    testWidgets('fills the window height along the left edge', (tester) async {
      expectNoOverflowIn(await pumpRail(tester));
      final rail = tester.getRect(find.byKey(_rail));
      // The old rail shrank to its items and floated mid-window.
      expect(rail, const Rect.fromLTWH(0, 0, 96, 900));
    });

    testWidgets('brand on top, footer pinned to the bottom', (tester) async {
      expectNoOverflowIn(await pumpRail(tester));
      // Below the 44px safe-area top, within the rail's top padding.
      expect(tester.getTopLeft(find.text('Brand')).dy, lessThan(120));
      expect(
        tester.getTopLeft(find.text('Discover')).dy,
        greaterThan(tester.getBottomLeft(find.text('Brand')).dy),
      );
      // Above the 34px safe-area bottom, within the rail's bottom padding.
      expect(tester.getBottomLeft(find.text('More')).dy, greaterThan(800));
      expect(
        tester.getTopLeft(find.text('Profile')).dy,
        greaterThan(tester.getBottomLeft(find.text('Premium')).dy + 100),
        reason: 'free space sits between the tabs and the footer',
      );
    });

    testWidgets('scrolls rather than overflowing on a short window', (
      tester,
    ) async {
      expectNoOverflowIn(await pumpRail(tester, size: const Size(900, 220)));
      expect(find.text('More', skipOffstage: false), findsOneWidget);
    });
  });
}
