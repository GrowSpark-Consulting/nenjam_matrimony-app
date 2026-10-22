import 'package:flutter/widgets.dart';

/// Maximum content widths, named by the **role of the content** rather than by
/// device, so each surface has one obvious choice.
///
/// Every value is a *maximum*. A surface narrower than its token fills the
/// space it has; it is never padded out to the token.
abstract final class ContentWidth {
  /// Text-heavy reading surfaces: settings, help, safety, privacy. Sized for a
  /// comfortable measure rather than for any particular screen.
  static const double prose = 680;

  /// A single-column form. Fields stay close to their labels instead of
  /// stretching a text input across a monitor.
  static const double form = 560;

  /// A form laid out in two columns on wide surfaces.
  static const double formWide = 900;

  /// A two-column detail surface (profile detail).
  static const double detail = 1200;
}

/// Centers [child] in a column no wider than [maxWidth].
///
/// Use one of the [ContentWidth] tokens for [maxWidth]. This replaces the old
/// global `NmAppFrame` clamp: instead of bounding the whole app (which also
/// hid the real window width from every descendant), each surface bounds
/// itself, so grids and two-pane layouts can still use the full width.
class NmContentWidth extends StatelessWidget {
  final double maxWidth;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const NmContentWidth({
    super.key,
    required this.maxWidth,
    required this.child,
    this.padding,
  });

  /// The §4.1 derivation: how much width content actually gets.
  ///
  /// [availableWidth] must already be post-navigation — in practice it is a
  /// `LayoutBuilder`'s `constraints.maxWidth` inside the shell's content area,
  /// which is a sibling of the rail and so never includes it. Pass the
  /// surface's own horizontal padding (both sides) as [horizontalPadding].
  ///
  /// Returns the smaller of the padded available width and [maxWidth], floored
  /// at 0 so a degenerate surface cannot produce a negative constraint.
  static double usableWidth({
    required double availableWidth,
    required double horizontalPadding,
    required double maxWidth,
  }) {
    if (availableWidth == double.infinity) return maxWidth;
    final padded = availableWidth - horizontalPadding;
    if (padded <= 0) return 0;
    return padded < maxWidth ? padded : maxWidth;
  }

  @override
  Widget build(BuildContext context) {
    final body = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: body,
      ),
    );
  }
}
