import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Lets a mouse drag the horizontal scroller below it.
///
/// Flutter leaves the mouse out of [ScrollBehavior.dragDevices], and a plain
/// mouse wheel only scrolls vertically — so in a browser a horizontal chip bar
/// or carousel showed what fit and nothing past it. Wrap horizontal scrollers
/// only: vertical lists already scroll with the wheel, and a mouse drag starts
/// after 1px of movement, so turning it on everywhere would let a slightly
/// shaky click on any list item become a scroll instead of a tap.
class NmMouseDragScroll extends StatelessWidget {
  final Widget child;

  const NmMouseDragScroll({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context);
    return ScrollConfiguration(
      behavior: behavior.copyWith(
        dragDevices: {...behavior.dragDevices, PointerDeviceKind.mouse},
      ),
      child: child,
    );
  }
}
