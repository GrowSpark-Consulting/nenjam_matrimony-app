import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/theme/app_theme.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// Nenjam ships light-mode only.
///
/// The app must render [AppTheme.light] on a device whose system appearance
/// is Dark, and there must be no way — user setting, stored preference, or
/// provider — to put it into a dark theme. These tests pin all three halves
/// of that: the runtime behaviour, the absence of a dark [ThemeData], and the
/// absence of the Appearance/Dark Mode setting that used to switch it.
void main() {
  group('runtime', () {
    testWidgets('stays light when the platform brightness is dark', (
      tester,
    ) async {
      late BuildContext captured;

      await tester.pumpWidget(
        MediaQuery(
          // Exactly what a device in system Dark Mode reports.
          data: const MediaQueryData(platformBrightness: Brightness.dark),
          child: MaterialApp(
            themeMode: ThemeMode.light,
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                captured = context;
                return const Scaffold(body: Text('nenjam'));
              },
            ),
          ),
        ),
      );

      final theme = Theme.of(captured);
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.brightness, Brightness.light);
      // The concrete light surface, unchanged — not merely "some light theme".
      expect(
        theme.scaffoldBackgroundColor,
        AppTheme.light.scaffoldBackgroundColor,
      );
      expect(
        tester.widget<Material>(find.byType(Material).first).color,
        AppTheme.light.scaffoldBackgroundColor,
      );
    });

    test('AppTheme exposes a light theme and nothing dark', () {
      expect(AppTheme.light.brightness, Brightness.light);
      // `AppTheme.dark` is gone; if it comes back this file stops compiling
      // against it, and the source scan below fails first.
      expect(
        File('lib/core/theme/app_theme.dart').readAsStringSync(),
        isNot(contains('static ThemeData get dark')),
      );
    });
  });

  group('root app wiring', () {
    /// `main.dart` is the app's only entry point — it builds the root
    /// `MaterialApp.router`, so that is what has to be pinned. (The unused
    /// flavor entry `bootstrap.dart` was deleted; if one is reintroduced,
    /// add it to this list.)
    for (final path in ['lib/main.dart']) {
      test('$path forces ThemeMode.light with no darkTheme', () {
        final source = File(path).readAsStringSync();

        expect(source, contains('themeMode: ThemeMode.light'));
        expect(source, contains('theme: AppTheme.light'));
        // No dark ThemeData is handed to MaterialApp at all, so even a stray
        // ThemeMode.dark could not produce a dark surface.
        expect(source, isNot(contains('darkTheme')));
        // The mode is a constant, never read from a provider or storage.
        expect(source, isNot(contains('themeModeProvider')));
        expect(source, isNot(contains('storageService.themeMode')));
      });
    }

    test('no theme-preference state survives anywhere in lib/', () {
      expect(File('lib/core/providers/theme_mode_provider.dart').existsSync(),
          isFalse);

      final offenders = <String>[];
      final banned = RegExp(
        r'ThemeMode\.(dark|system)|themeModeProvider|keyThemeMode|'
        r"'theme_mode'|setThemeMode",
      );

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (banned.hasMatch(lines[i])) {
            offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Dark mode is removed; nothing may select or persist a ThemeMode:\n'
            '${offenders.join('\n')}',
      );
    });

    test('no dead dark-mode branches remain', () {
      // Every `isDark ? dark : light` was folded to the light branch it
      // already rendered. A new one would be dead code from the day it is
      // written, so it is worth failing on.
      final offenders = <String>[];
      final banned = RegExp(r'(?<![A-Za-z0-9_$])isDark(?![A-Za-z0-9_$])');

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (banned.hasMatch(lines[i])) {
            offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'The app is light-mode only, so these branches are dead:\n'
            '${offenders.join('\n')}',
      );
    });

    test('only the status bar and the light theme consult Brightness', () {
      // `Brightness` itself is legitimate: AppTheme declares the light theme
      // with it, and NmStatusBarStyle derives status-bar icon colour from the
      // background actually being painted. Nothing else should care.
      const allowed = {
        'lib/core/theme/app_theme.dart',
        'lib/core/widgets/system_ui/nm_status_bar_style.dart',
      };
      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.split(Platform.pathSeparator).join('/');
        if (allowed.contains(path) || path.contains('/l10n/')) continue;
        if (entity.readAsStringSync().contains('Brightness')) {
          offenders.add(path);
        }
      }

      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('nothing reads the device appearance', () {
      final offenders = <String>[];
      final banned = RegExp(r'platformBrightness');

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (banned.hasMatch(entity.readAsStringSync())) {
          offenders.add(entity.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'The system appearance must not reach any widget:\n'
            '${offenders.join('\n')}',
      );
    });
  });

  group('the Dark Mode setting is gone', () {
    test('Settings renders no appearance/theme control', () {
      final source =
          File('lib/features/settings/presentation/pages/settings_page.dart')
              .readAsStringSync();

      expect(source, isNot(contains('dark_mode')));
      expect(source, isNot(contains('ThemeMode')));
      expect(source, isNot(contains('DarkMode')));
      // The App Preferences section survives — it still holds Language.
      expect(source, contains('settingsAppPreferencesSection'));
      expect(source, contains('settingsLanguage'));
    });

    test('its localization strings are gone from both locales', () {
      for (final path in [
        'lib/l10n/app_en.arb',
        'lib/l10n/app_ta.arb',
        'lib/l10n/app_localizations.dart',
        'lib/l10n/app_localizations_en.dart',
        'lib/l10n/app_localizations_ta.dart',
      ]) {
        expect(
          File(path).readAsStringSync(),
          isNot(contains('settingsDarkMode')),
          reason: '$path still carries the removed Dark Mode label',
        );
      }
    });

    test('no user-facing dark/light-mode copy remains', () {
      final banned = RegExp(
        r'Dark Mode|Light Mode|Light / Dark|System Default|System Theme',
        caseSensitive: false,
      );
      final offenders = <String>[];

      for (final path in ['lib/l10n/app_en.arb', 'lib/l10n/app_ta.arb']) {
        final lines = File(path).readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (banned.hasMatch(lines[i])) offenders.add('$path:${i + 1}');
        }
      }

      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });
}
