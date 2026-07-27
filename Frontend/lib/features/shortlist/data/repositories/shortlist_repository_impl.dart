import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../../discover/data/models/discovery_profile_model.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../domain/repositories/shortlist_repository.dart';

/// Live backend implementation, wired via `shortlistRepositoryProvider`.
/// `GET /matches/shortlist` returns a bare JSON array of `DiscoveryProfileDto`;
/// `POST`/`DELETE /matches/shortlist` add/remove by `{ profileId }`.
class ShortlistRepositoryImpl implements ShortlistRepository {
  ShortlistRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<DiscoveryProfileEntity>> getShortlisted({
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _apiClient.get<List<dynamic>>(
      ApiEndpoints.matchShortlist,
      queryParameters: {'page': page, 'limit': limit},
    );
    final data = unwrapOrThrow(response.statusCode, response.data);
    return (data ?? [])
        .cast<Map<String, dynamic>>()
        .map(DiscoveryProfileModel.fromJson)
        .toList();
  }

  @override
  Future<void> add(DiscoveryProfileEntity profile) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.matchShortlist,
      data: {'profileId': profile.id},
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  @override
  Future<void> remove(String profileId) async {
    final response = await _apiClient.delete<Map<String, dynamic>>(
      ApiEndpoints.matchShortlist,
      data: {'profileId': profileId},
    );
    unwrapOrThrow(response.statusCode, response.data);
  }
}
