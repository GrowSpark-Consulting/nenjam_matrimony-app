import 'package:dio/dio.dart' show CancelToken;

/// Pure abstract Dart interface. Concrete implementation lives in `data/`.
/// Covers only the `settings` module's own endpoints; the Push
/// Notifications toggle belongs to the `notifications` module, and the
/// Language row is a purely local preference, so neither routes through
/// here.
abstract interface class SettingsRepository {
  /// `GET /settings` — the raw JSON (`isPremium`, `hideMyProfile`,
  /// `hidePhotosFromNonConnections`), not yet a typed entity.
  Future<Map<String, dynamic>> getSettings({CancelToken? cancelToken});

  /// `PATCH /settings/privacy` — a partial update; send only the keys that
  /// changed. The backend answers 403 when a non-premium member tries to
  /// switch a privacy feature on.
  Future<void> updatePrivacySettings(Map<String, dynamic> settings);

  /// `DELETE /settings/delete-account`.
  Future<void> deleteAccount();
}
