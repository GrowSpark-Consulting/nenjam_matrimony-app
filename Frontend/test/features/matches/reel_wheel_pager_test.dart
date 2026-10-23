import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nenjam_matrimony/features/matches/presentation/pages/matches_page.dart';

/// The Matches reel is a vertical PageView. Its own wheel handling scrolls a
/// notch's pixels and springs back to the nearest page, so a mouse could
/// barely leave the first profile. [ReelWheelPager] turns a notch into one
/// whole page.
void main() {
  late DateTime clock;

  Future<PageController> pumpReel(WidgetTester tester) async {
    clock = DateTime(2026);
    final controller = PageController();
    final pager = ReelWheelPager(controller, now: () => clock);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 800,
          child: PageView.builder(
            controller: controller,
            scrollDirection: Axis.vertical,
            itemCount: 5,
            itemBuilder: (context, i) => Listener(
              onPointerSignal: (event) => pager.handle(event, 5),
              child: ColoredBox(
                color: Colors.primaries[i],
                child: Center(child: Text('page $i')),
              ),
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  Future<void> wheel(WidgetTester tester, double dy) async {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byType(PageView))),
    );
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pumpAndSettle();
  }

  testWidgets('one wheel notch down moves to the next profile', (tester) async {
    final controller = await pumpReel(tester);
    await wheel(tester, 100);
    expect(controller.page, 1);
  });

  testWidgets('a notch up moves back, and not before the first', (
    tester,
  ) async {
    final controller = await pumpReel(tester);
    await wheel(tester, 100);
    clock = clock.add(const Duration(seconds: 1));
    await wheel(tester, -100);
    expect(controller.page, 0);

    clock = clock.add(const Duration(seconds: 1));
    await wheel(tester, -100);
    expect(controller.page, 0);
  });

  testWidgets('a second notch during the page animation is ignored', (
    tester,
  ) async {
    final controller = await pumpReel(tester);
    await wheel(tester, 100);
    await wheel(tester, 100);
    expect(controller.page, 1);
  });

  testWidgets('small trackpad deltas do not move a page on their own', (
    tester,
  ) async {
    final controller = await pumpReel(tester);
    await wheel(tester, 10);
    expect(controller.page, 0);
  });
}
