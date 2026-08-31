import 'package:flutter/material.dart';

/// Nenjam Matrimony — Shadow System
///
/// Soft, plum-tinted shadows. A neutral black shadow over the warm-white
/// background reads as grey dirt; tinting toward the deep plum text colour
/// keeps surfaces looking lifted rather than smudged.
///
/// Shadows here are deliberately light — depth comes from the lavender
/// borders in [AppDecorations], not from heavy elevation.
abstract final class AppShadows {
  // ─── Card Shadows ────────────────────────────────────────────────
  static List<BoxShadow> get cardLight => const [
    BoxShadow(
      color: Color(0x0A21152B),
      blurRadius: 12,
      offset: Offset(0, 4),
      spreadRadius: 0,
    ),
    BoxShadow(
      color: Color(0x0521152B),
      blurRadius: 4,
      offset: Offset(0, 2),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get cardDark => const [
    BoxShadow(
      color: Color(0x40000000),
      blurRadius: 12,
      offset: Offset(0, 4),
      spreadRadius: 0,
    ),
  ];

  // ─── Elevated Shadows ────────────────────────────────────────────
  static List<BoxShadow> get elevated => const [
    BoxShadow(
      color: Color(0x1421152B),
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: 0,
    ),
    BoxShadow(
      color: Color(0x0A21152B),
      blurRadius: 8,
      offset: Offset(0, 4),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get elevatedDark => const [
    BoxShadow(
      color: Color(0x59000000),
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: 0,
    ),
  ];

  // ─── Subtle Shadows ──────────────────────────────────────────────
  static List<BoxShadow> get subtle => const [
    BoxShadow(
      color: Color(0x0721152B),
      blurRadius: 8,
      offset: Offset(0, 2),
      spreadRadius: 0,
    ),
  ];

  // ─── Bottom Navigation Shadow ────────────────────────────────────
  static List<BoxShadow> get bottomNav => const [
    BoxShadow(
      color: Color(0x0F21152B),
      blurRadius: 20,
      offset: Offset(0, -4),
      spreadRadius: 0,
    ),
  ];

  // ─── Button Shadows ──────────────────────────────────────────────
  /// Plum-tinted lift under the primary gradient CTA.
  static List<BoxShadow> get button => const [
    BoxShadow(
      color: Color(0x2E6B21A8),
      blurRadius: 16,
      offset: Offset(0, 6),
      spreadRadius: -2,
    ),
  ];

  static List<BoxShadow> get buttonPressed => const [
    BoxShadow(
      color: Color(0x1F6B21A8),
      blurRadius: 6,
      offset: Offset(0, 2),
      spreadRadius: -1,
    ),
  ];

  // ─── Accent / Premium Glow ───────────────────────────────────────
  /// Magenta glow — premium surfaces, match celebration, badges.
  static List<BoxShadow> get accentGlow => const [
    BoxShadow(
      color: Color(0x33D4147D),
      blurRadius: 18,
      offset: Offset(0, 6),
      spreadRadius: -2,
    ),
  ];

  /// Focus ring for inputs and selectable cards.
  static List<BoxShadow> get focusRing => const [
    BoxShadow(
      color: Color(0x1F6B21A8),
      blurRadius: 10,
      offset: Offset(0, 2),
      spreadRadius: 0,
    ),
  ];

  // ─── Inner Shadows (for depth effects) ───────────────────────────
  static List<BoxShadow> get innerSubtle => const [
    BoxShadow(
      color: Color(0x0821152B),
      blurRadius: 4,
      offset: Offset(0, 2),
      spreadRadius: -2,
    ),
  ];

  // ─── Aliases for Elevation & Tokens ──────────────────────────────
  static List<BoxShadow> get floatingLight => elevated;
  static List<BoxShadow> get floatingDark => elevatedDark;
  static List<BoxShadow> get glowAccent => accentGlow;

  /// No shadow — used to explicitly clear shadows
  static List<BoxShadow> get none => const [];
}
