import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_client.dart';
import 'package:nenjam_matrimony/core/network/api_endpoints.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/search/data/repositories/search_repository_impl.dart';

/// Records the path and query parameters of every request and replays a
/// canned response — the same stubbing approach `location_repository_test`
/// uses, so nothing here needs a mocking package.
class _StubClient extends ApiClient {
  _StubClient({this.data, this.status = 200});

  Map<String, dynamic>? data;
  int status;

  final List<String> paths = [];
  final List<Map<String, dynamic>?> queries = [];

  /// Thrown instead of returning, when set — stands in for a timeout or a
  /// dead connection (Dio surfaces both as a DioException).
  DioException? throws;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    paths.add(path);
    queries.add(queryParameters);
    if (throws != null) throw throws!;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: status,
      data: data as T?,
    );
  }
}

/// One profile in the exact shape `ProfileFeedMapper` emits — the backend's
/// `DiscoverProfileDto`. Only the fields `DiscoveryProfileModel.fromJson`
/// treats as required are mandatory here.
Map<String, dynamic> _profile(String id, {int age = 28}) => {
      'id': id,
      'matrimonyId': id.toUpperCase(),
      'name': 'Member $id',
      'age': age,
      'location': 'Chennai, Tamil Nadu',
      'profession': 'Engineer',
      'education': 'B.E.',
      'photoUrls': <String>['https://example.test/$id.jpg'],
    };

Map<String, dynamic> _envelope(
  List<Map<String, dynamic>> items, {
  int page = 1,
  int limit = 20,
  int? total,
  bool hasMore = false,
}) =>
    {
      'items': items,
      'page': page,
      'limit': limit,
      'total': total ?? items.length,
      'hasMore': hasMore,
      'tier': 1,
      'fallbackUsed': false,
      'reason': '',
      'relaxedFilters': <String>[],
    };

void main() {
  group('SearchRepositoryImpl', () {
    test('calls GET /discover/search — not /search', () async {
      final client = _StubClient(data: _envelope([_profile('a')]));

      await SearchRepositoryImpl(client).search(query: 'chennai');

      expect(client.paths, ['/discover/search']);
      expect(ApiEndpoints.discoverSearch, '/discover/search');
    });

    test('sends exactly q, page and limit — the only params the endpoint '
        'reads', () async {
      final client = _StubClient(data: _envelope([]));

      await SearchRepositoryImpl(client)
          .search(query: 'doctor', page: 3, limit: 20);

      expect(client.queries.single, {'q': 'doctor', 'page': 3, 'limit': 20});
    });

    test('trims the query before sending', () async {
      final client = _StubClient(data: _envelope([]));

      await SearchRepositoryImpl(client).search(query: '  doctor  ');

      expect(client.queries.single!['q'], 'doctor');
    });

    test('omits q entirely when the term is blank, so the backend applies no '
        'text predicate', () async {
      final client = _StubClient(data: _envelope([]));

      await SearchRepositoryImpl(client).search(query: '   ');

      expect(client.queries.single!.containsKey('q'), isFalse);
      expect(client.queries.single, {'page': 1, 'limit': 20});
    });

    test('parses the backend envelope into profiles', () async {
      final client = _StubClient(
        data: _envelope([_profile('a', age: 31), _profile('b')]),
      );

      final result = await SearchRepositoryImpl(client).search(query: 'x');

      expect(result.items, hasLength(2));
      expect(result.items.first.id, 'a');
      expect(result.items.first.age, 31);
      expect(result.items.first.name, 'Member a');
      expect(result.items.first.photoUrls, ['https://example.test/a.jpg']);
    });

    test('preserves the backend pagination fields verbatim', () async {
      final client = _StubClient(
        data: _envelope(
          [_profile('a')],
          page: 2,
          limit: 20,
          total: 57,
          hasMore: true,
        ),
      );

      final result = await SearchRepositoryImpl(client).search(query: 'x');

      expect(result.page, 2);
      expect(result.limit, 20);
      expect(result.total, 57);
      expect(result.hasMore, isTrue);
    });

    test('an empty result set is a normal response, not an error', () async {
      final client = _StubClient(data: _envelope([]));

      final result = await SearchRepositoryImpl(client).search(query: 'zzzz');

      expect(result.items, isEmpty);
      expect(result.hasMore, isFalse);
      expect(result.total, 0);
    });

    test('throws ApiException on 401 so the provider can surface it', () async {
      final client = _StubClient(
        status: 401,
        data: {'statusCode': 401, 'message': 'Empty bearer token.'},
      );

      await expectLater(
        SearchRepositoryImpl(client).search(query: 'x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', 'Empty bearer token.'),
        ),
      );
    });

    test('throws ApiException on 429 — the search throttle tier', () async {
      final client = _StubClient(
        status: 429,
        data: {'statusCode': 429, 'message': 'ThrottlerException: Too Many Requests'},
      );

      await expectLater(
        SearchRepositoryImpl(client).search(query: 'x'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 429)),
      );
    });

    test('propagates a connection failure rather than swallowing it', () async {
      final client = _StubClient()
        ..throws = DioException.connectionTimeout(
          timeout: const Duration(seconds: 20),
          requestOptions: RequestOptions(path: ApiEndpoints.discoverSearch),
        );

      await expectLater(
        SearchRepositoryImpl(client).search(query: 'x'),
        throwsA(isA<DioException>()),
      );
    });

    test('tolerates a response missing the optional envelope fields',
        () async {
      final client = _StubClient(data: {
        'items': [_profile('a')],
      });

      final result = await SearchRepositoryImpl(client).search(query: 'x');

      expect(result.items, hasLength(1));
      expect(result.page, 1);
      expect(result.total, 1);
      expect(result.hasMore, isFalse);
    });
  });
}
