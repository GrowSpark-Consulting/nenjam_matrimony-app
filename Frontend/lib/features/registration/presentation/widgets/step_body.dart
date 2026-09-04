import 'package:flutter/material.dart';

/// The shell every profile section shares: horizontally-padded content that
/// scrolls on its own.
///
/// [scrollable] exists because the same section widgets are rendered in two
/// places. Opened one at a time they own the viewport and must scroll
/// themselves. Stacked together on Edit Profile's single editable page
/// (ProfileEditPage) the parent owns the one viewport, and a section that
/// still wrapped itself in a [SingleChildScrollView] would be a nested
/// viewport given unbounded height — the classic "Vertical viewport was
/// given unbounded height" crash. Passing false drops the scroll view and
/// keeps the padding, so spacing is identical either way.
class StepBody extends StatelessWidget {
  final bool scrollable;
  final Widget child;

  const StepBody({super.key, required this.scrollable, required this.child});

  static const EdgeInsets _padding = EdgeInsets.symmetric(horizontal: 24);

  @override
  Widget build(BuildContext context) => scrollable
      ? SingleChildScrollView(padding: _padding, child: child)
      : Padding(padding: _padding, child: child);
}
