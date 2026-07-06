import 'package:flutter/material.dart';

/// Nenjam Matrimony — Spacing & Border Radius System
///
/// Consistent spacing scale based on a 4px grid.
/// All spacing in the app must use these tokens.
abstract final class AppSpacing {
  // ─── Spacing Scale (4px base grid) ───────────────────────────────
  static const double xs2 = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double base = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xl2 = 32;
  static const double xl3 = 40;
  static const double xl4 = 48;
  static const double xl5 = 56;
  static const double xl6 = 64;
  static const double xl7 = 80;
  static const double xl8 = 96;

  // ─── Page Padding ────────────────────────────────────────────────
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: base,
  );

  static const EdgeInsets pageHorizontal = EdgeInsets.symmetric(
    horizontal: lg,
  );

  static const EdgeInsets pageVertical = EdgeInsets.symmetric(
    vertical: base,
  );

  // ─── Card Padding ────────────────────────────────────────────────
  static const EdgeInsets cardPadding = EdgeInsets.all(base);

  static const EdgeInsets cardPaddingLarge = EdgeInsets.all(lg);

  static const EdgeInsets cardPaddingCompact = EdgeInsets.all(md);

  // ─── Section Spacing ─────────────────────────────────────────────
  static const double sectionGap = xl2;
  static const double itemGap = md;
  static const double listItemGap = sm;

  // ─── Border Radius ───────────────────────────────────────────────
  static const double radiusXs = 4;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radiusXl2 = 24;
  static const double radiusXl3 = 28;
  static const double radiusFull = 999;

  // ─── Common BorderRadius Objects ─────────────────────────────────
  static final BorderRadius borderRadiusSm = BorderRadius.circular(radiusSm);
  static final BorderRadius borderRadiusMd = BorderRadius.circular(radiusMd);
  static final BorderRadius borderRadiusLg = BorderRadius.circular(radiusLg);
  static final BorderRadius borderRadiusXl = BorderRadius.circular(radiusXl);
  static final BorderRadius borderRadiusXl2 = BorderRadius.circular(radiusXl2);
  static final BorderRadius borderRadiusFull = BorderRadius.circular(radiusFull);

  // ─── Bottom Sheet ────────────────────────────────────────────────
  static const BorderRadius bottomSheetRadius = BorderRadius.vertical(
    top: Radius.circular(radiusXl3),
  );
}
