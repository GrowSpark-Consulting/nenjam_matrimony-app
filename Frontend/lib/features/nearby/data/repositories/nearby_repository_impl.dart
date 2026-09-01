import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../../discover/data/models/discovery_profile_model.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../domain/repositories/nearby_repository.dart';

/// Backend-backed Near Me.
///
/// Reuses [DiscoveryProfileModel] rather than defining a parallel model: the
/// backend deliberately returns the same card shape as `/discover` with
/// `distanceKm` filled in (it was already on the contract, always null, before
/// this feature existed), so the existing card widgets and Profile Detail
/// navigation work here untouched.
class NearbyRepositoryImpl implements NearbyRepository {
  NearbyRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  /// Server-side maximum. Sent explicitly rather than relying on the backend
  /// default so the radius shown in the UI copy and the radius actually
  /// searched can never drift apart.
  static const defaultRadiusKm = 100.0;

  @override
  Future<List<DiscoveryProfileEntity>> getNearbyProfiles({
    required double latitude,
    required double longitude,
    double radiusKm = defaultRadiusKm,
    int page = 1,
    int limit = 50,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.profilesNearby,
      queryParameters: {
        'latitude': latitude,
        'longitude': longitude,
        'radiusKm': radiusKm,
        'page': page,
        'limit': limit,
      },
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? const {};

    // Dedupe by id for the same reason the Discover feed does: every card
    // shares a `Hero(tag: 'profile-photo-$id')`, and two cards with one id
    // makes Flutter throw on navigation rather than merely look wrong.
    final seen = <String>{};
    final profiles = <DiscoveryProfileEntity>[];
    for (final raw in (data['profiles'] as List<dynamic>? ?? const [])) {
      final json = Map<String, dynamic>.from(raw as Map);
      json['gender'] = normalizeProfileGender(json['gender']);
      final profile = DiscoveryProfileModel.fromJson(json);
      if (seen.add(profile.id)) profiles.add(profile);
    }

    // The server already sorts by ascending distance; this is not a re-sort of
    // its work but a guard on the one invariant the whole screen rests on, at
    // the cost of a near-sorted pass over at most one page.
    profiles.sort(
      (a, b) => (a.distanceKm ?? double.infinity).compareTo(
        b.distanceKm ?? double.infinity,
      ),
    );

    return profiles;
  }

  @override
  Future<void> updateMyLocation({
    required double latitude,
    required double longitude,
    int? accuracyMetres,
  }) async {
    final response = await _apiClient.put<Map<String, dynamic>>(
      ApiEndpoints.profileMeLocation,
      data: {
        'latitude': latitude,
        'longitude': longitude,
        if (accuracyMetres != null) 'accuracyM': accuracyMetres,
      },
    );
    unwrapOrThrow(response.statusCode, response.data);
  }
}
