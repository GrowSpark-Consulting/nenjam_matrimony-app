import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

/// Nenjam Matrimony — Local Storage Service
///
/// Wraps SharedPreferences for type-safe, centralized local storage.
/// Handles language, tokens, and user preferences.
class StorageService {
  late final SharedPreferences _prefs;

  /// Must be called before using the service.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ─── Language ────────────────────────────────────────────────────
  /// The user's explicitly selected language code, or `null` if the user
  /// has not chosen one yet. Backed by the `selected_language` key.
  String? get selectedLanguage {
    final value = _prefs.getString(AppConstants.keyLanguage);
    return (value != null && value.isNotEmpty) ? value : null;
  }

  /// Whether the user has completed the language-selection step.
  bool get hasSelectedLanguage => selectedLanguage != null;

  /// The active language code, falling back to the default when unset.
  /// Safe for locale resolution (never null).
  String get language => selectedLanguage ?? AppConstants.defaultLanguage;

  Future<void> setLanguage(String languageCode) async {
    await _prefs.setString(AppConstants.keyLanguage, languageCode);
  }

  // ─── Authentication Tokens ───────────────────────────────────────
  String? get accessToken => _prefs.getString(AppConstants.keyAccessToken);

  Future<void> setAccessToken(String token) async {
    await _prefs.setString(AppConstants.keyAccessToken, token);
  }

  String? get refreshToken => _prefs.getString(AppConstants.keyRefreshToken);

