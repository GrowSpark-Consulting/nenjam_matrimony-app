// CupertinoPageTransitionsBuilder is re-exported by material.dart on some
// Flutter versions but not others (it resolves via material on 3.35.x, and
// only via cupertino on the 3.44.x CI toolchain). Import cupertino directly
// so the theme compiles on both; the ignore silences the resulting
// `unnecessary_import` info on the SDKs where material does re-export it.
// ignore: unnecessary_import
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Nenjam Matrimony — Complete Material 3 Theme
///
/// Light and dark [ThemeData] for the Plum + Magenta + Rose identity.
/// Component themes carry the whole neutral-first balance: surfaces are white
/// or warm white, plum drives primary actions and selected states, magenta
/// handles highlights, and rose stays reserved for emotional accents (which
/// individual widgets opt into — it is deliberately not wired into any
/// default component colour here).
abstract final class AppTheme {
  /// Filled controls sit at 56px so they clear the 48dp minimum touch target
  /// comfortably even with text scaling.
  static const Size _fullWidthButton = Size(double.infinity, 56);
  static const EdgeInsets _buttonPadding = EdgeInsets.symmetric(
    horizontal: 24,
    vertical: 16,
  );

  // ─── Light Theme ─────────────────────────────────────────────────
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: AppColors.lightColorScheme,
    scaffoldBackgroundColor: AppColors.backgroundLight,
    textTheme: AppTypography.textTheme,
    splashColor: AppColors.primary.withValues(alpha: 0.08),
    highlightColor: AppColors.primary.withValues(alpha: 0.04),

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.backgroundLight,
      foregroundColor: AppColors.textPrimaryLight,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: AppTypography.titleLarge.copyWith(
        color: AppColors.textPrimaryLight,
      ),
      iconTheme: const IconThemeData(
        color: AppColors.textPrimaryLight,
        size: 24,
      ),
    ),

    // Cards
    cardTheme: CardThemeData(
      color: AppColors.cardLight,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      margin: EdgeInsets.zero,
    ),

    // Elevated Button — the flat plum fill. The gradient variant lives in
    // GradientButton; this is its non-gradient equivalent.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        disabledBackgroundColor: AppColors.primarySurfaceStrong,
        disabledForegroundColor: AppColors.textTertiaryLight,
        elevation: 0,
        padding: _buttonPadding,
        minimumSize: _fullWidthButton,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: AppTypography.button,
      ),
    ),

    // Filled Button
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        disabledBackgroundColor: AppColors.primarySurfaceStrong,
        disabledForegroundColor: AppColors.textTertiaryLight,
        padding: _buttonPadding,
        minimumSize: _fullWidthButton,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: AppTypography.button,
      ),
    ),

    // Outlined Button — deliberately no `backgroundColor`. An opaque white
    // fill turns every outlined button into a solid block on the brand
    // gradients (splash Retry, crop screen), where the label is white and
    // vanishes. Transparent inherits whatever surface it sits on.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        elevation: 0,
        padding: _buttonPadding,
        minimumSize: _fullWidthButton,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        textStyle: AppTypography.button,
      ),
    ),

    // Text Button
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        minimumSize: const Size(48, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: AppTypography.button,
      ),
    ),

    // Floating Action Button — magenta, so it reads as a highlight against
    // the plum navigation rather than blending into it.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.secondary,
      foregroundColor: AppColors.textOnSecondary,
      elevation: 3,
      focusElevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),

    // Input Decoration
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceLight,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.borderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.borderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.dividerLight),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      hintStyle: AppTypography.bodyMedium.copyWith(
        color: AppColors.textTertiaryLight,
      ),
      labelStyle: AppTypography.bodyMedium.copyWith(
        color: AppColors.textSecondaryLight,
      ),
      floatingLabelStyle: AppTypography.bodyMedium.copyWith(
        color: AppColors.primary,
      ),
      errorStyle: AppTypography.bodySmall.copyWith(color: AppColors.error),
      prefixIconColor: AppColors.textSecondaryLight,
      suffixIconColor: AppColors.textSecondaryLight,
    ),

    // Bottom Navigation Bar
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.surfaceLight,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textTertiaryLight,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: AppTypography.labelSmall.copyWith(
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: AppTypography.labelSmall,
    ),

    // Navigation Bar (Material 3)
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surfaceLight,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.primarySurface,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 0,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppTypography.labelSmall.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          );
        }
        return AppTypography.labelSmall.copyWith(
          color: AppColors.textTertiaryLight,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.primary, size: 24);
        }
        return const IconThemeData(
          color: AppColors.textTertiaryLight,
          size: 24,
        );
      }),
    ),

    // Bottom Sheet
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surfaceLight,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      showDragHandle: true,
      dragHandleColor: AppColors.primarySurfaceStrong,
    ),

    // Dialog
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceLight,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: AppTypography.titleLarge.copyWith(
        color: AppColors.textPrimaryLight,
      ),
      contentTextStyle: AppTypography.bodyMedium.copyWith(
        color: AppColors.textSecondaryLight,
      ),
    ),

    // Chip — unselected reads as soft lavender, selected as plum.
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.softLavender,
      selectedColor: AppColors.primary,
      secondarySelectedColor: AppColors.primary,
      disabledColor: AppColors.surfaceVariantLight,
      checkmarkColor: AppColors.textOnPrimary,
      labelStyle: AppTypography.labelMedium.copyWith(
        color: AppColors.primaryDark,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: AppTypography.labelMedium.copyWith(
        color: AppColors.textOnPrimary,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      side: const BorderSide(color: AppColors.borderLight),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    // Divider
    dividerTheme: const DividerThemeData(
      color: AppColors.dividerLight,
      thickness: 1,
      space: 1,
    ),

    // Tab Bar
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.textTertiaryLight,
      labelStyle: AppTypography.labelLarge.copyWith(
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: AppTypography.labelLarge,
      indicatorColor: AppColors.secondary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.dividerLight,
    ),

    // Snackbar
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.primaryDeep,
      contentTextStyle: AppTypography.bodyMedium.copyWith(
        color: AppColors.textOnPrimary,
      ),
      actionTextColor: AppColors.accentLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
      elevation: 4,
    ),

    // Switch
    switchTheme: SwitchThemeData(
      // White thumb in both states — the track carries the on/off signal.
      thumbColor: const WidgetStatePropertyAll(AppColors.surfaceLight),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.primary;
        return AppColors.primarySurfaceStrong;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.primary;
        return AppColors.borderLight;
      }),
    ),

    // Checkbox
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.primary;
        return Colors.transparent;
      }),
      checkColor: const WidgetStatePropertyAll(AppColors.textOnPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: const BorderSide(color: AppColors.borderLight, width: 1.5),
    ),

    // Radio
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.primary;
        return AppColors.textTertiaryLight;
      }),
    ),

    // Slider — plum active track, soft lavender inactive.
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.primary,
      inactiveTrackColor: AppColors.primarySurfaceStrong,
      thumbColor: AppColors.primary,
      overlayColor: AppColors.primary.withValues(alpha: 0.12),
      valueIndicatorColor: AppColors.primary,
      activeTickMarkColor: AppColors.textOnPrimary,
      inactiveTickMarkColor: AppColors.borderLight,
      trackHeight: 4,
      valueIndicatorTextStyle: AppTypography.labelSmall.copyWith(
        color: AppColors.textOnPrimary,
      ),
    ),

    // Progress Indicator
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.primarySurface,
      circularTrackColor: AppColors.primarySurface,
      linearMinHeight: 6,
    ),

    // Tooltip
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.primaryDeep,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: AppTypography.labelSmall.copyWith(
        color: AppColors.textOnPrimary,
      ),
    ),

    // List Tile
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.textSecondaryLight,
      textColor: AppColors.textPrimaryLight,
      selectedColor: AppColors.primary,
      selectedTileColor: AppColors.softLavender,
    ),

    // Icons
    iconTheme: const IconThemeData(color: AppColors.textSecondaryLight),

    // Page Transitions
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );

  // ─── Dark Theme ──────────────────────────────────────────────────
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: AppColors.darkColorScheme,
    scaffoldBackgroundColor: AppColors.backgroundDark,
    textTheme: AppTypography.textTheme,
    splashColor: AppColors.primaryOnDark.withValues(alpha: 0.10),
    highlightColor: AppColors.primaryOnDark.withValues(alpha: 0.05),

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.backgroundDark,
      foregroundColor: AppColors.textPrimaryDark,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: AppTypography.titleLarge.copyWith(
        color: AppColors.textPrimaryDark,
      ),
      iconTheme: const IconThemeData(
        color: AppColors.textPrimaryDark,
        size: 24,
      ),
    ),

    // Cards
    cardTheme: CardThemeData(
      color: AppColors.cardDark,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.borderDark),
      ),
      margin: EdgeInsets.zero,
    ),

    // Elevated Button
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryOnDark,
        foregroundColor: const Color(0xFF2B0B50),
        disabledBackgroundColor: AppColors.surfaceVariantDark,
        disabledForegroundColor: AppColors.textTertiaryDark,
        elevation: 0,
        padding: _buttonPadding,
        minimumSize: _fullWidthButton,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: AppTypography.button,
      ),
    ),

    // Filled Button
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryOnDark,
        foregroundColor: const Color(0xFF2B0B50),
        disabledBackgroundColor: AppColors.surfaceVariantDark,
        disabledForegroundColor: AppColors.textTertiaryDark,
        padding: _buttonPadding,
        minimumSize: _fullWidthButton,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: AppTypography.button,
      ),
    ),

    // Outlined Button
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryOnDark,
        elevation: 0,
        padding: _buttonPadding,
        minimumSize: _fullWidthButton,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: AppColors.primaryOnDark, width: 1.5),
        textStyle: AppTypography.button,
      ),
    ),

    // Text Button
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryOnDark,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        minimumSize: const Size(48, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: AppTypography.button,
      ),
    ),

    // Floating Action Button
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.secondaryOnDark,
      foregroundColor: const Color(0xFF4A0A2B),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),

    // Input Decoration
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceVariantDark,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.borderDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.borderDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: AppColors.primaryOnDark,
          width: 1.5,
        ),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.dividerDark),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.errorOnDark),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.errorOnDark, width: 1.5),
      ),
      hintStyle: AppTypography.bodyMedium.copyWith(
        color: AppColors.textTertiaryDark,
      ),
      labelStyle: AppTypography.bodyMedium.copyWith(
        color: AppColors.textSecondaryDark,
      ),
      floatingLabelStyle: AppTypography.bodyMedium.copyWith(
        color: AppColors.primaryOnDark,
      ),
      errorStyle: AppTypography.bodySmall.copyWith(
        color: AppColors.errorOnDark,
      ),
      prefixIconColor: AppColors.textSecondaryDark,
      suffixIconColor: AppColors.textSecondaryDark,
    ),

    // Bottom Navigation Bar
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.surfaceDark,
      selectedItemColor: AppColors.primaryOnDark,
      unselectedItemColor: AppColors.textTertiaryDark,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: AppTypography.labelSmall.copyWith(
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: AppTypography.labelSmall,
    ),

    // Navigation Bar (Material 3)
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surfaceDark,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.primaryContainerDark,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 0,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppTypography.labelSmall.copyWith(
            color: AppColors.primaryOnDark,
            fontWeight: FontWeight.w600,
          );
        }
        return AppTypography.labelSmall.copyWith(
          color: AppColors.textTertiaryDark,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.primaryOnDark, size: 24);
        }
        return const IconThemeData(color: AppColors.textTertiaryDark, size: 24);
      }),
    ),

    // Bottom Sheet
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surfaceDark,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      showDragHandle: true,
      dragHandleColor: AppColors.borderDark,
    ),

    // Dialog
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceDark,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: AppTypography.titleLarge.copyWith(
        color: AppColors.textPrimaryDark,
      ),
      contentTextStyle: AppTypography.bodyMedium.copyWith(
        color: AppColors.textSecondaryDark,
      ),
    ),

    // Chip
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceVariantDark,
      selectedColor: AppColors.primaryContainerDark,
      secondarySelectedColor: AppColors.primaryContainerDark,
      disabledColor: AppColors.surfaceVariantDark,
      checkmarkColor: AppColors.primaryOnDark,
      labelStyle: AppTypography.labelMedium.copyWith(
        color: AppColors.textSecondaryDark,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: AppTypography.labelMedium.copyWith(
        color: const Color(0xFFEEDCFB),
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      side: const BorderSide(color: AppColors.borderDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    // Divider
    dividerTheme: const DividerThemeData(
      color: AppColors.dividerDark,
      thickness: 1,
      space: 1,
    ),

    // Tab Bar
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.primaryOnDark,
      unselectedLabelColor: AppColors.textTertiaryDark,
      labelStyle: AppTypography.labelLarge.copyWith(
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: AppTypography.labelLarge,
      indicatorColor: AppColors.secondaryOnDark,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.dividerDark,
    ),

    // Snackbar
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceVariantDark,
      contentTextStyle: AppTypography.bodyMedium.copyWith(
        color: AppColors.textPrimaryDark,
      ),
      actionTextColor: AppColors.accentOnDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
      elevation: 4,
    ),

    // Switch
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Color(0xFF2B0B50);
        }
        return AppColors.textTertiaryDark;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primaryOnDark;
        }
        return AppColors.surfaceVariantDark;
      }),
      trackOutlineColor: const WidgetStatePropertyAll(AppColors.borderDark),
    ),

    // Checkbox
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primaryOnDark;
        }
        return Colors.transparent;
      }),
      checkColor: const WidgetStatePropertyAll(Color(0xFF2B0B50)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: const BorderSide(color: AppColors.borderDark, width: 1.5),
    ),

    // Radio
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primaryOnDark;
        }
        return AppColors.textTertiaryDark;
      }),
    ),

    // Slider
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.primaryOnDark,
      inactiveTrackColor: AppColors.surfaceVariantDark,
      thumbColor: AppColors.primaryOnDark,
      overlayColor: AppColors.primaryOnDark.withValues(alpha: 0.14),
      valueIndicatorColor: AppColors.primaryContainerDark,
      trackHeight: 4,
      valueIndicatorTextStyle: AppTypography.labelSmall.copyWith(
        color: AppColors.textPrimaryDark,
      ),
    ),

    // Progress Indicator
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primaryOnDark,
      linearTrackColor: AppColors.primaryContainerDark,
      circularTrackColor: AppColors.primaryContainerDark,
      linearMinHeight: 6,
    ),

    // Tooltip
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariantDark,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: AppTypography.labelSmall.copyWith(
        color: AppColors.textPrimaryDark,
      ),
    ),

    // List Tile
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.textSecondaryDark,
      textColor: AppColors.textPrimaryDark,
      selectedColor: AppColors.primaryOnDark,
      selectedTileColor: AppColors.primaryContainerDark,
    ),

    // Icons
    iconTheme: const IconThemeData(color: AppColors.textSecondaryDark),

    // Page Transitions
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
