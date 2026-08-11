import 'dart:ui';

import '../../l10n/app_localizations.dart';
import '../constants/app_constants.dart';

/// Context-free access to the active [AppLocalizations].
///
/// Almost all UI should keep using `AppLocalizations.of(context)` — it is
/// tied to the widget tree and rebuilds correctly. This exists only for the
/// handful of layers that produce user-facing text but legitimately have no
/// `BuildContext` to hand:
///
///  * `Validators` — called as bare tear-offs (`validator: Validators.email`)
///    from `TextFormField`, which passes only the value.
///  * `AuthErrorMapper` — called from Riverpod controllers, which sit outside
///    the widget tree.
///  * `ApiInterceptor` — a Dio interceptor, further still from any context.
///
/// [locale] is kept in sync by `LocaleNotifier` (see
/// `core/providers/locale_provider.dart`), which assigns it synchronously
/// both when it seeds from storage and when the user switches language —
/// before it awaits the SharedPreferences write. That ordering matters: a
/// validator that runs in the same frame as a language switch must already
/// see the new locale, so this is deliberately not read back off disk.
abstract final class AppL10n {
  static Locale _locale = const Locale(AppConstants.defaultLanguage);

  /// The locale the app is currently rendering in.
  static Locale get locale => _locale;

  /// Called by `LocaleNotifier` only. Ignores unsupported codes so this can
  /// never fall out of step with what `MaterialApp` is actually showing.
  static set locale(Locale value) {
    if (!AppConstants.activeLanguages.contains(value.languageCode)) return;
    _locale = value;
  }

  /// Strings for the active locale. Synchronous — the generated
  /// `lookupAppLocalizations` builds the class directly, with no async
  /// delegate load involved.
  static AppLocalizations get current => lookupAppLocalizations(_locale);
}
