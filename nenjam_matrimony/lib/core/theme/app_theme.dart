import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Nenjam Matrimony — Complete Material 3 Theme
///
/// Provides fully configured light and dark ThemeData with
/// custom component themes for a premium matrimonial experience.
abstract final class AppTheme {
  // ─── Light Theme ─────────────────────────────────────────────────
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: AppColors.lightColorScheme,
        scaffoldBackgroundColor: AppColors.backgroundLight,
        textTheme: AppTypography.textTheme,

        // AppBar
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.backgroundLight,
          foregroundColor: AppColors.textPrimaryLight,
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
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          margin: EdgeInsets.zero,
        ),

        // Elevated Button
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: AppTypography.button,
          ),
        ),

        // Outlined Button
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            textStyle: AppTypography.button,
          ),
        ),

        // Text Button
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: AppTypography.button,
          ),
        ),

        // Floating Action Button
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),

        // Input Decoration
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceVariantLight,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
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
          errorStyle: AppTypography.bodySmall.copyWith(
            color: AppColors.error,
          ),
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
          indicatorColor: AppColors.primarySurface,
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
              return const IconThemeData(
                color: AppColors.primary,
                size: 24,
              );
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          showDragHandle: true,
          dragHandleColor: AppColors.dividerLight,
        ),

        // Dialog
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surfaceLight,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          titleTextStyle: AppTypography.titleLarge.copyWith(
            color: AppColors.textPrimaryLight,
          ),
          contentTextStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondaryLight,
          ),
        ),

        // Chip
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFE2E8F0),
          selectedColor: AppColors.primarySurface,
          disabledColor: const Color(0xFFE2E8F0),
          checkmarkColor: AppColors.primary,
          labelStyle: AppTypography.labelMedium.copyWith(
            color: AppColors.textPrimaryLight,
            fontWeight: FontWeight.w700,
          ),
          secondaryLabelStyle: AppTypography.labelMedium.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w800,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF94A3B8), width: 1.2),
          ),
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
          labelStyle: AppTypography.labelLarge,
          unselectedLabelStyle: AppTypography.labelLarge,
          indicatorColor: AppColors.primary,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: AppColors.dividerLight,
        ),

        // Snackbar
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.primary,
          contentTextStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.textOnPrimary,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          behavior: SnackBarBehavior.floating,
          elevation: 4,
        ),

        // Switch
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return AppColors.textTertiaryLight;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primarySurface;
            }
            return AppColors.surfaceVariantLight;
          }),
        ),

        // Checkbox
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return Colors.transparent;
          }),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          side: const BorderSide(color: AppColors.borderLight, width: 1.5),
        ),

        // Radio
        radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return AppColors.textTertiaryLight;
          }),
        ),

        // Progress Indicator
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.primary,
          linearTrackColor: AppColors.primarySurface,
          circularTrackColor: AppColors.primarySurface,
        ),

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

        // AppBar
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.backgroundDark,
          foregroundColor: AppColors.textPrimaryDark,
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
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          margin: EdgeInsets.zero,
        ),

        // Elevated Button
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7B9AD6),
            foregroundColor: AppColors.primaryDark,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: AppTypography.button,
          ),
        ),

        // Outlined Button
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF7B9AD6),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            side: const BorderSide(color: Color(0xFF7B9AD6), width: 1.5),
            textStyle: AppTypography.button,
          ),
        ),

        // Text Button
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF7B9AD6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: AppTypography.button,
          ),
        ),

        // Floating Action Button
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: const Color(0xFF7B9AD6),
          foregroundColor: AppColors.primaryDark,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),

        // Input Decoration
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceVariantDark,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
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
              color: Color(0xFF7B9AD6),
              width: 1.5,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFFF6B6B)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Color(0xFFFF6B6B),
              width: 1.5,
            ),
          ),
          hintStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.textTertiaryDark,
          ),
          labelStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondaryDark,
          ),
          errorStyle: AppTypography.bodySmall.copyWith(
            color: const Color(0xFFFF6B6B),
          ),
          prefixIconColor: AppColors.textSecondaryDark,
          suffixIconColor: AppColors.textSecondaryDark,
        ),

        // Bottom Navigation Bar
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: AppColors.surfaceDark,
          selectedItemColor: const Color(0xFF7B9AD6),
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
          indicatorColor: const Color(0xFF1B2B4B),
          elevation: 0,
          height: 72,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppTypography.labelSmall.copyWith(
                color: const Color(0xFF7B9AD6),
                fontWeight: FontWeight.w600,
              );
            }
            return AppTypography.labelSmall.copyWith(
              color: AppColors.textTertiaryDark,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(
                color: Color(0xFF7B9AD6),
                size: 24,
              );
            }
            return const IconThemeData(
              color: AppColors.textTertiaryDark,
              size: 24,
            );
          }),
        ),

        // Bottom Sheet
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          showDragHandle: true,
          dragHandleColor: AppColors.dividerDark,
        ),

        // Dialog
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surfaceDark,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          titleTextStyle: AppTypography.titleLarge.copyWith(
            color: AppColors.textPrimaryDark,
          ),
          contentTextStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondaryDark,
          ),
        ),

        // Chip
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF242836),
          selectedColor: const Color(0xFF1B2B4B),
          disabledColor: const Color(0xFF242836),
          checkmarkColor: const Color(0xFF7B9AD6),
          labelStyle: AppTypography.labelMedium.copyWith(
            color: AppColors.textPrimaryDark,
            fontWeight: FontWeight.w700,
          ),
          secondaryLabelStyle: AppTypography.labelMedium.copyWith(
            color: const Color(0xFFD6E3FF),
            fontWeight: FontWeight.w800,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF475569), width: 1.2),
          ),
        ),

        // Divider
        dividerTheme: const DividerThemeData(
          color: AppColors.dividerDark,
          thickness: 1,
          space: 1,
        ),

        // Tab Bar
        tabBarTheme: TabBarThemeData(
          labelColor: const Color(0xFF7B9AD6),
          unselectedLabelColor: AppColors.textTertiaryDark,
          labelStyle: AppTypography.labelLarge,
          unselectedLabelStyle: AppTypography.labelLarge,
          indicatorColor: const Color(0xFF7B9AD6),
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: AppColors.dividerDark,
        ),

        // Snackbar
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.surfaceVariantDark,
          contentTextStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimaryDark,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          behavior: SnackBarBehavior.floating,
          elevation: 4,
        ),

        // Switch
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF7B9AD6);
            }
            return AppColors.textTertiaryDark;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF1B2B4B);
            }
            return AppColors.surfaceVariantDark;
          }),
        ),

        // Checkbox
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF7B9AD6);
            }
            return Colors.transparent;
          }),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          side: const BorderSide(color: AppColors.borderDark, width: 1.5),
        ),

        // Radio
        radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF7B9AD6);
            }
            return AppColors.textTertiaryDark;
          }),
        ),

        // Progress Indicator
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFF7B9AD6),
          linearTrackColor: Color(0xFF1B2B4B),
          circularTrackColor: Color(0xFF1B2B4B),
        ),

        // Page Transitions
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      );
}
