import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../domain/models/religion_models.dart';

/// On-device cache for religion master data.
///
/// Deliberately its own SharedPreferences accessor rather than a method on
/// StorageService, for the same reason [LocationCache] is: `clearUserData()`
/// on sign-out must NOT drop it. It holds no user data — it is a copy of a
/// public reference table — and clearing it would make the next member on the
/// device re-download everything.
///
/// This mirrors `features/location/data/location_cache.dart` closely. The two
/// are kept separate rather than generalised because the location cache is
/// perf-critical and freshly covered by its own tests; folding them into one
/// `ReferenceCache` is worth doing, but as its own change.
class ReligionCache {
  const ReligionCache();

  static const String _prefix = 'religion_cache_';
  static const String _versionKey = '${_prefix}schema_version';

  /// Bump when the cached shape changes, so old entries are discarded rather
  /// than misread.
  static const int _schemaVersion = 1;

  /// Long enough to cover a registration session, short enough that a
  /// corrected label reaches members without an app update.
  static const Duration _ttl = Duration(days: 7);

  static String religionsKey() => '${_prefix}religions';
  static String communitiesKey(String religionCode) =>
      '${_prefix}communities_$religionCode';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<ReligionOption>?> read(String key) async {
    try {
      final prefs = await _prefs;
      if (prefs.getInt(_versionKey) != _schemaVersion) {
        await _clearAll(prefs);
        return null;
      }

      final raw = prefs.getString(key);
      if (raw == null) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final storedAt = decoded['at'] as int?;
      if (storedAt == null ||
          DateTime.now().millisecondsSinceEpoch - storedAt > _ttl.inMilliseconds) {
        await prefs.remove(key);
        return null;
      }

      final items = decoded['items'];
      if (items is! List) return null;
      return items
          .whereType<Map<String, dynamic>>()
          .map(ReligionOption.fromCacheJson)
          .toList(growable: false);
    } catch (error) {
      // A cache is an optimisation. Anything unreadable — corrupt JSON, a
      // storage backend that throws, a shape from an older build — means
      // "fetch it again", never an error the member has to see.
      debugPrint('ReligionCache read failed for $key: $error');
      return null;
    }
  }

  Future<void> write(String key, List<ReligionOption> options) async {
    try {
      final prefs = await _prefs;
      await prefs.setInt(_versionKey, _schemaVersion);
      await prefs.setString(
        key,
        jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'items': options.map((o) => o.toJson()).toList(),
        }),
      );
    } catch (error) {
      debugPrint('ReligionCache write failed for $key: $error');
    }
  }

  Future<void> _clearAll(SharedPreferences prefs) async {
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      await prefs.remove(key);
    }
  }

  /// Drops every cached entry. For tests and a future "refresh reference
  /// data" action; nothing calls it on sign-out.
  Future<void> clear() async => _clearAll(await _prefs);
}

/// Reads religion master data from the backend, cached on device.
///
/// Cache-first: a hit returns immediately and costs no network, a miss
/// fetches and stores. The endpoints are public, so these calls work before
/// the member has a session — which is the point, since the Religion step
/// runs several screens before auth.
class ReligionRepository {
  ReligionRepository(this._apiClient, {ReligionCache cache = const ReligionCache()})
      : _cache = cache;

  final ApiClient _apiClient;
  final ReligionCache _cache;

  Future<List<ReligionOption>> religions({CancelToken? cancelToken}) {
    return _fetch(
      cacheKey: ReligionCache.religionsKey(),
      path: ApiEndpoints.referenceReligions,
      cancelToken: cancelToken,
    );
  }

  /// Communities within one religion. Never all of them — the child level is
  /// only ever fetched for the parent the member actually chose.
  Future<List<ReligionOption>> communities(
    String religionCode, {
    CancelToken? cancelToken,
  }) {
    return _fetch(
      cacheKey: ReligionCache.communitiesKey(religionCode),
      path: ApiEndpoints.referenceCommunities,
      query: {'religionCode': religionCode},
      cancelToken: cancelToken,
    );
  }

  Future<List<ReligionOption>> _fetch({
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
        .map(ReligionOption.fromJson)
        .toList(growable: false);

    // Only a non-empty result is cached: an empty list is far more likely to
    // be a transient backend problem than a real answer, and caching it for a
    // week would strand the member with an empty dropdown. A religion that
    // genuinely has no communities simply re-asks, which is cheap.
    if (options.isNotEmpty) {
      await _cache.write(cacheKey, options);
    }
    return options;
  }
}
