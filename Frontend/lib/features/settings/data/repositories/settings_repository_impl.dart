import 'package:dio/dio.dart' show CancelToken;
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/repositories/settings_repository.dart';

/// Real backend implementation, wired through `settingsRepositoryProvider`
/// (`settings_providers.dart`) and used by the Privacy page
/// (`updatePrivacySettings`) and the Settings page (`deleteAccount`).
///
/// Backed by the `settings` controller's `GET /settings`,
/// `PATCH /settings/privacy` and `DELETE /settings/delete-account` routes.
class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<Map<String, dynamic>> getSettings({CancelToken? cancelToken}) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.settings,
      cancelToken: cancelToken,
    );
    return unwrapOrThrow(response.statusCode, response.data) ?? {};
  }

  @override
  Future<void> updatePrivacySettings(Map<String, dynamic> settings) async {
    final response = await _apiClient.patch<Map<String, dynamic>>(
      ApiEndpoints.privacySettings,
      data: settings,
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  @override
  Future<void> deleteAccount() async {
    final response =
        await _apiClient.delete<Map<String, dynamic>>(ApiEndpoints.deleteAccount);
    unwrapOrThrow(response.statusCode, response.data);
  }
}
