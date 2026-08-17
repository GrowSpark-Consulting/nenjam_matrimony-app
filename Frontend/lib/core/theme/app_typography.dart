import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Nenjam Matrimony — Typography System
///
/// Primary: Inter — clean, modern, highly legible
/// Display: Poppins — geometric, premium, impactful headings
/// Tamil:   Noto Sans Tamil — fallback only, see [_tamilFallback]
///
/// Uses Google Fonts for dynamic loading with fallbacks.
abstract final class AppTypography {
  // ─── Font Families ───────────────────────────────────────────────
  static String get primaryFamily => 'Inter';
  static String get displayFamily => 'Poppins';

  /// Neither Inter nor Poppins ships Tamil glyphs, so every `ta` string
  /// would otherwise render as tofu (□□□) or get silently swapped to
  /// whatever the platform picks — which differs per OS and ignores the
  /// weight/size the style asked for.
  ///
  /// Declared as a *fallback* rather than swapping the family per-locale on
  /// purpose: fallback resolution is per-glyph, so Latin text keeps Inter /
  /// Poppins exactly as before (including inside a Tamil sentence — names,
  /// numerals, "Nenjam"), and only the codepoints Inter lacks come from Noto.
  /// That means the English UI is byte-for-byte unchanged, and a mixed
  /// Tamil/English string doesn't flip fonts mid-line.
  ///
  /// Resolved once and cached: each `GoogleFonts.notoSansTamil()` call
  /// registers a font loader, so calling it inside every style getter (which
  /// rebuild on every frame) would thrash. The getter is only touched for
  /// its `fontFamily` name — the returned style itself is discarded.
  static final List<String> _tamilFallback = <String>[
    GoogleFonts.notoSansTamil().fontFamily!,
  ];

  /// Poppins + Tamil fallback — display/heading styles.
  static TextStyle _display({
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) => GoogleFonts.poppins(
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    height: height,
  ).copyWith(fontFamilyFallback: _tamilFallback);

  /// Inter + Tamil fallback — body/label styles.
  static TextStyle _body({
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) => GoogleFonts.inter(
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    height: height,
  ).copyWith(fontFamilyFallback: _tamilFallback);

  // ─── Display Styles (Poppins) ────────────────────────────────────
  static TextStyle get displayLarge => _display(
    fontSize: 57,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.25,
    height: 1.12,
  );

  static TextStyle get displayMedium => _display(
    fontSize: 45,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.16,
  );

  static TextStyle get displaySmall => _display(
    fontSize: 36,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.22,
  );

  // ─── Headline Styles (Poppins) ───────────────────────────────────
  static TextStyle get headlineLarge => _display(
    fontSize: 32,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.25,
  );

  static TextStyle get headlineMedium => _display(
    fontSize: 28,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.29,
  );

  static TextStyle get headlineSmall => _display(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.33,
  );

  // ─── Title Styles (Poppins) ──────────────────────────────────────
  static TextStyle get titleLarge => _display(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.27,
  );

  static TextStyle get titleMedium => _display(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.15,
    height: 1.50,
  );

  static TextStyle get titleSmall => _display(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.43,
  );

  // ─── Body Styles (Inter) ─────────────────────────────────────────
  static TextStyle get bodyLarge => _body(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.5,
    height: 1.50,
  );

  static TextStyle get bodyMedium => _body(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.25,
    height: 1.43,
  );

  static TextStyle get bodySmall => _body(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
    height: 1.33,
  );

  // ─── Label / Caption Styles (Inter) ──────────────────────────────
  static TextStyle get labelLarge => _body(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    height: 1.43,
  );

  static TextStyle get labelMedium => _body(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    height: 1.33,
  );

  static TextStyle get labelSmall => _body(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    height: 1.45,
  );

  static TextStyle get caption => labelSmall;

  // ─── Button Style ────────────────────────────────────────────────
  static TextStyle get button => _body(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    height: 1.43,
  );

  static TextStyle get buttonLarge => _body(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    height: 1.50,
  );

  // ─── Domain Specific Luxury Typography ───────────────────────────
  static TextStyle get otpDigits =>
      _display(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 8);

  static TextStyle get profileName =>
      _display(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 0.2);

  static TextStyle get profileMetadata =>
      _body(fontSize: 13, fontWeight: FontWeight.w400, letterSpacing: 0.2);

  static TextStyle get chatMessages =>
      _body(fontSize: 15, fontWeight: FontWeight.w400, height: 1.4);

  static TextStyle get subscriptionTitles =>
      _display(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.3);

  // ─── Complete TextTheme ──────────────────────────────────────────
  static TextTheme get textTheme => TextTheme(
    displayLarge: displayLarge,
    displayMedium: displayMedium,
    displaySmall: displaySmall,
    headlineLarge: headlineLarge,
    headlineMedium: headlineMedium,
    headlineSmall: headlineSmall,
    titleLarge: titleLarge,
    titleMedium: titleMedium,
    titleSmall: titleSmall,
    bodyLarge: bodyLarge,
    bodyMedium: bodyMedium,
    bodySmall: bodySmall,
    labelLarge: labelLarge,
    labelMedium: labelMedium,
    labelSmall: labelSmall,
  );
}
