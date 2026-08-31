import 'package:flutter/material.dart';

/// Nenjam Matrimony — Complete Color System
///
/// Brand direction: **Plum + Magenta + Rose** — modern, emotional, premium
/// and trustworthy. Built as a 60 / 25 / 10 / 5 system:
///
/// * **60%** neutral — warm white, white, very light lavender/blush
/// * **25%** plum / purple — primary actions, navigation, headings, brand
/// * **10%** magenta — secondary actions, highlights, match states
/// * **5%**  rose — emotional accents, celebration, badges
///
/// Every widget should read from these constants (or from `Theme.of(context)`)
/// rather than hardcoding `Color(0xFF…)`.
abstract final class AppColors {
  // ─── Brand Anchors ────────────────────────────────────────────────
  /// The four reference brand hues. Used to build gradients and to key the
  /// three Nenjam match scores; prefer the semantic aliases below in widgets.
  static const Color brandDeepPurple = Color(0xFF610C9F);
  static const Color brandPlum = Color(0xFF940B92);
  static const Color brandMagenta = Color(0xFFDA0C81);
  static const Color brandRose = Color(0xFFE95793);

  // ─── Primary Palette (Plum / Purple — 25%) ───────────────────────
  static const Color primary = Color(0xFF6B21A8);
  static const Color primaryLight = Color(0xFF8B3FC4);
  static const Color primaryDark = Color(0xFF4C1D95);
  static const Color primaryDeep = Color(0xFF3B1173);

  /// Very light lavender wash — selected states, containers, chips.
  static const Color primarySurface = Color(0xFFF3E8F7);
  static const Color primarySurfaceStrong = Color(0xFFE7D5F0);

  /// Alias matching the `softLavender` token in the brand spec.
  static const Color softLavender = primarySurface;

  // ─── Secondary / Accent (Magenta 10% · Rose 5%) ──────────────────
  static const Color secondary = Color(0xFFD4147D);
  static const Color secondaryLight = Color(0xFFE5479B);
  static const Color secondaryDark = Color(0xFFA80F63);
  static const Color secondarySurface = Color(0xFFFCE7F3);

  static const Color accent = Color(0xFFE95793);
  static const Color accentLight = Color(0xFFF58CB4);
  static const Color accentDark = Color(0xFFC93A73);

  /// Soft blush surface — the lightest accent tint.
  static const Color accentSoft = Color(0xFFFCE7F3);

