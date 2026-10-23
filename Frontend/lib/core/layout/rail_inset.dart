import 'package:flutter/widgets.dart';

/// How much of the window's width a navigation rail takes beside the pages
/// below this widget — 0 where no rail is drawn.
///
/// Published by the desktop frame that draws the rail. For layout that
/// measures the window (`MediaQuery`) rather than its own constraints: the
/// window minus [of] is the page's real width.
class NmRailInset extends InheritedWidget {
  final double width;

  const NmRailInset({super.key, required this.width, required super.child});

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NmRailInset>()?.width ?? 0;

  @override
  bool updateShouldNotify(NmRailInset oldWidget) => width != oldWidget.width;
}
