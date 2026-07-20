import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../domain/models/profile.dart';

/// Thrown when the backend rejects a `GET /profiles/me` request — carries
/// the backend's own message when available. Mirrors
/// RegistrationApiException's shape (see registration_repository.dart) —
/// kept as a separate type since this feature isn't a fork of the wizard,
/// just the same error-unwrapping convention.
class ProfileApiException implements Exception {
  ProfileApiException(this.statusCode, this.message);
  final int? statusCode;
  final String message;

  @override
  String toString() => 'ProfileApiException($statusCode): $message';
}

/// Talks to backend/apps/api/src/modules/profiles' ProfileController.
/// Read-only — editing continues through RegistrationRepository (the wizard
/// PATCH /profiles/draft/* + POST /profiles/finalize flow already wired via
/// RegistrationNotifier.startEditMode()).
class ApiProfileRepository {
  ApiProfileRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<Profile> getMyProfile() async {
    final response =
        await _apiClient.get<Map<String, dynamic>>(ApiEndpoints.profileMe);
    final data = _unwrap(response.statusCode, response.data);
    return Profile.fromJson(data!);
  }

  Map<String, dynamic>? _unwrap(int? statusCode, Map<String, dynamic>? data) {
    if (statusCode != null && statusCode >= 400) {
      final message = data?['message'];
      throw ProfileApiException(
        statusCode,
        message is String
            ? message
            : message is List && message.isNotEmpty
                ? message.join(', ')
                : 'Request failed ($statusCode).',
      );
    }
    return data;
  }
}
