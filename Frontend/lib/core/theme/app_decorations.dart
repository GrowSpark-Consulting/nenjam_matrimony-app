import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_gradients.dart';
import 'app_shadows.dart';

/// Nenjam Matrimony — Reusable Box Decorations
///
/// Cards are white on a warm-white background, so they need a hairline
/// lavender border to separate from the page — the very soft shadow alone
/// is not enough contrast, and a heavier shadow would break the "clean and
/// premium" direction.
abstract final class AppDecorations {
  // ─── Card Decorations ────────────────────────────────────────────
  static BoxDecoration card({bool isDark = false}) => BoxDecoration(
    color: isDark ? AppColors.cardDark : AppColors.cardLight,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      color: isDark ? AppColors.borderDark : AppColors.borderLight,
      width: 1,
    ),
    boxShadow: isDark ? AppShadows.cardDark : AppShadows.cardLight,
  );

  static BoxDecoration cardElevated({bool isDark = false}) => BoxDecoration(
    color: isDark ? AppColors.cardElevatedDark : AppColors.cardElevatedLight,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(
      color: isDark ? AppColors.borderDark : AppColors.borderLight,
      width: 1,
    ),
    boxShadow: isDark ? AppShadows.elevatedDark : AppShadows.elevated,
  );

  static BoxDecoration cardSubtle({bool isDark = false}) => BoxDecoration(
    color: isDark ? AppColors.cardDark : AppColors.cardLight,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
      width: 1,
    ),
    boxShadow: AppShadows.subtle,
  );

  /// Soft lavender fill with no shadow — selected rows, info panels, and
  /// unread notification highlights.
  static BoxDecoration cardSoft({double radius = 16}) => BoxDecoration(
    color: AppColors.softLavender,
    borderRadius: BorderRadius.circular(radius),
  );

  /// Selected-state card: soft lavender fill + plum border.
  static BoxDecoration cardSelected({double radius = 16}) => BoxDecoration(
    color: AppColors.softLavender,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: AppColors.primary, width: 1.5),
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
    borderRadius: BorderRadius.circular(24),
    boxShadow: AppShadows.elevated,
  );

  static BoxDecoration get accentCard => BoxDecoration(
    gradient: AppGradients.accent,
    borderRadius: BorderRadius.circular(20),
    boxShadow: AppShadows.accentGlow,
  );

  static BoxDecoration get accentBorder => BoxDecoration(
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: AppColors.secondary, width: 1.5),
  );

  // ─── Input Decorations ───────────────────────────────────────────
  static BoxDecoration inputField({bool isDark = false}) => BoxDecoration(
    color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceLight,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(
      color: isDark ? AppColors.borderDark : AppColors.borderLight,
      width: 1,
    ),
  );

  static BoxDecoration inputFieldFocused({bool isDark = false}) =>
      BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.primaryOnDark : AppColors.primary,
          width: 1.5,
        ),
        boxShadow: isDark ? AppShadows.none : AppShadows.focusRing,
      );

  // ─── Container Decorations ───────────────────────────────────────
  static BoxDecoration roundedContainer({
    required Color color,
    double radius = 20,
  }) =>
      BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius));

  // ─── Bottom Sheet Decoration ─────────────────────────────────────
  static BoxDecoration bottomSheet({bool isDark = false}) => BoxDecoration(
    color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
    boxShadow: AppShadows.elevated,
  );

  // ─── Image Overlay ───────────────────────────────────────────────
  static BoxDecoration get imageOverlay =>
      const BoxDecoration(gradient: AppGradients.imageOverlay);

  static BoxDecoration imageOverlayRounded({double radius = 20}) =>
      BoxDecoration(
        gradient: AppGradients.imageOverlay,
        borderRadius: BorderRadius.circular(radius),
      );
}
