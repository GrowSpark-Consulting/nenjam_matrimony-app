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
  //
  // THE single source of truth for the backend origin. Every Dio client,
  // socket connection and health probe reads it from here — nothing else in
  // the app may hardcode a host. The backend has NO global `/v1` prefix, so
  // this URL is an origin only: paths like `/discover` or `/profiles/me` are
  // appended verbatim.
  //
  // Overridable at build time without touching source, e.g.
  //   flutter build apk --release --dart-define=API_BASE_URL=https://staging.example.com
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api-production-83c6.up.railway.app',
  );
  static const Duration apiConnectTimeout = Duration(seconds: 20);
  static const Duration apiReceiveTimeout = Duration(seconds: 20);
  static const Duration apiSendTimeout = Duration(seconds: 20);

  /// Startup `/health` probe budget — deliberately shorter than the regular
  /// request timeouts so a dead backend surfaces a graceful error state
  /// quickly instead of holding the splash for the full 20s.
  static const Duration healthCheckTimeout = Duration(seconds: 8);

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
  static const String keyLanguage = 'selected_language';
  static const String keyOnboardingDone = 'onboarding_done';
  static const String keyNotificationsEnabled = 'notifications_enabled';

  /// Whether the Nenjam notification-permission explanation dialog has
  /// already been shown once. Gates [NotificationPermissionGate] so the
  /// user is never re-prompted every app launch after choosing "Not now".
  static const String keyNotificationPermissionPrompted =
      'notification_permission_prompted';

  /// Phone number captured during signup, held locally only until the number
  /// is verified and linked to the Firebase account. Not a profile store.
  static const String keyPendingPhone = 'pending_signup_phone';

  /// Local-only search history — capped at [maxRecentSearches] entries.
  static const String keySearchHistory = 'search_history';
  static const int maxRecentSearches = 10;

  // ─── Navigation / App State Restoration ───────────────────────────
  //
  // Snapshotted on AppLifecycleState.paused, consumed once by
  // SplashController.resolveInitialRoute() after a cold start (e.g. the OS
  // killed the process while the user was mid-registration in another app).
  static const String keyLastRoute = 'nav_last_route';
  static const String keyRegistrationStep = 'nav_registration_step';
  static const String keyProfileFlowMode = 'nav_profile_flow_mode';
  static const String keyProfileDraftJson = 'nav_profile_draft_json';

  // ─── Localization ────────────────────────────────────────────────
  /// Default language used until the user makes an explicit selection.
  static const String defaultLanguage = 'en';

  /// Languages the app currently ships translations for.
  static const List<String> activeLanguages = ['en', 'ta'];

  /// Supported Languages roadmap (translations rolled out incrementally).
  static const List<String> supportedLanguages = [
    'en',
    'ta',
    'hi',
    'gu',
    'te',
    'kn',
    'ml',
    'mr',
    'bn',
    'ar',
  ];
}