  // ─── Background & Surface (Neutral — 60%) ────────────────────────
  static const Color backgroundLight = Color(0xFFFFF9FC);
  static const Color backgroundDark = Color(0xFF14101A);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E1826);
  static const Color surfaceVariantLight = Color(0xFFF7F1FA);
  static const Color surfaceVariantDark = Color(0xFF2A2133);

  /// Warm cream — reserved for premium surfaces.
  static const Color premiumCream = Color(0xFFFFF6EC);

  /// Light-theme shorthands matching the brand spec token names.
  static const Color background = backgroundLight;
  static const Color surface = surfaceLight;

  // ─── Card Colors ─────────────────────────────────────────────────
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF221A2B);
  static const Color cardElevatedLight = Color(0xFFFFFDFF);
  static const Color cardElevatedDark = Color(0xFF2B2235);

  // ─── Text Colors ─────────────────────────────────────────────────
  static const Color textPrimaryLight = Color(0xFF21152B);
  static const Color textPrimaryDark = Color(0xFFF4EFF7);
  static const Color textSecondaryLight = Color(0xFF756878);
  static const Color textSecondaryDark = Color(0xFFB7A9BF);
  static const Color textTertiaryLight = Color(0xFF7B6D83);
  static const Color textTertiaryDark = Color(0xFF877B90);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnSecondary = Color(0xFFFFFFFF);

  /// Light-theme shorthands matching the brand spec token names.
  ///
  /// Every one of these clears 4.5:1 against both [surfaceLight] and the
  /// warm-white [backgroundLight] — the muted tier in particular is darker
  /// than a purely visual read would suggest, because #FFF9FC is bright
  /// enough that a lighter mauve drops below AA for body text.
  static const Color textPrimary = textPrimaryLight;
  static const Color textSecondary = textSecondaryLight;
  static const Color textMuted = textTertiaryLight;

  // ─── Status Colors ───────────────────────────────────────────────
  static const Color success = Color(0xFF17754D);
  static const Color successLight = Color(0xFFE6F6EF);
  static const Color warning = Color(0xFF9A5A00);
  static const Color warningLight = Color(0xFFFDF3E3);
  static const Color error = Color(0xFFD92D3F);
  static const Color errorLight = Color(0xFFFDEAEC);
  static const Color info = Color(0xFF3462D6);
  static const Color infoLight = Color(0xFFEBF0FD);

  // ─── Semantic Colors ─────────────────────────────────────────────
  static const Color verified = Color(0xFF2563EB);
  static const Color verifiedBlue = Color(0xFF2563EB);

  /// Premium membership accent. The Silver / Gold *plans* are unchanged —
  /// only their visual treatment moved to the plum/magenta system.
  static const Color premium = secondary;
  static const Color premiumBright = accent;
  static const Color faceVerificationGreen = success;
  static const Color online = Color(0xFF12924E);
  static const Color offline = Color(0xFF9E9E9E);
  static const Color liked = accent;
  static const Color shortlisted = brandPlum;
  static const Color disabled = Color(0xFFC9BFD1);

  // ─── Nenjam 3-Score Match System ─────────────────────────────────
  /// Deep purple keys astrology, magenta keys psychology (OCEAN), and rose
  /// keys the demographic score — so the three read apart at a glance.
  static const Color scoreAstrology = brandDeepPurple;
  static const Color scorePsychology = secondary;
  static const Color scoreDemographic = accent;

  // ─── Divider & Border ────────────────────────────────────────────
  static const Color divider = Color(0xFFEEE7F1);
  static const Color dividerLight = Color(0xFFEEE7F1);
  static const Color dividerDark = Color(0xFF2E2538);
  static const Color border = Color(0xFFE9DFF0);
  static const Color borderLight = Color(0xFFE9DFF0);
  static const Color borderDark = Color(0xFF3A2F45);

  // ─── Shimmer Colors ──────────────────────────────────────────────
  static const Color shimmerBaseLight = Color(0xFFF1E9F4);
  static const Color shimmerHighlightLight = Color(0xFFFBF7FD);
  static const Color shimmerBaseDark = Color(0xFF2A2133);
  static const Color shimmerHighlightDark = Color(0xFF362B41);

  // ─── Overlay & Scrim ─────────────────────────────────────────────
  static const Color scrim = Color(0x80000000);
  static const Color overlay = Color(0x1A21152B);
  static const Color overlayDark = Color(0x33FFFFFF);

  /// Deep plum wash used over photography (matches reel, hero cards) so
  /// overlaid text stays legible without turning the image grey.
  static const Color photoScrimSoft = Color(0x4D2A0B3F);
  static const Color photoScrimVeil = Color(0x992A0B3F);
  static const Color photoScrimMedium = Color(0xCC2A0B3F);
  static const Color photoScrimStrong = Color(0xF22A0B3F);

  // ─── Dark-Theme Brand Tones ──────────────────────────────────────
  /// Lightened brand hues so plum/magenta keep AA contrast on dark surfaces.
  static const Color primaryOnDark = Color(0xFFCBA6F7);
  static const Color primaryContainerDark = Color(0xFF3B1173);
  static const Color secondaryOnDark = Color(0xFFF472B6);
  static const Color secondaryContainerDark = Color(0xFF57123A);
  static const Color accentOnDark = Color(0xFFF58CB4);
  static const Color errorOnDark = Color(0xFFFF8A9B);

  // ─── Material 3 Color Scheme — Light ─────────────────────────────
  static ColorScheme get lightColorScheme => const ColorScheme.light(
    primary: primary,
    onPrimary: textOnPrimary,
    primaryContainer: primarySurface,
    onPrimaryContainer: primaryDark,
    secondary: secondary,
    onSecondary: textOnSecondary,
    secondaryContainer: secondarySurface,
    onSecondaryContainer: secondaryDark,
    tertiary: accent,
    onTertiary: Colors.white,
    tertiaryContainer: accentSoft,
    onTertiaryContainer: accentDark,
    surface: surfaceLight,
    onSurface: textPrimaryLight,
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFFF9FC),
    surfaceContainer: Color(0xFFFBF4FD),
    surfaceContainerHigh: Color(0xFFF7F1FA),
    surfaceContainerHighest: surfaceVariantLight,
    onSurfaceVariant: textSecondaryLight,
    error: error,
    onError: Colors.white,
    errorContainer: errorLight,
    onErrorContainer: Color(0xFF8C1420),
    outline: borderLight,
    outlineVariant: dividerLight,
    shadow: Color(0x1A21152B),
    scrim: scrim,
  );

  // ─── Material 3 Color Scheme — Dark ──────────────────────────────
  static ColorScheme get darkColorScheme => const ColorScheme.dark(
    primary: primaryOnDark,
    onPrimary: Color(0xFF2B0B50),
    primaryContainer: primaryContainerDark,
    onPrimaryContainer: Color(0xFFEEDCFB),
    secondary: secondaryOnDark,
    onSecondary: Color(0xFF4A0A2B),
    secondaryContainer: secondaryContainerDark,
    onSecondaryContainer: Color(0xFFFFD9E8),
    tertiary: accentOnDark,
    onTertiary: Color(0xFF4E0F2C),
    tertiaryContainer: Color(0xFF6B1D40),
    onTertiaryContainer: Color(0xFFFFD9E8),
    surface: surfaceDark,
    onSurface: textPrimaryDark,
    surfaceContainerLowest: Color(0xFF100C15),
    surfaceContainerLow: Color(0xFF1A1421),
    surfaceContainer: Color(0xFF221A2B),
    surfaceContainerHigh: Color(0xFF2A2133),
    surfaceContainerHighest: surfaceVariantDark,
    onSurfaceVariant: textSecondaryDark,
    error: errorOnDark,
    onError: Color(0xFF4A0410),
    errorContainer: Color(0xFF6E1220),
    onErrorContainer: Color(0xFFFFDADD),
    outline: borderDark,
    outlineVariant: dividerDark,
    shadow: Color(0x66000000),
    scrim: scrim,
  );
}
