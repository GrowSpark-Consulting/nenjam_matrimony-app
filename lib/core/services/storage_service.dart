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
  String get language =>
      _prefs.getString(AppConstants.keyLanguage) ?? 'en';

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
