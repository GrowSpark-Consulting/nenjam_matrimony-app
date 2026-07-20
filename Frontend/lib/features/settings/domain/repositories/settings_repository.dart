/// Pure abstract Dart interface. Concrete implementation lives in `data/`.
/// Not wired to any provider today — `settings_page.dart`'s Dark Mode
/// switch is hardcoded/non-functional (though it needs no backend call —
/// `StorageService.setThemeMode()` already persists it locally), and there
/// is no delete-account UI at all. Covers only the `settings` module's own
/// endpoints; the Push Notifications toggle belongs to the `notifications`
/// module, which is out of scope for this pass.
abstract interface class SettingsRepository {
  /// `GET /settings`. Shape is undefined — the `settings` controller is
  /// currently an empty stub — so this returns the raw JSON rather than a
  /// typed entity until a contract exists.
  Future<Map<String, dynamic>> getSettings();

  /// `PATCH /settings/privacy` (proposed method — backend is a stub, exact
  /// verb/shape not confirmed).
  Future<void> updatePrivacySettings(Map<String, dynamic> settings);

  /// `DELETE /settings/delete-account`.
  Future<void> deleteAccount();
}
