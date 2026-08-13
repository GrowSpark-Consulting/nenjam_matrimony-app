import 'package:flutter/material.dart';

import '../../theme/app_typography.dart';

/// Instagram/WhatsApp-style count bubble that floats over a navigation icon.
///
/// Purely decorative: it never takes a tap (see the [IgnorePointer] below) so
/// the nav item underneath stays fully tappable even where the badge overlaps
/// it, and it carries no semantics of its own — the host nav item folds the
/// count into its own accessibility label instead, so a screen reader reads
/// "Inbox, 3 unread messages" as one node rather than "Inbox" then "3".
///
/// Stays in the widget tree at every count, including zero: [AnimatedScale]
/// only plays the pop-in/pop-out if the widget persists across the change,
/// which is also why this doesn't do its own `if (count > 0)`. Same reasoning
/// as `UnreadBadge` on the Inbox tabs — that one is an inline count pill sized
/// for a text row; this one is the floating overlay for an icon.
class NavBadge extends StatelessWidget {
  /// Badge fill — the standard iOS/Instagram notification red.
  static const Color badgeColor = Color(0xFFFF2D55);

  /// Minimum diameter. A single digit renders as an exact circle at this
  /// size; wider content ("12", "99+") grows it into a pill.
  static const double minSize = 18;

  /// Ring separating the badge from the icon behind it.
  static const double borderWidth = 2;

  /// Counts above this render as "99+".
  static const int maxCount = 99;

  final int count;

  /// Colour of the surrounding ring — pass the surface the badge sits on so
  /// it reads as a cut-out. Defaults to white (the light-theme nav bar).
  final Color borderColor;

  const NavBadge({
    super.key,
    required this.count,
    this.borderColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedScale(
          scale: count > 0 ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: Container(
            constraints: const BoxConstraints(
              minWidth: minSize,
              minHeight: minSize,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: badgeColor,
              // Stadium rather than a fixed circle: "99+" is wider than it is
              // tall, and a `shape: BoxShape.circle` would clip it.
              borderRadius: BorderRadius.circular(minSize),
              border: Border.all(color: borderColor, width: borderWidth),
            ),
            // Shrink-wrapping [Center] rather than `Container.alignment`:
            // the latter wraps the child in a *filling* Align, so inside the
            // loose constraints of a `Positioned(top:, right:)` the bubble
            // would stretch to the whole icon instead of hugging its digits.
            // With both factors at 1 the box still takes its size from the
            // text (floored by the min constraints above) while keeping the
            // digits optically centred in it.
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                count > maxCount ? '$maxCount+' : '$count',
                textAlign: TextAlign.center,
                // Clamped rather than fixed: the badge grows with the OS text
                // size (its min constraints are a floor, not a fixed size) so
                // the count stays legible, but an extreme accessibility scale
                // can't blow an 18px bubble out over the whole nav bar.
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.3),
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  // Kills the font's default leading so the digits sit
                  // optically centred in the bubble instead of low.
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