  Future<void> setRefreshToken(String token) async {
    await _prefs.setString(AppConstants.keyRefreshToken, token);
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      setAccessToken(accessToken),
      setRefreshToken(refreshToken),
    ]);
  }

  Future<void> clearTokens() async {
    await Future.wait([
      _prefs.remove(AppConstants.keyAccessToken),
      _prefs.remove(AppConstants.keyRefreshToken),
    ]);
  }

  bool get isLoggedIn => accessToken != null && accessToken!.isNotEmpty;

  // ─── User ID ─────────────────────────────────────────────────────
  String? get userId => _prefs.getString(AppConstants.keyUserId);

  Future<void> setUserId(String id) async {
    await _prefs.setString(AppConstants.keyUserId, id);
  }

  // ─── Pending signup phone (transient, local-only) ────────────────
  String? get pendingPhone {
    final value = _prefs.getString(AppConstants.keyPendingPhone);
    return (value != null && value.isNotEmpty) ? value : null;
  }

  Future<void> setPendingPhone(String e164Phone) async {
    await _prefs.setString(AppConstants.keyPendingPhone, e164Phone);
  }

  Future<void> clearPendingPhone() async {
    await _prefs.remove(AppConstants.keyPendingPhone);
  }

  // ─── Dev-auth phone (DEBUG ONLY, local-only) ─────────────────────
  //
  // The number the dummy OTP accepted, stood in for a Firebase session by
  // DevAuthSession. Only ever written by a debug build — see
  // dev_auth_session.dart — and cleared on sign-out with everything else.
  String? get devAuthPhone {
    final value = _prefs.getString(AppConstants.keyDevAuthPhone);
    return (value != null && value.isNotEmpty) ? value : null;
  }

  Future<void> setDevAuthPhone(String e164Phone) async {
    await _prefs.setString(AppConstants.keyDevAuthPhone, e164Phone);
  }

  Future<void> clearDevAuthPhone() async {
    await _prefs.remove(AppConstants.keyDevAuthPhone);
  }

  // ─── Pending onboarding email (transient, local-only) ────────────
  //
  // Set when the Email + Mobile step has asked Firebase to confirm an
  // address but the account does not carry it yet — Firebase only attaches
  // the address once the member opens the link, which can be minutes or a
  // device away. Without this marker the onboarding gate would keep sending
  // them back to a step they have already completed. Cleared once the
  // address actually lands on the account.
  String? get pendingEmail {
    final value = _prefs.getString(AppConstants.keyPendingEmail);
    return (value != null && value.isNotEmpty) ? value : null;
  }

  Future<void> setPendingEmail(String email) async {
    await _prefs.setString(AppConstants.keyPendingEmail, email);
  }

  Future<void> clearPendingEmail() async {
    await _prefs.remove(AppConstants.keyPendingEmail);
  }

  // ─── Onboarding completion (development bridge) ──────────────────
  //
  // Signup collects a whole profile before asking for any credential, so a
  // member reaches the end of onboarding with no Firebase session — and
  // every authenticated route correctly refuses one. While the OTP step is
  // the static development verifier (MockOtpVerifier), this flag is what
  // lets a finished member into the app.
  //
  // It is a development bridge, not an auth mechanism: it is local to the
  // device and proves nothing about identity. It exists exactly as long as
  // the mock verifier does — when real verification is restored, the OTP
  // step ends in a real session and both this flag and its branch in the
  // router guard should be deleted together.
  bool get onboardingCompleted =>
      _prefs.getBool(AppConstants.keyOnboardingCompleted) ?? false;

  Future<void> setOnboardingCompleted(bool value) async {
    await _prefs.setBool(AppConstants.keyOnboardingCompleted, value);
  }

  // ─── Search History ──────────────────────────────────────────────
  List<String> get recentSearches =>
      _prefs.getStringList(AppConstants.keySearchHistory) ?? const [];

  Future<void> setRecentSearches(List<String> searches) async {
    await _prefs.setStringList(AppConstants.keySearchHistory, searches);
  }

  // ─── Onboarding ──────────────────────────────────────────────────
  bool get isOnboardingDone =>
      _prefs.getBool(AppConstants.keyOnboardingDone) ?? false;

  Future<void> setOnboardingDone() async {
    await _prefs.setBool(AppConstants.keyOnboardingDone, true);
  }

  // ─── Notifications ──────────────────────────────────────────────
  bool get notificationsEnabled =>
      _prefs.getBool(AppConstants.keyNotificationsEnabled) ?? true;

  Future<void> setNotificationsEnabled(bool enabled) async {
    await _prefs.setBool(AppConstants.keyNotificationsEnabled, enabled);
  }

  /// Whether [NotificationPermissionGate] has already shown its one-time
  /// explanation dialog (regardless of the user's choice) — prevents
  /// repeatedly prompting on every app launch.
  bool get hasPromptedNotificationPermission =>
      _prefs.getBool(AppConstants.keyNotificationPermissionPrompted) ?? false;

  Future<void> setNotificationPermissionPrompted() async {
    await _prefs.setBool(AppConstants.keyNotificationPermissionPrompted, true);
  }

  // ─── Navigation / App State Restoration ───────────────────────────
  String? get lastRoute => _prefs.getString(AppConstants.keyLastRoute);

  int? get savedRegistrationStep =>
      _prefs.getInt(AppConstants.keyRegistrationStep);

  String? get savedProfileFlowMode =>
      _prefs.getString(AppConstants.keyProfileFlowMode);

  String? get savedProfileDraftJson =>
      _prefs.getString(AppConstants.keyProfileDraftJson);

  /// Snapshots "where the user currently is" on every app pause, so a cold
  /// start after the OS kills the process (e.g. backgrounded to verify an
  /// email in Gmail) can resume the same screen. [registrationStep],
  /// [profileFlowMode] and [profileDraftJson] should only be passed when
  /// [route] is the registration wizard or profile review — passing null
  /// clears them, which is what stops CREATE/EDIT state leaking into an
  /// unrelated later screen.
  Future<void> saveNavState({
    required String route,
    int? registrationStep,
    String? profileFlowMode,
    String? profileDraftJson,
  }) async {
    final futures = <Future<bool>>[
      _prefs.setString(AppConstants.keyLastRoute, route),
    ];
    futures.add(
      registrationStep != null
          ? _prefs.setInt(AppConstants.keyRegistrationStep, registrationStep)
          : _prefs.remove(AppConstants.keyRegistrationStep),
    );
    futures.add(
      profileFlowMode != null
          ? _prefs.setString(AppConstants.keyProfileFlowMode, profileFlowMode)
          : _prefs.remove(AppConstants.keyProfileFlowMode),
    );
    futures.add(
      profileDraftJson != null
          ? _prefs.setString(AppConstants.keyProfileDraftJson, profileDraftJson)
          : _prefs.remove(AppConstants.keyProfileDraftJson),
    );
    await Future.wait(futures);
  }

  Future<void> clearNavState() async {
    await Future.wait([
      _prefs.remove(AppConstants.keyLastRoute),
      _prefs.remove(AppConstants.keyRegistrationStep),
      _prefs.remove(AppConstants.keyProfileFlowMode),
      _prefs.remove(AppConstants.keyProfileDraftJson),
    ]);
  }

  // ─── Clear All ───────────────────────────────────────────────────
  Future<void> clearAll() async {
    await _prefs.clear();
  }

  /// Clears user-specific data while preserving app settings.
  /// Everything that identifies the signed-out user, dropped together.
  ///
  /// [onboardingCompleted] belongs here and not only in the signup flow that
  /// sets it: while it is set, the router lets a session-less device into
  /// every protected route (debug builds — see `_onboardingCompletedLocally`).
  /// Leaving it behind on sign-out meant logging out cleared the session but
  /// not the thing standing in for one, so protected routes stayed reachable
  /// and a relaunch resumed straight back into the app. Sign-out has to
  /// revoke the substitute as well as the real credential.
  Future<void> clearUserData() async {
    await Future.wait([
      clearTokens(),
      _prefs.remove(AppConstants.keyUserId),
      _prefs.remove(AppConstants.keyOnboardingCompleted),
      // A dev session is a session: signing out has to end it too, or the
      // next launch would still send the header and silently resume the
      // account the member just left.
      _prefs.remove(AppConstants.keyDevAuthPhone),
    ]);
  }
}

/// Global storage service instance.
final storageService = StorageService();
