import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_gradients.dart';
import 'app_shadows.dart';

/// Nenjam Matrimony — Reusable Box Decorations
///
/// Pre-built decorations for cards, glass effects, premium surfaces,
/// and overlay containers used throughout the app.
abstract final class AppDecorations {
  // ─── Card Decorations ────────────────────────────────────────────
  static BoxDecoration card({bool isDark = false}) => BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark ? AppShadows.cardDark : AppShadows.cardLight,
      );

  static BoxDecoration cardElevated({bool isDark = false}) => BoxDecoration(
        color:
            isDark ? AppColors.cardElevatedDark : AppColors.cardElevatedLight,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark ? AppShadows.elevatedDark : AppShadows.elevated,
      );

  static BoxDecoration cardSubtle({bool isDark = false}) => BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.subtle,
      );

  // ─── Glass Decorations ───────────────────────────────────────────
  static BoxDecoration glass({bool isDark = false}) => BoxDecoration(
        gradient: isDark ? AppGradients.cardGlassDark : AppGradients.cardGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.6),
          width: 1,
        ),
      );

  static BoxDecoration glassElevated({bool isDark = false}) => BoxDecoration(
        gradient: isDark ? AppGradients.cardGlassDark : AppGradients.cardGlass,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.7),
          width: 1.5,
        ),
        boxShadow: isDark ? AppShadows.elevatedDark : AppShadows.elevated,
      );

  // ─── Premium Decorations ─────────────────────────────────────────
  static BoxDecoration get premiumCard => BoxDecoration(
        gradient: AppGradients.premiumCard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.elevated,
      );

  static BoxDecoration get goldCard => BoxDecoration(
        gradient: AppGradients.gold,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.goldGlow,
      );

  static BoxDecoration get goldBorder => BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.accentGold,
          width: 1.5,
        ),
      );

  // ─── Input Decorations ───────────────────────────────────────────
  static BoxDecoration inputField({bool isDark = false}) => BoxDecoration(
        color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
          width: 1,
        ),
      );

  static BoxDecoration inputFieldFocused({bool isDark = false}) => BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      );

  // ─── Container Decorations ───────────────────────────────────────
  static BoxDecoration roundedContainer({
    required Color color,
    double radius = 20,
  }) =>
      BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      );

  // ─── Bottom Sheet Decoration ─────────────────────────────────────
  static BoxDecoration bottomSheet({bool isDark = false}) => BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(28),
        ),
        boxShadow: AppShadows.elevated,
      );

  // ─── Image Overlay ───────────────────────────────────────────────
  static BoxDecoration get imageOverlay => const BoxDecoration(
        gradient: AppGradients.imageOverlay,
      );

  static BoxDecoration imageOverlayRounded({double radius = 20}) =>
      BoxDecoration(
        gradient: AppGradients.imageOverlay,
        borderRadius: BorderRadius.circular(radius),
      );
}
