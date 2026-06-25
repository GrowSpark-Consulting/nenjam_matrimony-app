/// Nenjam Matrimony — Application Constants
///
/// Centralized configuration values. No hardcoded strings/numbers
/// should exist outside this file and its siblings.
abstract final class AppConstants {
  // ─── App Info ────────────────────────────────────────────────────
  static const String appName = 'Nenjam Matrimony';
  static const String appTagline = 'Where Hearts Meet';
  static const String appVersion = '1.0.0';
  static const String appBuildNumber = '1';

  // ─── API Configuration ───────────────────────────────────────────
  static const String apiBaseUrl = 'https://api.nenjammatrimony.com/v1';
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration apiConnectTimeout = Duration(seconds: 15);
  static const int apiMaxRetries = 3;

  // ─── Pagination ──────────────────────────────────────────────────
  static const int defaultPageSize = 20;
  static const int maxPageSize = 50;
  static const int infiniteScrollThreshold = 200;

  // ─── Cache Durations ─────────────────────────────────────────────
  static const Duration cacheShort = Duration(minutes: 5);
  static const Duration cacheMedium = Duration(minutes: 30);
  static const Duration cacheLong = Duration(hours: 24);

  // ─── Animation Durations ─────────────────────────────────────────
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 300);
  static const Duration animSlow = Duration(milliseconds: 500);
  static const Duration animPageTransition = Duration(milliseconds: 350);
  static const Duration splashDuration = Duration(seconds: 3);

  // ─── UI Constraints ──────────────────────────────────────────────
  static const double maxContentWidth = 600;
  static const double tabletBreakpoint = 600;
  static const double desktopBreakpoint = 1024;
  static const double minTouchTarget = 48;
  static const int maxProfilePhotos = 10;
  static const int maxBioLength = 500;
  static const int otpLength = 6;

  // ─── Storage Keys ────────────────────────────────────────────────
  static const String keyAccessToken = 'access_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUserId = 'user_id';
  static const String keyThemeMode = 'theme_mode';
  static const String keyLanguage = 'language';
  static const String keyOnboardingDone = 'onboarding_done';
  static const String keyNotificationsEnabled = 'notifications_enabled';

  // ─── Supported Languages ─────────────────────────────────────────
  static const List<String> supportedLanguages = [
    'en', 'ta', 'hi', 'gu', 'te', 'kn', 'ml', 'mr', 'bn', 'ar',
  ];
}
