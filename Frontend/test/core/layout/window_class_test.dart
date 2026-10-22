import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/layout/window_class.dart';

void main() {
  group('WindowClass.fromWidth half-open intervals', () {
    test('classifies every boundary pair', () {
      expect(WindowClass.fromWidth(0), WindowClass.compact);
      expect(WindowClass.fromWidth(320), WindowClass.compact);
      expect(WindowClass.fromWidth(599), WindowClass.compact);
      expect(WindowClass.fromWidth(600), WindowClass.medium);
      expect(WindowClass.fromWidth(899), WindowClass.medium);
      expect(WindowClass.fromWidth(900), WindowClass.expanded);
      expect(WindowClass.fromWidth(1199), WindowClass.expanded);
      expect(WindowClass.fromWidth(1200), WindowClass.large);
      expect(WindowClass.fromWidth(3440), WindowClass.large);
    });

    test('599.9 is still compact and 600.0 is medium', () {
      expect(WindowClass.fromWidth(599.9), WindowClass.compact);
      expect(WindowClass.fromWidth(600.0), WindowClass.medium);
    });

    test('tolerates infinite and negative widths without throwing', () {
      expect(WindowClass.fromWidth(double.infinity), WindowClass.large);
      expect(WindowClass.fromWidth(-10), WindowClass.compact);
    });
  });

  group('resolve', () {
    test('falls back down the chain when a tier is omitted', () {
      expect(
        WindowClass.large.resolve(compact: 1, medium: 2),
        2,
        reason: 'large falls back to expanded, then medium',
      );
      expect(WindowClass.expanded.resolve(compact: 1), 1);
      expect(WindowClass.large.resolve(compact: 1, large: 9), 9);
    });
  });

  group('threshold getters', () {
    test('isAtLeastExpanded is true from 900 up', () {
      expect(WindowClass.medium.isAtLeastExpanded, isFalse);
      expect(WindowClass.expanded.isAtLeastExpanded, isTrue);
      expect(WindowClass.large.isAtLeastExpanded, isTrue);
    });
  });

  group('WindowClass.of', () {
    testWidgets('reads the real MediaQuery width', (tester) async {
      late WindowClass seen;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1440, 900)),
          child: Builder(
            builder: (context) {
              seen = WindowClass.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(seen, WindowClass.large);
    });

    testWidgets('a narrow pane on a large window classifies as compact '
        'when read from local constraints', (tester) async {
      late WindowClass paneClass;
      late double paneWidth;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1920, 1080)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            // Align loosens the incoming constraint. Without it the SizedBox
            // is the direct child of pumpWidget's root, receives a TIGHT
            // constraint equal to the test surface, and cannot narrow itself
            // -- the LayoutBuilder would then see the surface width (800),
            // classify as medium, and prove nothing about a narrow pane.
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    paneWidth = constraints.maxWidth;
                    paneClass = WindowClass.fromWidth(paneWidth);
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      // Pin the premise: the LayoutBuilder must really see the 400px pane.
      // Without this assertion the class check alone would not show that.
      expect(paneWidth, 400);
      expect(
        paneClass,
        WindowClass.compact,
        reason: 'local constraints, not the 1920px window, decide a pane',
      );
    });
  });
}
