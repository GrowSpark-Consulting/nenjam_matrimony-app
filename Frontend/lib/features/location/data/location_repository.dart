import 'package:dio/dio.dart' show CancelToken;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../domain/models/location_models.dart';
import 'location_cache.dart';

/// Reads location master data from the backend, cached on device.
///
/// Every method is cache-first: a hit returns immediately and costs no
/// network, a miss fetches and stores. The endpoints are public, so these
/// calls work before the member has a session — which is the point, since the
/// location step happens during registration.
class LocationRepository {
  LocationRepository(this._apiClient, {LocationCache cache = const LocationCache()})
      : _cache = cache;

  final ApiClient _apiClient;
  final LocationCache _cache;

  Future<List<LocationOption>> countries({CancelToken? cancelToken}) {
    return _fetch(
      cacheKey: LocationCache.countriesKey(),
      path: ApiEndpoints.referenceCountries,
      cancelToken: cancelToken,
    );
  }

  Future<List<LocationOption>> states(String countryCode, {CancelToken? cancelToken}) {
    return _fetch(
      cacheKey: LocationCache.statesKey(countryCode),
      path: ApiEndpoints.referenceStates,
      query: {'countryCode': countryCode},
      cancelToken: cancelToken,
    );
  }

  Future<List<LocationOption>> cities(String stateCode, {CancelToken? cancelToken}) {
    return _fetch(
      cacheKey: LocationCache.citiesKey(stateCode),
      path: ApiEndpoints.referenceCities,
      // One request per subdivision, then every search is local — which is
      // why this asks for the maximum rather than the server's default page
      // of 200. `filteredCitiesProvider` filters what it was given, so a
      // truncated page would silently hide real cities from search.
      //
      // The largest subdivision in the dataset is GB-ENG at 743 cities and
      // only 13 exceed 200, so 1000 covers every one of them today. The
      // server's own cap is 1000, and `cities.csv` is checked against that
      // ceiling by the seeder's spec.
      //
      // Worth it because the round trip dominates: ~330ms of network versus a
      // 43KB body for Tamil Nadu, cached on device for 7 days. Paging would
      // trade one request for several, each paying that 330ms again.
      query: {'stateCode': stateCode, 'limit': 1000},
      cancelToken: cancelToken,
    );
  }

  Future<List<LocationOption>> _fetch({
    required String cacheKey,
    required String path,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) async {
    final cached = await _cache.read(cacheKey);
    if (cached != null && cached.isNotEmpty) return cached;

    final response = await _apiClient.get<dynamic>(
      path,
      queryParameters: query,
      cancelToken: cancelToken,
    );
    final data = unwrapOrThrow(response.statusCode, response.data);
    if (data is! List) {
      throw ApiException(response.statusCode, 'Unexpected response for $path.');
    }

    final options = data
        .whereType<Map<String, dynamic>>()
        .map(LocationOption.fromJson)
        .toList(growable: false);

    // Only a non-empty result is worth caching: an empty list is far more
    // likely to be a transient backend problem than a real answer, and
    // caching it for a week would strand the member with an empty dropdown.
    if (options.isNotEmpty) {
      await _cache.write(cacheKey, options);
    }
    return options;
  }
}
