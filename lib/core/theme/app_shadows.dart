import 'package:flutter/material.dart';

/// Nenjam Matrimony — Shadow System
///
/// Soft, elegant shadow presets that maintain the luxury aesthetic.
abstract final class AppShadows {
  // ─── Card Shadows ────────────────────────────────────────────────
  static List<BoxShadow> get cardLight => const [
        BoxShadow(
          color: Color(0x0A1B2B4B),
          blurRadius: 12,
          offset: Offset(0, 4),
          spreadRadius: 0,
        ),
        BoxShadow(
          color: Color(0x051B2B4B),
          blurRadius: 4,
          offset: Offset(0, 2),
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get cardDark => const [
        BoxShadow(
          color: Color(0x30000000),
          blurRadius: 12,
          offset: Offset(0, 4),
          spreadRadius: 0,
        ),
      ];

  // ─── Elevated Shadows ────────────────────────────────────────────
  static List<BoxShadow> get elevated => const [
        BoxShadow(
          color: Color(0x141B2B4B),
          blurRadius: 24,
          offset: Offset(0, 8),
          spreadRadius: 0,
        ),
        BoxShadow(
          color: Color(0x0A1B2B4B),
          blurRadius: 8,
          offset: Offset(0, 4),
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get elevatedDark => const [
        BoxShadow(
          color: Color(0x50000000),
          blurRadius: 24,
          offset: Offset(0, 8),
          spreadRadius: 0,
        ),
      ];

  // ─── Subtle Shadows ──────────────────────────────────────────────
  static List<BoxShadow> get subtle => const [
        BoxShadow(
          color: Color(0x071B2B4B),
          blurRadius: 8,
          offset: Offset(0, 2),
          spreadRadius: 0,
        ),
      ];

  // ─── Bottom Navigation Shadow ────────────────────────────────────
  static List<BoxShadow> get bottomNav => const [
        BoxShadow(
          color: Color(0x0F1B2B4B),
          blurRadius: 20,
          offset: Offset(0, -4),
          spreadRadius: 0,
        ),
      ];

  // ─── Button Shadows ──────────────────────────────────────────────
  static List<BoxShadow> get button => const [
        BoxShadow(
          color: Color(0x1A1B2B4B),
          blurRadius: 12,
          offset: Offset(0, 4),
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get buttonPressed => const [
        BoxShadow(
          color: Color(0x0F1B2B4B),
          blurRadius: 6,
          offset: Offset(0, 2),
          spreadRadius: 0,
        ),
      ];

  // ─── Gold / Premium Shadow ───────────────────────────────────────
  static List<BoxShadow> get goldGlow => const [
        BoxShadow(
          color: Color(0x30C9A84C),
          blurRadius: 16,
          offset: Offset(0, 4),
          spreadRadius: 0,
        ),
      ];

  // ─── Inner Shadows (for depth effects) ───────────────────────────
  static List<BoxShadow> get innerSubtle => const [
        BoxShadow(
          color: Color(0x08000000),
          blurRadius: 4,
          offset: Offset(0, 2),
          spreadRadius: -2,
        ),
      ];

  // ─── Aliases for Elevation & Tokens ──────────────────────────────
  static List<BoxShadow> get floatingLight => elevated;
  static List<BoxShadow> get floatingDark => elevatedDark;
  static List<BoxShadow> get glowGold => goldGlow;

  /// No shadow — used to explicitly clear shadows
  static List<BoxShadow> get none => const [];
}
