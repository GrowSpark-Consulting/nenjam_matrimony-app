import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discover_feed_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discover_profile_page.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/repositories/discover_repository.dart';
import 'package:nenjam_matrimony/features/discover/presentation/providers/discover_providers.dart';
import 'package:nenjam_matrimony/features/matches/presentation/providers/reel_feed_provider.dart';

/// How the Matches reel walks the feed.
///
/// It used to ask for "page 2", and the backend ranks the feed per request and
/// pushes profiles it has just served to the back — so the second request's
/// rows 20-40 were the ORIGINAL rows 40-60, and twenty profiles were never
/// shown to that member at all. The fake below reproduces exactly that
/// behaviour, so a return to offset paging fails these tests rather than
/// silently losing profiles again.
void main() {
  ProviderContainer containerWith(_RankedFeedBackend backend) {
    final container = ProviderContainer(
      overrides: [discoverRepositoryProvider.overrideWithValue(backend)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<ReelFeedState> load(ProviderContainer container) =>
      container.read(reelFeedProvider.future);

  test('the first page asks for no cursor', () async {
    final backend = _RankedFeedBackend(total: 60);
    final container = containerWith(backend);

    final state = await load(container);

    expect(backend.requests, [const _Request(cursor: null, limit: 20)]);
    expect(state.profiles.map((p) => p.id).toList(), backend.ids(0, 20));
    expect(state.cursor, isNotNull);
    expect(state.hasMore, isTrue);
  });

  test('the next page continues from the cursor, losing nobody', () async {
    final backend = _RankedFeedBackend(total: 60);
    final container = containerWith(backend);
    await load(container);

    await container.read(reelFeedProvider.notifier).loadMore();
    final state = container.read(reelFeedProvider).value!;

    // The request carried the cursor the first page returned, not "page 2".
    expect(backend.requests.last.cursor, isNotNull);
    expect(backend.requests.last.cursor, backend.cursorAfter(19));

    // Exactly the first 40 profiles of the ranked order, in order, with
    // nothing skipped and nothing repeated.
    expect(state.profiles.map((p) => p.id).toList(), backend.ids(0, 40));
    expect(state.profiles.map((p) => p.id).toSet(), hasLength(40));
  });

  test('paging to the end walks every profile exactly once', () async {
    final backend = _RankedFeedBackend(total: 55);
    final container = containerWith(backend);
    await load(container);

    while (container.read(reelFeedProvider).value!.hasMore) {
      await container.read(reelFeedProvider.notifier).loadMore();
    }
    final state = container.read(reelFeedProvider).value!;

    expect(state.profiles.map((p) => p.id).toList(), backend.ids(0, 55));
    expect(state.hasMore, isFalse);
    expect(state.cursor, isNull);
  });

  test('stops at the end instead of re-requesting', () async {
    final backend = _RankedFeedBackend(total: 10);
    final container = containerWith(backend);
    final state = await load(container);

    expect(state.hasMore, isFalse);
    await container.read(reelFeedProvider.notifier).loadMore();
    expect(backend.requests, hasLength(1));
  });

  test(
    'a backend that reports more but returns no cursor is treated as exhausted',
    () async {
      // Otherwise the reel would ask for the same first page forever.
      final backend = _RankedFeedBackend(total: 60, withholdCursor: true);
      final container = containerWith(backend);
      final state = await load(container);

      expect(state.hasMore, isFalse);
      await container.read(reelFeedProvider.notifier).loadMore();
      expect(backend.requests, hasLength(1));
    },
  );

  test('a failed page keeps what is loaded and can be retried', () async {
    final backend = _RankedFeedBackend(total: 60);
    final container = containerWith(backend);
    await load(container);

    backend.failNext = true;
    await container.read(reelFeedProvider.notifier).loadMore();
    var state = container.read(reelFeedProvider).value!;
    expect(state.profiles, hasLength(20));
    expect(state.isLoadingMore, isFalse);

    backend.failNext = false;
    await container.read(reelFeedProvider.notifier).loadMore();
    state = container.read(reelFeedProvider).value!;
    expect(state.profiles.map((p) => p.id).toList(), backend.ids(0, 40));
  });
}

class _Request {
  final String? cursor;
  final int limit;
  const _Request({required this.cursor, required this.limit});

  @override
  bool operator ==(Object other) =>
      other is _Request && other.cursor == cursor && other.limit == limit;

  @override
  int get hashCode => Object.hash(cursor, limit);

  @override
  String toString() => 'Request(cursor: $cursor, limit: $limit)';
}

/// Stands in for `GET /discover` as the backend actually behaves.
///
/// One fixed ranked order of [total] profiles. A cursor names the last profile
/// served and the next page starts straight after it — and, like the real
/// feed, an offset-based request would NOT, because already-served profiles
/// are demoted out of the way.
class _RankedFeedBackend implements DiscoverRepository {
  _RankedFeedBackend({required this.total, this.withholdCursor = false});

  final int total;
  final bool withholdCursor;
  bool failNext = false;
  final List<_Request> requests = [];

  List<String> ids(int from, int to) => [
    for (var i = from; i < to && i < total; i++)
      'u${i.toString().padLeft(2, '0')}',
  ];

  String cursorAfter(int index) => 'cursor-after-$index';

  @override
  Future<DiscoverProfilePage> getDiscoverProfilesPage({
    int page = 1,
    int limit = 20,
    String? cursor,
  }) async {
    requests.add(_Request(cursor: cursor, limit: limit));
    if (failNext) throw Exception('network');

    final start = cursor == null
        ? 0
        : int.parse(cursor.substring('cursor-after-'.length)) + 1;
    final end = (start + limit).clamp(0, total);
    final items = [
      for (final id in ids(start, end))
        DiscoveryProfileEntity(
          id: id,
          matrimonyId: id.toUpperCase(),
          name: id,
          age: 28,
          location: 'Chennai, Tamil Nadu',
          profession: 'Engineer',
          education: 'B.E',
          photoUrls: const [],
        ),
    ];
    final more = end < total;
    return DiscoverProfilePage(
      items: items,
      page: page,
      hasMore: more,
      nextCursor: more && !withholdCursor && items.isNotEmpty
          ? cursorAfter(end - 1)
          : null,
    );
  }

  @override
  Future<DiscoverFeedEntity> getDiscoverFeed() async =>
      const DiscoverFeedEntity(
        aiRecommended: [],
        recentlyJoined: [],
        stories: [],
        verifiedProfiles: [],
        nearYou: [],
        premiumMembers: [],
        profileCompletionPercent: 0,
      );
}
