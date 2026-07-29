import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/storage_service.dart';

/// Manages the app's active [ThemeMode] and persists the user's choice.
///
/// Mirrors [LocaleNotifier]'s shape exactly. [build] seeds the mode from
/// [StorageService] so a restart restores the saved preference.
/// `MaterialApp.themeMode` watches this provider, so changing [state]
/// instantly rebuilds the whole app with the new theme — before this
/// provider existed, `main.dart` read `storageService.themeMode` as a
/// one-off getter, so toggling it anywhere had no visible effect until
/// the next cold start.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => storageService.themeMode;

  /// Applies [mode] to the whole app immediately, then persists it.
  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await storageService.setThemeMode(mode);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
