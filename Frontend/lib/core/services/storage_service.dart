import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

/// Nenjam Matrimony — Local Storage Service
///
/// Wraps SharedPreferences for type-safe, centralized local storage.
/// Handles theme mode, language, tokens, and user preferences.
class StorageService {
  late final SharedPreferences _prefs;

  /// Must be called before using the service.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ─── Theme ───────────────────────────────────────────────────────
  ThemeMode get themeMode {
    final value = _prefs.getString(AppConstants.keyThemeMode);
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _prefs.setString(AppConstants.keyThemeMode, value);
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
  String? get accessToken =>
      _prefs.getString(AppConstants.keyAccessToken);

  Future<void> setAccessToken(String token) async {
    await _prefs.setString(AppConstants.keyAccessToken, token);
  }

  String? get refreshToken =>
      _prefs.getString(AppConstants.keyRefreshToken);

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

  // ─── Onboarding ──────────────────────────────────────────────────
  bool get isOnboardingDone =>
      _prefs.getBool(AppConstants.keyOnboardingDone) ?? false;

  Future<void> setOnboardingDone() async {
    await _prefs.setBool(AppConstants.keyOnboardingDone, true);
  }

  // ─── Improve Profile prompt (Relationship Intelligence hub) ──────
  bool get hasSeenImproveProfilePrompt =>
      _prefs.getBool(AppConstants.keyImproveProfilePromptSeen) ?? false;

  Future<void> setImproveProfilePromptSeen() async {
    await _prefs.setBool(AppConstants.keyImproveProfilePromptSeen, true);
  }

  // ─── Notifications ──────────────────────────────────────────────
  bool get notificationsEnabled =>
      _prefs.getBool(AppConstants.keyNotificationsEnabled) ?? true;

  Future<void> setNotificationsEnabled(bool enabled) async {
    await _prefs.setBool(AppConstants.keyNotificationsEnabled, enabled);
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
    final futures = <Future<bool>>[_prefs.setString(AppConstants.keyLastRoute, route)];
    futures.add(registrationStep != null
        ? _prefs.setInt(AppConstants.keyRegistrationStep, registrationStep)
        : _prefs.remove(AppConstants.keyRegistrationStep));
    futures.add(profileFlowMode != null
        ? _prefs.setString(AppConstants.keyProfileFlowMode, profileFlowMode)
        : _prefs.remove(AppConstants.keyProfileFlowMode));
    futures.add(profileDraftJson != null
        ? _prefs.setString(AppConstants.keyProfileDraftJson, profileDraftJson)
        : _prefs.remove(AppConstants.keyProfileDraftJson));
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
  Future<void> clearUserData() async {
    await Future.wait([
      clearTokens(),
      _prefs.remove(AppConstants.keyUserId),
    ]);
  }
}

/// Global storage service instance.
final storageService = StorageService();
