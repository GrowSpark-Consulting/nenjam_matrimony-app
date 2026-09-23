import 'package:flutter/material.dart';

/// The shell every profile section shares: horizontally-padded content that
/// scrolls on its own.
///
/// [scrollable] exists because a section is sometimes placed inside a parent
/// that already owns the viewport (a section edit page's scroll view, see
/// ProfileSectionEditPage). A section that still wrapped itself in a
/// [SingleChildScrollView] there would be a nested viewport given unbounded
/// height — the classic "Vertical viewport was given unbounded height"
/// crash. Passing false drops the scroll view and keeps the padding, so
/// spacing is identical either way.
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
