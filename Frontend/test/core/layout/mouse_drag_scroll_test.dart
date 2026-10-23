import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nenjam_matrimony/core/layout/mouse_drag_scroll.dart';

/// In a browser a plain mouse wheel only scrolls vertically and Flutter does
/// not let a mouse drag a scroller, so horizontal chip bars and carousels
/// showed what fit and nothing past it. [NmMouseDragScroll] turns mouse
/// dragging on for the horizontal scroller under it.
void main() {
  Future<ScrollController> pumpRow(
    WidgetTester tester, {
    required bool wrap,
  }) async {
    final controller = ScrollController();
    Widget row = ListView(
      controller: controller,
      scrollDirection: Axis.horizontal,
      children: [
        for (var i = 0; i < 20; i++)
          const SizedBox(width: 100, child: Placeholder()),
      ],
    );
    if (wrap) row = NmMouseDragScroll(child: row);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SizedBox(height: 100, child: row)),
      ),
    );
    return controller;
  }

  Future<void> mouseDrag(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(-300, 0));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('without it a mouse drag does not move a horizontal list', (
    tester,
  ) async {
    final controller = await pumpRow(tester, wrap: false);
    await mouseDrag(tester);
    expect(controller.offset, 0);
  });

  testWidgets('with it a mouse drag scrolls the horizontal list', (
    tester,
  ) async {
    final controller = await pumpRow(tester, wrap: true);
    await mouseDrag(tester);
    expect(controller.offset, greaterThan(200));
  });

  testWidgets('touch dragging still works', (tester) async {
    final controller = await pumpRow(tester, wrap: true);
    await tester.drag(find.byType(ListView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(200));
  });
}
