import 'package:dio/dio.dart' show CancelToken;
/// Pure abstract Dart interface. Concrete implementation lives in `data/`.
/// Covers only the `settings` module's own endpoints; the Push
/// Notifications toggle belongs to the `notifications` module, and the
/// Language row is a purely local preference, so neither routes through
/// here.
abstract interface class SettingsRepository {
  /// `GET /settings`. Shape is undefined — the `settings` controller is
  /// currently an empty stub — so this returns the raw JSON rather than a
  /// typed entity until a contract exists.
  Future<Map<String, dynamic>> getSettings({CancelToken? cancelToken});

  /// `PATCH /settings/privacy` (proposed method — backend is a stub, exact
  /// verb/shape not confirmed).
  Future<void> updatePrivacySettings(Map<String, dynamic> settings);

  /// `DELETE /settings/delete-account`.
  Future<void> deleteAccount();
}
