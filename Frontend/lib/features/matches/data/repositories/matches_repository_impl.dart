import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../../discover/data/models/discovery_profile_model.dart';
import '../../domain/repositories/matches_repository.dart';

/// Real backend implementation — dormant, not wired to any provider.
///
/// TODO(backend): the `matches` controller is currently an empty stub —
/// zero routes, despite `ApiEndpoints.matches`/`.matchInterest`/
/// `.matchShortlist`/`.matchDecline`/`.matchViewed` all being defined.
/// Response shape for `getMatches` follows the same proposed pagination
/// envelope as Discover/Search: `{ items, page, limit, total, hasMore }`,
/// items shaped like [DiscoveryProfileModel.fromJson].
class MatchesRepositoryImpl implements MatchesRepository {
  MatchesRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<MatchesResultPage> getMatches({int page = 1, int limit = 20}) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.matches,
      queryParameters: {'page': page, 'limit': limit},
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    final items = (data['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(DiscoveryProfileModel.fromJson)
        .toList();
    return MatchesResultPage(
      items: items,
      page: (data['page'] as num?)?.toInt() ?? page,
      limit: (data['limit'] as num?)?.toInt() ?? limit,
      total: (data['total'] as num?)?.toInt() ?? items.length,
      hasMore: data['hasMore'] as bool? ?? false,
    );
  }

  @override
  Future<void> expressInterest(String profileId) =>
      _postAction(ApiEndpoints.matchInterest, profileId);

  @override
  Future<void> shortlist(String profileId) =>
      _postAction(ApiEndpoints.matchShortlist, profileId);

  @override
  Future<void> decline(String profileId) =>
      _postAction(ApiEndpoints.matchDecline, profileId);

  @override
  Future<void> markViewed(String profileId) =>
      _postAction(ApiEndpoints.matchViewed, profileId);

  Future<void> _postAction(String path, String profileId) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      path,
      data: {'profileId': profileId},
    );
    unwrapOrThrow(response.statusCode, response.data);
  }
}
