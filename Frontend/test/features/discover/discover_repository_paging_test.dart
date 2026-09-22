import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_client.dart';
import 'package:nenjam_matrimony/features/discover/data/repositories/discover_repository_impl.dart';

/// What the reel's page request actually puts on the wire, and what it reads
/// back. `cursor` is the field that stops the feed skipping profiles between
/// pages — see reel_feed_paging_test.dart for the behaviour it protects.
class _StubClient extends ApiClient {
  _StubClient(this.data);

  Map<String, dynamic> data;
  final List<Map<String, dynamic>?> queries = [];

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    queries.add(queryParameters);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: data as T?,
    );
  }
}

void main() {
  Map<String, dynamic> body({
    String? nextCursor,
    bool hasMore = true,
  }) =>
      {
        // The fields DiscoveryProfileModel.fromJson requires, as the feed
        // endpoint sends them.
        'items': [
          {
            'id': 'u1',
            'name': 'Meera',
            'age': 27,
            'location': 'Chennai, Tamil Nadu',
            'profession': 'Engineer',
            'education': 'B.E',
            'photoUrls': <String>[],
            'gender': 'female',
          },
        ],
        'page': 1,
        'limit': 20,
        'hasMore': hasMore,
        if (nextCursor != null) 'nextCursor': nextCursor,
      };

  test('the first page sends no cursor', () async {
    final client = _StubClient(body(nextCursor: 'abc'));
    final repository = DiscoverRepositoryImpl(client);

    await repository.getDiscoverProfilesPage(limit: 20);

    expect(client.queries.single, isNot(contains('cursor')));
    expect(client.queries.single!['limit'], 20);
  });

  test('a later page sends the cursor it was given', () async {
    final client = _StubClient(body(nextCursor: 'def'));
    final repository = DiscoverRepositoryImpl(client);

    await repository.getDiscoverProfilesPage(limit: 20, cursor: 'abc');

    expect(client.queries.single!['cursor'], 'abc');
  });

  test('reads nextCursor back off the response', () async {
    final client = _StubClient(body(nextCursor: 'def'));
    final page = await DiscoverRepositoryImpl(client)
        .getDiscoverProfilesPage(limit: 20);

    expect(page.nextCursor, 'def');
    expect(page.hasMore, isTrue);
    expect(page.items.single.id, 'u1');
  });

  test('a missing or empty nextCursor reads as null, never as ""', () async {
    // An empty string would be sent back as a cursor and restart the feed.
    for (final payload in [
      body(hasMore: false),
      body(nextCursor: '', hasMore: false),
    ]) {
      final page = await DiscoverRepositoryImpl(_StubClient(payload))
          .getDiscoverProfilesPage(limit: 20);
      expect(page.nextCursor, isNull);
    }
  });

  test('an empty cursor argument is not sent', () async {
    final client = _StubClient(body(nextCursor: 'abc'));

    await DiscoverRepositoryImpl(client)
        .getDiscoverProfilesPage(limit: 20, cursor: '');

    expect(client.queries.single, isNot(contains('cursor')));
  });
}
