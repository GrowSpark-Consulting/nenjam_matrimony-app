import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/location_models.dart';

/// On-device cache for location master data.
///
/// The dataset changes only when the backend is deployed, so re-fetching a
/// country list the member already has is pure latency on the registration
/// path. Entries are cached per key (`countries`, `states:IN`,
/// `cities:IN-TN`) and expire after [_ttl].
///
/// Deliberately its own SharedPreferences accessor rather than a method on
/// StorageService: `clearUserData()` on sign-out must NOT drop this. It holds
/// no user data — it is a copy of a public reference table — and clearing it
/// would make the next member on the device re-download everything.
class LocationCache {
  const LocationCache();

  static const String _prefix = 'location_cache_';
  static const String _versionKey = '${_prefix}schema_version';

  /// Bump when [LocationOption]'s cached shape changes, so old entries are
  /// discarded rather than misread.
  static const int _schemaVersion = 1;

  /// Long enough to cover a registration session and several days of app use,
  /// short enough that a corrected label reaches members without an update.
  static const Duration _ttl = Duration(days: 7);

  static String countriesKey() => '${_prefix}countries';
  static String statesKey(String countryCode) => '${_prefix}states_$countryCode';
  static String citiesKey(String stateCode) => '${_prefix}cities_$stateCode';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<LocationOption>?> read(String key) async {
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
          .map(LocationOption.fromCacheJson)
          .toList(growable: false);
    } catch (error) {
      // A cache is an optimisation. Anything unreadable — corrupt JSON, a
      // storage backend that throws, a shape from an older build — means
      // "fetch it again", never an error the member has to see.
      debugPrint('LocationCache read failed for $key: $error');
      return null;
    }
  }

  Future<void> write(String key, List<LocationOption> options) async {
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
      debugPrint('LocationCache write failed for $key: $error');
    }
  }

  Future<void> _clearAll(SharedPreferences prefs) async {
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      await prefs.remove(key);
    }
  }

  /// Drops every cached entry. Exposed for tests and for a future
  /// "refresh reference data" action; nothing calls it on sign-out.
  Future<void> clear() async => _clearAll(await _prefs);
}
