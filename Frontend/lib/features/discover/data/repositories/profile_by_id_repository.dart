import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/discovery_profile_entity.dart';
import '../models/discovery_profile_model.dart';

/// Reads one member's profile by id (`GET /discover/profiles/:userId`).
///
/// Used when a profile URL is opened without the profile in memory — a browser
/// refresh, a copied link. The backend applies the same visibility rules as the
/// feed, so "not visible to you" and "does not exist" are the same answer.
class ProfileByIdRepository {
  const ProfileByIdRepository(this._apiClient);

  final ApiClient _apiClient;

  /// The profile, or null when the backend says it is not available to this
  /// member (404). Any other failure — offline, 401, 5xx — is thrown so the
  /// caller can offer a retry instead of reporting a missing profile.
  Future<DiscoveryProfileEntity?> get(String userId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.discoverProfile(userId),
    );
    if (response.statusCode == 404) return null;
    final data = unwrapOrThrow(response.statusCode, response.data);
    if (data == null) return null;
    return DiscoveryProfileModel.fromJson(data);
  }
}
