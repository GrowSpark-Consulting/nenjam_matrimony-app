import 'dart:math' as math;

/// A resolved grid: how many columns, how wide each tile, and the gutter.
class GridMetrics {
  final int columns;
  final double tileWidth;
  final double gutter;

  const GridMetrics({
    required this.columns,
    required this.tileWidth,
    required this.gutter,
  });

  @override
  bool operator ==(Object other) =>
      other is GridMetrics &&
      other.columns == columns &&
      other.tileWidth == tileWidth &&
      other.gutter == gutter;

  @override
  int get hashCode => Object.hash(columns, tileWidth, gutter);

  @override
  String toString() =>
      'GridMetrics(columns: $columns, tileWidth: $tileWidth, gutter: $gutter)';
}

/// Derives grid metrics from the width a surface actually has.
///
/// Column count comes from a target tile width rather than a
/// breakpoint-to-count lookup table, so intermediate widths and continuous
/// browser resizing behave correctly instead of snapping at a few hardcoded
/// sizes.
///
/// Both the column count *and* the tile width are capped: capping only the
/// columns would let a 3440px surface render four 800px cards.
abstract final class AdaptiveGrid {
  static GridMetrics resolve({
    required double availableWidth,
    required double horizontalPadding,
    required double spacing,
    double targetTileWidth = 320,
    double maxTileWidth = 420,
    int maxColumns = 5,
  }) {
    final padded = availableWidth - horizontalPadding;
    if (padded <= 0) {
      return GridMetrics(columns: 1, tileWidth: 0, gutter: spacing);
    }

    // How many tiles of roughly the target width fit, counting the gutters
    // between them.
    var columns = ((padded + spacing) / (targetTileWidth + spacing)).floor();
    columns = columns.clamp(1, maxColumns);

    var tileWidth = (padded - spacing * (columns - 1)) / columns;

    // If that leaves tiles wider than the cap, add columns until they fit or
    // the column cap is reached.
    while (tileWidth > maxTileWidth && columns < maxColumns) {
      columns += 1;
      tileWidth = (padded - spacing * (columns - 1)) / columns;
    }

    // At the column cap on a very wide surface, stop growing the tiles: the
    // grid then sits narrower than its container rather than stretching.
    tileWidth = math.min(tileWidth, maxTileWidth);

    return GridMetrics(
      columns: columns,
      tileWidth: math.max(0, tileWidth),
      gutter: spacing,
    );
  }
}
