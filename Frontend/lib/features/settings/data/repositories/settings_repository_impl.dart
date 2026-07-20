import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/repositories/settings_repository.dart';

/// Real backend implementation — dormant, not wired to any provider.
///
/// TODO(backend): the `settings` controller is currently an empty stub —
/// zero routes, despite `ApiEndpoints.settings`/`.privacySettings`/
/// `.deleteAccount` all being defined.
class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<Map<String, dynamic>> getSettings() async {
    final response =
        await _apiClient.get<Map<String, dynamic>>(ApiEndpoints.settings);
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
