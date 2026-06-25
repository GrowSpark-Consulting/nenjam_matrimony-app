import 'package:flutter/material.dart';

/// Nenjam Matrimony — Complete Color System
///
/// Designed for a premium, luxury matrimonial experience.
/// Supports both light and dark themes with Material 3.
abstract final class AppColors {
  // ─── Primary Palette ───────────────────────────────────────────────
  static const Color primary = Color(0xFF1B2B4B);
  static const Color primaryLight = Color(0xFF2D4A7A);
  static const Color primaryDark = Color(0xFF0F1A2E);
  static const Color primarySurface = Color(0xFFE8EDF5);

  // ─── Accent Gold ──────────────────────────────────────────────────
  static const Color accentGold = Color(0xFFC9A84C);
  static const Color accentGoldLight = Color(0xFFE2CC7E);
  static const Color accentGoldDark = Color(0xFFA8882E);
  static const Color accentGoldSurface = Color(0xFFFAF5E4);

  // ─── Background & Surface ────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFFBF9F4);
  static const Color backgroundDark = Color(0xFF0F1117);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1A1D27);
  static const Color surfaceVariantLight = Color(0xFFF5F3EE);
  static const Color surfaceVariantDark = Color(0xFF242836);

  // ─── Card Colors ─────────────────────────────────────────────────
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF1E2230);
  static const Color cardElevatedLight = Color(0xFFFFFDF8);
  static const Color cardElevatedDark = Color(0xFF252A3A);

  // ─── Text Colors ─────────────────────────────────────────────────
  static const Color textPrimaryLight = Color(0xFF1A1C20);
  static const Color textPrimaryDark = Color(0xFFF0F0F5);
  static const Color textSecondaryLight = Color(0xFF5A5E6B);
  static const Color textSecondaryDark = Color(0xFFA0A4B2);
  static const Color textTertiaryLight = Color(0xFF8E919D);
  static const Color textTertiaryDark = Color(0xFF6B6F7E);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnGold = Color(0xFF1A1C20);

  // ─── Status Colors ───────────────────────────────────────────────
  static const Color success = Color(0xFF2E7D32);
  static const Color successLight = Color(0xFFE8F8F0);
  static const Color warning = Color(0xFFE6A700);
  static const Color warningLight = Color(0xFFFEF5E7);
  static const Color error = Color(0xFFD32F2F);
  static const Color errorLight = Color(0xFFFDECEA);
  static const Color info = Color(0xFF3498DB);
  static const Color infoLight = Color(0xFFEBF5FB);

  // ─── Semantic Colors ─────────────────────────────────────────────
  static const Color verified = Color(0xFF1565C0);
  static const Color verifiedBlue = Color(0xFF1565C0);
  static const Color premium = Color(0xFFC9A84C);
  static const Color premiumGold = Color(0xFFFFD54F);
  static const Color faceVerificationGreen = Color(0xFF43A047);
  static const Color online = Color(0xFF4CAF50);
  static const Color offline = Color(0xFF9E9E9E);
  static const Color liked = Color(0xFFE91E63);
  static const Color shortlisted = Color(0xFFFF9800);
  static const Color disabled = Color(0xFFBDBDBD);

  // ─── Divider & Border ────────────────────────────────────────────
  static const Color divider = Color(0xFFE0E0E0);
  static const Color dividerLight = Color(0xFFE0E0E0);
  static const Color dividerDark = Color(0xFF2A2E3D);
  static const Color borderLight = Color(0xFFE0DDD7);
  static const Color borderDark = Color(0xFF343849);

  // ─── Shimmer Colors ──────────────────────────────────────────────
  static const Color shimmerBaseLight = Color(0xFFEEECE7);
  static const Color shimmerHighlightLight = Color(0xFFF9F7F2);
  static const Color shimmerBaseDark = Color(0xFF2A2E3D);
  static const Color shimmerHighlightDark = Color(0xFF343849);

  // ─── Overlay & Scrim ─────────────────────────────────────────────
  static const Color scrim = Color(0x80000000);
  static const Color overlay = Color(0x1A000000);
  static const Color overlayDark = Color(0x33FFFFFF);

  // ─── Material 3 Color Scheme — Light ─────────────────────────────
  static ColorScheme get lightColorScheme => const ColorScheme.light(
        primary: primary,
        onPrimary: textOnPrimary,
        primaryContainer: primarySurface,
        onPrimaryContainer: primary,
        secondary: accentGold,
        onSecondary: textOnGold,
        secondaryContainer: accentGoldSurface,
        onSecondaryContainer: accentGoldDark,
        tertiary: Color(0xFF6C5B7B),
        onTertiary: Colors.white,
        surface: surfaceLight,
        onSurface: textPrimaryLight,
        surfaceContainerHighest: surfaceVariantLight,
        onSurfaceVariant: textSecondaryLight,
        error: error,
        onError: Colors.white,
        outline: borderLight,
        outlineVariant: dividerLight,
        shadow: Color(0x1A1B2B4B),
        scrim: scrim,
      );

  // ─── Material 3 Color Scheme — Dark ──────────────────────────────
  static ColorScheme get darkColorScheme => const ColorScheme.dark(
        primary: Color(0xFF7B9AD6),
        onPrimary: primaryDark,
        primaryContainer: primary,
        onPrimaryContainer: Color(0xFFD6E3FF),
        secondary: accentGold,
        onSecondary: textOnGold,
        secondaryContainer: Color(0xFF3D3520),
        onSecondaryContainer: accentGoldLight,
        tertiary: Color(0xFFB39DDB),
        onTertiary: Color(0xFF332D41),
        surface: surfaceDark,
        onSurface: textPrimaryDark,
        surfaceContainerHighest: surfaceVariantDark,
        onSurfaceVariant: textSecondaryDark,
        error: Color(0xFFFF6B6B),
        onError: Color(0xFF3D0000),
        outline: borderDark,
        outlineVariant: dividerDark,
        shadow: Color(0x40000000),
        scrim: scrim,
      );
}
