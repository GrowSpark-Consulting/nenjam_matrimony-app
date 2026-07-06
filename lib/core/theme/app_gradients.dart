import 'package:flutter/material.dart';

/// Nenjam Matrimony — Gradient System
///
/// Premium gradients used throughout the app for buttons,
/// cards, backgrounds, and overlay effects.
abstract final class AppGradients {
  // ─── Primary Gradients ───────────────────────────────────────────
  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B2B4B), Color(0xFF2D4A7A)],
  );

  static const LinearGradient primaryVertical = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1B2B4B), Color(0xFF2D4A7A)],
  );

  static const LinearGradient primarySubtle = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B2B4B), Color(0xFF1F3460)],
  );

  // ─── Gold / Premium Gradients ────────────────────────────────────
  static const LinearGradient gold = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC9A84C), Color(0xFFE2CC7E)],
  );

  static const LinearGradient goldButton = gold;

  static const LinearGradient goldShimmer = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFA8882E),
      Color(0xFFC9A84C),
      Color(0xFFE2CC7E),
      Color(0xFFC9A84C),
    ],
    stops: [0.0, 0.3, 0.6, 1.0],
  );

  static const LinearGradient premiumCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B2B4B), Color(0xFF2D4A7A), Color(0xFF1B2B4B)],
    stops: [0.0, 0.5, 1.0],
  );

  // ─── Background Gradients ────────────────────────────────────────
  static const LinearGradient backgroundLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFBF9F4), Color(0xFFFFFFFF)],
  );

  static const LinearGradient backgroundDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0F1117), Color(0xFF1A1D27)],
  );

  // ─── Card Gradients ──────────────────────────────────────────────
  static const LinearGradient cardGlass = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x1AFFFFFF),
      Color(0x0DFFFFFF),
    ],
  );

  static const LinearGradient cardGlassDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x1A1E2230),
      Color(0x0D1E2230),
    ],
  );

  // ─── Overlay Gradients ───────────────────────────────────────────
  static const LinearGradient imageOverlay = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.transparent,
      Color(0x80000000),
    ],
  );

  static const LinearGradient imageOverlayStrong = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.transparent,
      Color(0x33000000),
      Color(0xCC000000),
    ],
    stops: [0.0, 0.4, 1.0],
  );

  // ─── Status Gradients ────────────────────────────────────────────
  static const LinearGradient success = LinearGradient(
    colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
  );

  static const LinearGradient error = LinearGradient(
    colors: [Color(0xFFE74C3C), Color(0xFFC0392B)],
  );

  // ─── Splash / Onboarding ─────────────────────────────────────────
  static const LinearGradient splash = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF1B2B4B),
      Color(0xFF2D4A7A),
      Color(0xFF1B2B4B),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  static const RadialGradient splashRadial = RadialGradient(
    center: Alignment.center,
    radius: 1.2,
    colors: [
      Color(0xFF2D4A7A),
      Color(0xFF1B2B4B),
    ],
  );
}
