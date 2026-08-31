import 'package:flutter/material.dart';

/// Nenjam Matrimony — Gradient System
///
/// Three brand gradients carry the identity — [primary], [deep] and [match].
/// Everything else here is a supporting wash (backgrounds, photo scrims,
/// status). Gradients are a *highlight*, not a background treatment: use them
/// on primary CTAs, the splash, progress indicators, and match celebration —
/// never as the fill of a whole content screen.
abstract final class AppGradients {
  // ─── Signature Brand Gradients ───────────────────────────────────
  /// Deep Purple → Plum → Magenta → Rose. The primary CTA / brand gradient.
  ///
  /// The deep-purple anchor is what gives the ramp its depth: starting at
  /// plum made CTAs read as a flat mid-purple wash, because the darkest
  /// value on the button was already halfway up the brand scale. Stops are
  /// near-even so the four hues blend continuously rather than banding —
  /// the compressed `[0, 0.4, 0.75, 1]` spacing squeezed rose into the last
  /// quarter and left the first 40% almost single-hue.
  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF4C1D95),
      Color(0xFF6B21A8),
      Color(0xFFA30D91),
      Color(0xFFD4147D),
      Color(0xFFE95793),
    ],
    stops: [0.0, 0.22, 0.5, 0.78, 1.0],
  );

  /// Deep purple → plum. Reserved for dark brand surfaces and overlays.
  static const LinearGradient deep = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4C1D95), Color(0xFF6B21A8), Color(0xFF940B92)],
  );

  /// Plum → Magenta → Rose, warmer and shorter. Match states and celebration.
  static const LinearGradient match = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF940B92), Color(0xFFD4147D), Color(0xFFE95793)],
  );

  // ─── Primary Variants ────────────────────────────────────────────
  static const LinearGradient primaryVertical = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF4C1D95),
      Color(0xFF6B21A8),
      Color(0xFFA30D91),
      Color(0xFFD4147D),
      Color(0xFFE95793),
    ],
    stops: [0.0, 0.22, 0.5, 0.78, 1.0],
  );

  /// Two-stop plum, for large fills where the full four-stop ramp would
  /// read as too loud (headers, wide banners).
  static const LinearGradient primarySubtle = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6B21A8), Color(0xFF8B3FC4)],
  );

  /// Plum → Magenta. The two-stop progress / completion ramp.
  static const LinearGradient progress = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF6B21A8), Color(0xFFD4147D)],
  );

  // ─── Accent / Premium Gradients ──────────────────────────────────
  /// Deep Magenta → Magenta. Secondary CTAs, badges, highlight pills.
  ///
  /// Runs `secondaryDark → secondary` rather than reaching into rose: white
  /// label text over the old magenta→rose ramp bottomed out around 3.8:1,
  /// under AA for the 14px semibold button style, and spending the 5% rose
  /// on every secondary CTA is what tipped the app toward reading pink.
  /// Rose stays reserved for genuine emotional accents.
  static const LinearGradient accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFA80F63), Color(0xFFD4147D)],
  );

  static const LinearGradient accentButton = accent;

  /// Four-stop magenta ramp used for shimmer sweeps on premium surfaces.
  static const LinearGradient accentShimmer = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFA80F63),
      Color(0xFFD4147D),
      Color(0xFFF58CB4),
      Color(0xFFD4147D),
    ],
    stops: [0.0, 0.3, 0.6, 1.0],
  );

  /// Deep plum card fill for premium/subscription surfaces.
  static const LinearGradient premiumCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B1173), Color(0xFF6B21A8), Color(0xFF940B92)],
    stops: [0.0, 0.55, 1.0],
  );

  // ─── Background Gradients ────────────────────────────────────────
  static const LinearGradient backgroundLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF9FC), Color(0xFFFFFFFF)],
  );

  static const LinearGradient backgroundDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF14101A), Color(0xFF1E1826)],
  );

  // ─── Card Gradients ──────────────────────────────────────────────
  static const LinearGradient cardGlass = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x1AFFFFFF), Color(0x0DFFFFFF)],
  );

  static const LinearGradient cardGlassDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x1A2B2235), Color(0x0D2B2235)],
  );

  // ─── Overlay Gradients ───────────────────────────────────────────
  /// Plum-tinted photo scrim — keeps skin tones warm where a neutral black
  /// scrim would flatten them.
  static const LinearGradient imageOverlay = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0x992A0B3F)],
  );

  static const LinearGradient imageOverlayStrong = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0x4D2A0B3F), Color(0xF22A0B3F)],
    stops: [0.0, 0.4, 1.0],
  );

  // ─── Status Gradients ────────────────────────────────────────────
  static const LinearGradient success = LinearGradient(
    colors: [Color(0xFF27A776), Color(0xFF1E8E5F)],
  );

  static const LinearGradient error = LinearGradient(
    colors: [Color(0xFFE24E5E), Color(0xFFD92D3F)],
  );

  // ─── Splash / Onboarding ─────────────────────────────────────────
  /// Strongest brand treatment in the app: deep plum → magenta → rose.
  static const LinearGradient splash = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF3B1173),
      Color(0xFF6B21A8),
      Color(0xFF940B92),
      Color(0xFFD4147D),
      Color(0xFFE95793),
    ],
    stops: [0.0, 0.28, 0.55, 0.8, 1.0],
  );

  static const RadialGradient splashRadial = RadialGradient(
    center: Alignment.center,
    radius: 1.2,
    colors: [Color(0xFF940B92), Color(0xFF3B1173)],
  );
}
