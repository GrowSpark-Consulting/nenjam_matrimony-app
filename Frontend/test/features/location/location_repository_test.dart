import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_client.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/location/data/location_cache.dart';
import 'package:nenjam_matrimony/features/location/data/location_repository.dart';
import 'package:nenjam_matrimony/features/location/domain/models/location_models.dart';

/// An in-memory stand-in for [LocationCache], so these tests exercise the
/// cache-first behaviour without touching SharedPreferences.
class _FakeCache implements LocationCache {
  final Map<String, List<LocationOption>> store = {};
  final List<String> reads = [];
  final List<String> writes = [];

  @override
  Future<List<LocationOption>?> read(String key) async {
    reads.add(key);
    return store[key];
  }

  @override
  Future<void> write(String key, List<LocationOption> options) async {
    writes.add(key);
    store[key] = options;
  }

  @override
  Future<void> clear() async => store.clear();
}

/// Counts requests and replays canned responses, so a test can assert that
/// a second call did NOT reach the network.
class _StubClient extends ApiClient {
  _StubClient(this._responses);

  final Map<String, dynamic> _responses;
  final List<String> requested = [];
  int status = 200;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    requested.add(path);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: status,
      data: _responses[path] as T?,
    );
  }
}

void main() {
  group('LocationRepository', () {
    late _FakeCache cache;
    late _StubClient client;
    late LocationRepository repository;

    setUp(() {
      cache = _FakeCache();
      client = _StubClient({
        '/reference-data/countries': [
          {'code': 'IN', 'label': 'India'},
          {'code': 'SG', 'label': 'Singapore'},
        ],
        '/reference-data/states': [
          {'code': 'IN-TN', 'label': 'Tamil Nadu', 'type': 'State', 'countryCode': 'IN'},
        ],
        '/reference-data/cities': [
          {
            'code': 'IN-TN-CHENNAI',
            'label': 'Chennai',
            'stateCode': 'IN-TN',
            'countryCode': 'IN',
          },
        ],
      });
      repository = LocationRepository(client, cache: cache);
    });

    test('parses countries and keeps the code as the stored value', () async {
      final countries = await repository.countries();
      expect(countries.map((c) => c.code), ['IN', 'SG']);
      expect(countries.first.label, 'India');
    });

    test('reads a state list through to its parent country code', () async {
      final states = await repository.states('IN');
      expect(states.single.code, 'IN-TN');
      expect(states.single.parentCode, 'IN');
      expect(states.single.type, 'State');
    });

    test('reads a city list through to its parent state code', () async {
      final cities = await repository.cities('IN-TN');
      expect(cities.single.code, 'IN-TN-CHENNAI');
      // A city's parent is its state, not its country — this is what the
      // cascade uses to know a selection is still valid.
      expect(cities.single.parentCode, 'IN-TN');
    });

    test('serves a second call from cache without touching the network', () async {
      await repository.countries();
      expect(client.requested, ['/reference-data/countries']);

      await repository.countries();
      expect(
        client.requested,
        ['/reference-data/countries'],
        reason: 'the second call should have been served from the cache',
      );
    });

    test('caches each parent separately', () async {
      await repository.cities('IN-TN');
      expect(cache.writes, ['location_cache_cities_IN-TN']);
      await repository.cities('IN-KL');
      expect(cache.writes, contains('location_cache_cities_IN-KL'));
    });

    test('does not cache an empty result', () async {
      client = _StubClient({'/reference-data/countries': <dynamic>[]});
      repository = LocationRepository(client, cache: cache);

      expect(await repository.countries(), isEmpty);
      // An empty list is far more likely to be a transient backend problem
      // than a real answer; caching it would strand the member for a week.
      expect(cache.writes, isEmpty);
    });

    test('turns a 4xx into an ApiException rather than an empty list', () async {
      client.status = 404;
      client = _StubClient({
        '/reference-data/states': {'statusCode': 404, 'message': 'Unknown country code "ZZ".'},
      })
        ..status = 404;
      repository = LocationRepository(client, cache: cache);

      await expectLater(
        repository.states('ZZ'),
        throwsA(
          isA<ApiException>().having((e) => e.message, 'message', contains('Unknown country')),
        ),
      );
    });
  });
}
