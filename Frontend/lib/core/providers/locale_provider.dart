import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../l10n/app_l10n.dart';
import '../services/storage_service.dart';

/// Manages the app's active [Locale] and persists the user's choice.
///
/// [build] seeds the locale from [StorageService] (backed by the
/// `selected_language` key) so a restart restores the saved language.
/// `MaterialApp.locale` watches this provider, so changing [state]
/// instantly rebuilds the whole app with the new localization.
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => _resolveSavedLocale();

  Locale _resolveSavedLocale() {
    final code = storageService.language; // never null (falls back to default)
    final active = AppConstants.activeLanguages.contains(code)
        ? code
        : AppConstants.defaultLanguage;
    final locale = Locale(active);
    // Mirror into the context-free accessor used by Validators /
    // AuthErrorMapper / ApiInterceptor — see [AppL10n].
    AppL10n.locale = locale;
    return locale;
  }

  /// Re-reads the persisted language and applies it. Useful to force a
  /// refresh from storage; [build] already does this on first read.
  void loadSavedLocale() {
    state = _resolveSavedLocale();
  }

  /// Applies [languageCode] to the whole app immediately, then persists it.
  ///
  /// State is updated first so the UI switches without waiting on disk I/O;
  /// SharedPreferences is written afterwards for restart persistence.
  Future<void> changeLocale(String languageCode) async {
    if (!AppConstants.activeLanguages.contains(languageCode)) return;
    // 1. Update state immediately -> rebuilds MaterialApp.router. Mirrored
    //    into AppL10n in the same synchronous step so context-free callers
    //    (validators, error mappers) can't read a stale locale in the frame
    //    the switch happens.
    final locale = Locale(languageCode);
    AppL10n.locale = locale;
    state = locale;
    // 2. Persist for the next app launch.
    await storageService.setLanguage(languageCode);
  }
}

/// Global provider for the active app locale.
final localeProvider = NotifierProvider<LocaleNotifier, Locale>(
  LocaleNotifier.new,
);
