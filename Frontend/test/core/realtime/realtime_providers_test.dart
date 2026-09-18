import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nenjam_matrimony/core/realtime/realtime_event.dart';
import 'package:nenjam_matrimony/core/realtime/realtime_providers.dart';
import 'package:nenjam_matrimony/core/realtime/realtime_service.dart';
import 'package:nenjam_matrimony/features/authentication/data/models/auth_user.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discover_feed_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discover_profile_page.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/repositories/discover_repository.dart';
import 'package:nenjam_matrimony/features/discover/presentation/providers/discover_providers.dart';
import 'package:nenjam_matrimony/features/matches/presentation/providers/reel_feed_provider.dart';
import 'package:nenjam_matrimony/features/notifications/domain/repositories/notification_repository.dart';
import 'package:nenjam_matrimony/features/notifications/presentation/providers/notification_providers.dart';
import 'package:nenjam_matrimony/features/search/domain/repositories/search_repository.dart';
import 'package:nenjam_matrimony/features/search/presentation/providers/search_providers.dart';
import 'package:nenjam_matrimony/features/shortlist/domain/repositories/shortlist_repository.dart';
import 'package:nenjam_matrimony/features/shortlist/presentation/providers/shortlist_provider.dart';

void main() {
  group('RealtimeEvent.feedInvalidate — enum wiring', () {
    test('wire name matches the backend exactly', () {
      expect(RealtimeEvent.feedInvalidate.wireName, 'feed.invalidate');
    });

    test('is included in wireNames — this is what makes RealtimeService '
        'register a socket.on() listener for it', () {
      expect(RealtimeEvent.wireNames, contains('feed.invalidate'));
    });

    test('fromWire round-trips', () {
      expect(RealtimeEvent.fromWire('feed.invalidate'), RealtimeEvent.feedInvalidate);
    });

    test('chat events are untouched by this addition', () {
      // Regression guard: feedInvalidate belongs on RealtimeEvent, never on
      // ChatRealtimeEvent — chat's wire names must be exactly what they were.
      expect(ChatRealtimeEvent.wireNames, [
        'chat.message',
        'chat.read',
        'chat.delivered',
        'chat.typing',
        'chat.messageEdited',
        'chat.messageDeleted',
        'chat.presence',
      ]);
      expect(ChatRealtimeEvent.fromWire('feed.invalidate'), isNull);
    });
  });

  group('realtimeSyncProvider — feed.invalidate wiring', () {
    test('invalidates Discover, Matches reel and Search on receipt', () async {
      final discover = _RecordingDiscoverRepository();
      final search = _RecordingSearchRepository();
      final service = _FakeRealtimeService();
      final container = _container(
        service: service,
        discover: discover,
        search: search,
      );

      // Keep each provider alive and already-fetched, exactly as a real
      // screen watching it would — invalidate only re-fetches something
      // that's actively watched.
      container.listen(discoverFeedProvider, (_, __) {});
      container.listen(reelFeedProvider, (_, __) {});
      container.listen(searchResultsProvider, (_, __) {});
      container.read(realtimeSyncProvider);
      await container.read(discoverFeedProvider.future);
      await container.read(reelFeedProvider.future);
      // Search starts idle (no query) — give it a query so it actually
      // issues a request search.invalidate can meaningfully re-trigger.
      container.read(searchQueryProvider.notifier).state = 'engineer';
      await container.read(searchResultsProvider.future);

      expect(discover.feedCalls, 1);
      expect(discover.pageCalls, 1);
      expect(search.calls, hasLength(1));

      service.emitEvent(RealtimeEvent.feedInvalidate);
      await Future<void>.delayed(Duration.zero);
      await container.read(discoverFeedProvider.future);
      await container.read(reelFeedProvider.future);
      await container.read(searchResultsProvider.future);

      expect(discover.feedCalls, 2);
      expect(discover.pageCalls, 2);
      expect(search.calls, hasLength(2));
    });

    test('preserves the current search query and filters — never clears '
        'the search field', () async {
      final search = _RecordingSearchRepository();
      final service = _FakeRealtimeService();
      final container = _container(service: service, search: search);
      container.listen(searchResultsProvider, (_, __) {});
      container.read(realtimeSyncProvider);

      container.read(searchQueryProvider.notifier).state = 'engineer';
      await container.read(searchResultsProvider.future);

      service.emitEvent(RealtimeEvent.feedInvalidate);
      await Future<void>.delayed(Duration.zero);
      await container.read(searchResultsProvider.future);

      // The query text itself is untouched — feed.invalidate only refetches
      // through the existing request, it never resets searchQueryProvider.
      expect(container.read(searchQueryProvider), 'engineer');
      expect(search.calls.every((c) => c.query == 'engineer'), isTrue);
    });

    test('an idle Search (no query, no filters) issues no request on '
        'feed.invalidate', () async {
      final search = _RecordingSearchRepository();
      final service = _FakeRealtimeService();
      final container = _container(service: service, search: search);
      container.listen(searchResultsProvider, (_, __) {});
      container.read(realtimeSyncProvider);
      await container.read(searchResultsProvider.future);
      expect(search.calls, isEmpty);

      service.emitEvent(RealtimeEvent.feedInvalidate);
      await Future<void>.delayed(Duration.zero);
      await container.read(searchResultsProvider.future);

      expect(search.calls, isEmpty);
    });

    test('an autoDispose provider nobody is watching stays untouched — no '
        'crash, no wasted request', () async {
      // reelFeedProvider/searchResultsProvider are .autoDispose: with no
      // active watcher (the Matches/Search screen isn't open) Riverpod has
      // already disposed them, so invalidating is a true no-op — nothing to
      // recompute. (discoverFeedProvider is a plain, non-autoDispose
      // FutureProvider, so it behaves differently: see the next test.)
      final search = _RecordingSearchRepository();
      final service = _FakeRealtimeService();
      final container = _container(service: service, search: search);
      container.read(realtimeSyncProvider);
      // Deliberately not listened to — nothing on screen reads Search.

      service.emitEvent(RealtimeEvent.feedInvalidate);
      await Future<void>.delayed(Duration.zero);

      expect(search.calls, isEmpty);
    });

    test('discoverFeedProvider (non-autoDispose) recomputes even while '
        'unwatched — harmless, since nothing renders it in that state',
        () async {
      final discover = _RecordingDiscoverRepository();
      final service = _FakeRealtimeService();
      final container = _container(service: service, discover: discover);
      container.read(realtimeSyncProvider);

      service.emitEvent(RealtimeEvent.feedInvalidate);
      await Future<void>.delayed(Duration.zero);

      // Unlike the autoDispose providers above, a plain FutureProvider has
      // no "nobody's listening" state to preserve — invalidating always
      // recomputes it. This costs one background REST call with no visible
      // effect (nothing is watching it to render), not a bug.
      expect(discover.feedCalls, 1);
    });

    test('repeated invalidations do not stack into a runaway number of '
        'requests', () async {
      final discover = _RecordingDiscoverRepository();
      final service = _FakeRealtimeService();
      final container = _container(service: service, discover: discover);
      container.listen(discoverFeedProvider, (_, __) {});
      container.read(realtimeSyncProvider);
      await container.read(discoverFeedProvider.future);
      expect(discover.feedCalls, 1);

      // Three invalidations fired back-to-back, synchronously — the
      // pathological case Step 8 warns about.
      service.emitEvent(RealtimeEvent.feedInvalidate);
      service.emitEvent(RealtimeEvent.feedInvalidate);
      service.emitEvent(RealtimeEvent.feedInvalidate);
      await Future<void>.delayed(Duration.zero);
      await container.read(discoverFeedProvider.future);

      // Riverpod coalesces same-provider invalidates that land before the
      // previous rebuild is read; the exact count is bounded and small —
      // never unbounded, and never so few that no refresh happened at all.
      expect(discover.feedCalls, inInclusiveRange(2, 4));
      expect(discover.feedCalls, lessThan(10),
          reason: 'three invalidations must never fan out into a runaway '
              'request storm');
    });

    test('a listener survives multiple events over its lifetime (proxy for '
        '"reconnect restores the listener" — the same subscription just '
        'keeps receiving)', () async {
      final discover = _RecordingDiscoverRepository();
      final service = _FakeRealtimeService();
      final container = _container(service: service, discover: discover);
      container.listen(discoverFeedProvider, (_, __) {});
      container.read(realtimeSyncProvider);
      await container.read(discoverFeedProvider.future);

      for (var i = 0; i < 3; i++) {
        service.emitEvent(RealtimeEvent.feedInvalidate);
        await Future<void>.delayed(Duration.zero);
        await container.read(discoverFeedProvider.future);
      }

      expect(discover.feedCalls, greaterThanOrEqualTo(4),
          reason: 'the 1 initial fetch plus at least 3 more — the '
              'subscription must not go silent after its first event');
    });

    test('reading realtimeSyncProvider more than once does not register a '
        'second listener — one event, one round of invalidation', () async {
      final discover = _RecordingDiscoverRepository();
      final service = _FakeRealtimeService();
      final container = _container(service: service, discover: discover);
      container.listen(discoverFeedProvider, (_, __) {});
      // Read twice, as two different screens watching the same app-root
      // provider would.
      container.read(realtimeSyncProvider);
      container.read(realtimeSyncProvider);
      await container.read(discoverFeedProvider.future);
      expect(discover.feedCalls, 1);

      service.emitEvent(RealtimeEvent.feedInvalidate);
      await Future<void>.delayed(Duration.zero);
      await container.read(discoverFeedProvider.future);

      // Exactly one extra fetch — not two, which a duplicate `.listen()`
      // registration would cause.
      expect(discover.feedCalls, 2);
    });

    test('sign-out disconnects the realtime service (existing cleanup path, '
        'unaffected by this change)', () async {
      final service = _FakeRealtimeService();
      final container = _container(service: service);
      container.read(realtimeSyncProvider);
      // ref.listen's fireImmediately fires once on setup with the initial
      // (signed-out) value — one disconnect() before anything else happens.
      await Future<void>.delayed(Duration.zero);
      expect(service.disconnectCalls, 1);
      expect(service.connectCalls, 0);

      container.read(_authOverrideProvider.notifier).state =
          const AuthUser(uid: 'u1');
      await Future<void>.delayed(Duration.zero);
      expect(service.connectCalls, 1);

      container.read(_authOverrideProvider.notifier).state = null;
      await Future<void>.delayed(Duration.zero);

      // The initial fireImmediately disconnect, plus this explicit sign-out.
      expect(service.disconnectCalls, 2);
    });

    test('other existing RealtimeEvent cases are unaffected by the new '
        'switch branch', () async {
      final shortlist = _RecordingShortlistRepository();
      final notifications = _RecordingNotificationRepository();
      final service = _FakeRealtimeService();
      final container = _container(
        service: service,
        shortlist: shortlist,
        notifications: notifications,
      );
      container.listen(shortlistNotifierProvider, (_, __) {});
      container.listen(notificationsNotifierProvider, (_, __) {});
      container.read(realtimeSyncProvider);
      await container.read(shortlistNotifierProvider.future);
      await container.read(notificationsNotifierProvider.future);
      expect(shortlist.getCalls, 1);
      expect(notifications.getCalls, 1);

      service.emitEvent(RealtimeEvent.shortlistCreated);
      await Future<void>.delayed(Duration.zero);
      await container.read(shortlistNotifierProvider.future);
      await container.read(notificationsNotifierProvider.future);

      expect(shortlist.getCalls, 2);
      expect(notifications.getCalls, 2,
          reason: 'shortlistCreated invalidates notifications too, same as '
              'before this change');
    });
  });
}

