import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/layout/adaptive_grid.dart';

void main() {
  GridMetrics at(double width) => AdaptiveGrid.resolve(
    availableWidth: width,
    horizontalPadding: 32,
    spacing: 16,
  );

  group('column count derives from post-padding width', () {
    test('a 320px phone gets one column', () {
      expect(at(320).columns, 1);
    });

    test('column count grows monotonically with width', () {
      var previous = 0;
      for (var w = 320.0; w <= 3440; w += 20) {
        final columns = at(w).columns;
        expect(
          columns,
          greaterThanOrEqualTo(previous),
          reason: 'columns must never decrease as width grows (at ${w}px)',
        );
        previous = columns;
      }
    });

    test('is capped so ultrawide does not produce a dozen columns', () {
      expect(at(3440).columns, lessThanOrEqualTo(5));
    });
  });

  group('tile width', () {
    test('never exceeds the cap even on an ultrawide surface', () {
      for (final w in [1920.0, 2560.0, 3440.0]) {
        expect(
          at(w).tileWidth,
          lessThanOrEqualTo(420),
          reason: 'capping only the column count would yield giant cards',
        );
      }
    });

    test('tiles plus gutters fit the available width', () {
      for (var w = 320.0; w <= 3440; w += 37) {
        final m = at(w);
        final used = m.tileWidth * m.columns + m.gutter * (m.columns - 1);
        expect(
          used,
          lessThanOrEqualTo(w - 32 + 0.5),
          reason: 'grid must fit inside its padded width at ${w}px',
        );
      }
    });

    test('a narrow pane on a wide monitor yields one column', () {
      // The caller passes its LayoutBuilder width, not the window width.
      expect(at(360).columns, 1);
    });
  });

  group('degenerate input', () {
    test('always yields at least one column and a non-negative tile', () {
      final m = at(10);
      expect(m.columns, 1);
      expect(m.tileWidth, greaterThanOrEqualTo(0));
    });
  });
}
