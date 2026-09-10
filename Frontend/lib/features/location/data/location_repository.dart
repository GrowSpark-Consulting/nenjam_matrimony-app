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
      // The server caps this itself; asking for the maximum means the whole
      // subdivision is cached once and every subsequent search is local.
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