// ─── Fakes ──────────────────────────────────────────────────────────────

/// A controllable stand-in for [RealtimeService]. Overrides every member
/// [realtimeSyncProvider] touches; nothing here opens a real socket.
class _FakeRealtimeService implements RealtimeService {
  final _controller = _BroadcastRecorder<RealtimeEvent>();
  int connectCalls = 0;
  int disconnectCalls = 0;

  /// Not part of [RealtimeService]'s interface — the test's own way to push
  /// an event through, standing in for a real inbound socket frame.
  void emitEvent(RealtimeEvent event) => _controller.add(event);

  @override
  Stream<RealtimeEvent> get events => _controller.stream;

  @override
  Future<void> connect() async {
    connectCalls++;
  }

  @override
  void disconnect() {
    disconnectCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Thin wrapper so `_FakeRealtimeService` doesn't need a real
/// StreamController import juggling act — just records/replays.
class _BroadcastRecorder<T> {
  final _controller = StreamController<T>.broadcast();
  Stream<T> get stream => _controller.stream;
  void add(T value) => _controller.add(value);
}

class _RecordingDiscoverRepository implements DiscoverRepository {
  int feedCalls = 0;
  int pageCalls = 0;

  @override
  Future<DiscoverFeedEntity> getDiscoverFeed() async {
    feedCalls++;
    return const DiscoverFeedEntity(
      stories: [],
      profileCompletionPercent: 0,
      aiRecommended: [],
      recentlyJoined: [],
      verifiedProfiles: [],
      nearYou: [],
      premiumMembers: [],
    );
  }

  @override
  Future<DiscoverProfilePage> getDiscoverProfilesPage({
    int page = 1,
    int limit = 20,
  }) async {
    pageCalls++;
    return const DiscoverProfilePage(items: [], page: 1, hasMore: false);
  }
}

class _RecordingSearchRepository implements SearchRepository {
  final List<({String query, int page})> calls = [];

  @override
  Future<SearchResultPage> search({
    required String query,
    int page = 1,
    int limit = 20,
  }) async {
    calls.add((query: query, page: page));
    return SearchResultPage(items: const [], page: page, limit: limit, total: 0, hasMore: false);
  }
}

class _RecordingShortlistRepository implements ShortlistRepository {
  int getCalls = 0;

  @override
  Future<List<DiscoveryProfileEntity>> getShortlisted({
    int page = 1,
    int limit = 20,
  }) async {
    getCalls++;
    return const [];
  }

  @override
  Future<void> add(DiscoveryProfileEntity profile) async {}

  @override
  Future<void> remove(String profileId) async {}
}

class _RecordingNotificationRepository implements NotificationRepository {
  int getCalls = 0;

  @override
  Future<NotificationResultPage> getNotifications({int page = 1, int limit = 20}) async {
    getCalls++;
    return const NotificationResultPage(items: [], page: 1, limit: 20, total: 0, hasMore: false);
  }

  @override
  Future<int> getUnreadCount() async => 0;

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> markAllRead() async {}

  @override
  Future<void> registerDevice({required String fcmToken, required String platform}) async {}

  @override
  Future<void> unregisterDevice(String fcmToken) async {}
}

/// Lets tests drive `currentAuthUserProvider`'s value without touching
/// Firebase — `currentAuthUserProvider` is overridden to forward this.
final _authOverrideProvider = StateProvider<AuthUser?>((ref) => null);

ProviderContainer _container({
  required _FakeRealtimeService service,
  DiscoverRepository? discover,
  SearchRepository? search,
  ShortlistRepository? shortlist,
  NotificationRepository? notifications,
}) {
  final container = ProviderContainer(
    overrides: [
      realtimeServiceProvider.overrideWithValue(service),
      currentAuthUserProvider.overrideWith((ref) => ref.watch(_authOverrideProvider)),
      if (discover != null) discoverRepositoryProvider.overrideWithValue(discover),
      if (search != null) searchRepositoryProvider.overrideWithValue(search),
      if (shortlist != null) shortlistRepositoryProvider.overrideWithValue(shortlist),
      if (notifications != null)
        notificationRepositoryProvider.overrideWithValue(notifications),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
