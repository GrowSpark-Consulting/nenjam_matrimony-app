import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../../discover/data/models/discovery_profile_model.dart';
import '../../domain/entities/search_filters_entity.dart';
import '../../domain/repositories/search_repository.dart';

/// Real backend implementation — dormant, not wired to any provider.
/// `search_providers.dart` still filters client-side over Discover's shared
/// mock pool; nothing constructs this class today.
///
/// TODO(backend): the `search` controller is currently an empty stub —
/// zero routes. Proposed contract (same shape as Discover's proposed
/// `/search?category=` contract — see discover_remote_datasource.dart),
/// extended with a free-text `query` and the [SearchFilters] fields:
///   GET /search?query=&page=&limit=&(filter params)
///   -> { items: DiscoveryProfileDto[], page, limit, total, hasMore }
/// Filter fields with no matching entity field yet (gender, country,
/// state, annualIncome, smoking, drinking, rashi, star, incomeVerified —
/// see [SearchFilters]'s own doc comment) are still sent as query params
/// here so the contract is ready the moment the backend defines them; the
/// response mapping doesn't depend on them being honoured.
class SearchRepositoryImpl implements SearchRepository {
  SearchRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<SearchResultPage> search({
    required String query,
    required SearchFilters filters,
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.search,
      queryParameters: {
        if (query.isNotEmpty) 'query': query,
        'page': page,
        'limit': limit,
        ..._filterParams(filters),
      },
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    final items = (data['items'] as List<dynamic>? ?? [])
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

  Map<String, dynamic> _filterParams(SearchFilters f) => {
        'ageMin': f.ageRange.start.round(),
        'ageMax': f.ageRange.end.round(),
        if (f.heightMin != null) 'heightMin': f.heightMin,
        if (f.heightMax != null) 'heightMax': f.heightMax,
        if (f.gender != null) 'gender': f.gender,
        if (f.religion != null) 'religion': f.religion,
        if (f.caste != null) 'caste': f.caste,
        if (f.community != null) 'community': f.community,
        if (f.country != null) 'country': f.country,
        if (f.state != null) 'state': f.state,
        if (f.city != null) 'city': f.city,
        if (f.education != null) 'education': f.education,
        if (f.occupation != null) 'occupation': f.occupation,
        if (f.annualIncome != null) 'annualIncome': f.annualIncome,
        if (f.diet != null) 'diet': f.diet,
        if (f.smoking != null) 'smoking': f.smoking,
        if (f.drinking != null) 'drinking': f.drinking,
        if (f.rashi != null) 'rashi': f.rashi,
        if (f.star != null) 'star': f.star,
        if (f.horoscopeAvailable) 'horoscopeAvailable': true,
        if (f.aadhaarVerified) 'aadhaarVerified': true,
        if (f.incomeVerified) 'incomeVerified': true,
        if (f.nriVerified) 'nriVerified': true,
        if (f.premiumOnly) 'premiumOnly': true,
        if (f.withPhoto) 'withPhoto': true,
        if (f.completedProfile) 'completedProfile': true,
      };
}
