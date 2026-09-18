import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../../discover/data/models/discovery_profile_model.dart';
import '../../domain/repositories/search_repository.dart';

/// Real backend search, over `GET /discover/search`.
///
/// The response envelope is byte-for-byte the Discover feed's
/// (`DiscoverFeedResponseDto`), which is why this reuses
/// [DiscoveryProfileModel.fromJson] rather than declaring a parallel search
/// model — the backend's `SearchService` maps rows through the same
/// `ProfileFeedMapper` the feed uses.
///
/// Only `q`, `page` and `limit` are sent, because those are the only
/// parameters the endpoint reads. Filters are applied client-side over the
/// result — see [SearchRepository]'s doc comment for why they are not sent.
class SearchRepositoryImpl implements SearchRepository {
  SearchRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<SearchResultPage> search({
    required String query,
    int page = 1,
    int limit = 20,
  }) async {
    final term = query.trim();
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.discoverSearch,
      queryParameters: {
        // Omitted rather than sent empty when there's no term: the backend
        // treats a blank `q` as "no text predicate", i.e. the eligible feed
        // unfiltered, which is exactly what a filters-only search wants.
        if (term.isNotEmpty) 'q': term,
        'page': page,
        'limit': limit,
      },
    );

    // ApiClient uses `validateStatus: status < 500`, so a 401/429/4xx arrives
    // as a normal response — unwrapOrThrow is what turns it into an
    // ApiException the provider can surface as AsyncError.
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    final items = (data['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(DiscoveryProfileModel.fromJson)
        .toList();

    return SearchResultPage(
      items: items,
      page: (data['page'] as num?)?.toInt() ?? page,
      limit: (data['limit'] as num?)?.toInt() ?? limit,
      total: (data['total'] as num?)?.toInt() ?? items.length,
      hasMore: data['hasMore'] as bool? ?? false,
    );
  }
}
