import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// BuildContext extensions for quick access to theme,
/// colors, typography, and screen dimensions.
extension ContextExtensions on BuildContext {
  // ─── Theme ───────────────────────────────────────────────────────
  ThemeData get theme => Theme.of(this);
  ColorScheme get colorScheme => theme.colorScheme;
  TextTheme get textTheme => theme.textTheme;
  bool get isDark => theme.brightness == Brightness.dark;

  // ─── Media Query ─────────────────────────────────────────────────
  MediaQueryData get mediaQuery => MediaQuery.of(this);
  Size get screenSize => mediaQuery.size;
  double get screenWidth => screenSize.width;
  double get screenHeight => screenSize.height;
  double get statusBarHeight => mediaQuery.padding.top;
  double get bottomPadding => mediaQuery.padding.bottom;
  EdgeInsets get viewPadding => mediaQuery.viewPadding;
  EdgeInsets get viewInsets => mediaQuery.viewInsets;
  double get keyboardHeight => viewInsets.bottom;
  bool get isKeyboardVisible => keyboardHeight > 0;
  Orientation get orientation => mediaQuery.orientation;

  // ─── Device Type ─────────────────────────────────────────────────
  bool get isPhone => screenWidth < 600;
  bool get isTablet => screenWidth >= 600 && screenWidth < 1024;
  bool get isDesktop => screenWidth >= 1024;
  bool get isLandscape => orientation == Orientation.landscape;
  bool get isPortrait => orientation == Orientation.portrait;

  // ─── App Colors Quick Access ─────────────────────────────────────
  Color get primaryColor => colorScheme.primary;
  Color get backgroundColor => isDark
      ? AppColors.backgroundDark
      : AppColors.backgroundLight;
  Color get cardColor => isDark
      ? AppColors.cardDark
      : AppColors.cardLight;
  Color get textPrimary => isDark
      ? AppColors.textPrimaryDark
      : AppColors.textPrimaryLight;
  Color get textSecondary => isDark
      ? AppColors.textSecondaryDark
      : AppColors.textSecondaryLight;
  Color get dividerColor => isDark
      ? AppColors.dividerDark
      : AppColors.dividerLight;

  // ─── Navigation ──────────────────────────────────────────────────
  NavigatorState get navigator => Navigator.of(this);
  void pop<T>([T? result]) => navigator.pop(result);

  // ─── Snackbar ────────────────────────────────────────────────────
  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : null,
      ),
    );
  }

  // ─── Focus ───────────────────────────────────────────────────────
  void unfocus() => FocusScope.of(this).unfocus();
}
