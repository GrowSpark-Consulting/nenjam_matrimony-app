import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discover_feed_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discover_profile_page.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/repositories/discover_repository.dart';
import 'package:nenjam_matrimony/features/discover/presentation/providers/discover_providers.dart';
import 'package:nenjam_matrimony/features/inbox/domain/entities/conversation_entity.dart';
import 'package:nenjam_matrimony/features/inbox/domain/repositories/conversation_repository.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:nenjam_matrimony/features/matches/presentation/providers/matches_providers.dart';
import 'package:nenjam_matrimony/features/notifications/domain/entities/notification_deep_link.dart';
import 'package:nenjam_matrimony/features/notifications/presentation/services/notification_navigation_service.dart';

/// Tests for the notification deep-link layer.
///
/// Split in two:
///
///   * **Payload parsing** — pure unit tests over
///     [NotificationDeepLink.fromData], covering the wire formats the
///     backend actually sends plus the malformed ones it must survive.
///   * **Navigation** — [NotificationNavigationService] driven against a
///     throwaway GoRouter whose routes use the real [RouteNames] paths but
///     stub pages. The shell/branch structure of the production router is
///     deliberately not reproduced: these assert *which destination* a tap
///     resolves to, which is what the service decides. Rendering those
///     destinations is the router's concern, not this service's.
void main() {
  group('NotificationDeepLink.fromData', () {
    test('parses a chat payload', () {
      final link = NotificationDeepLink.fromData({
        'type': 'chat',
        'conversationId': 'abc123',
        'senderId': 'u1',
      });

      expect(link.kind, NotificationDeepLinkKind.chat);
      expect(link.conversationId, 'abc123');
      expect(link.senderId, 'u1');
      expect(link.issue, isNull);
    });

    test('treats the Prisma enum and lower-case spellings as one type', () {
      for (final raw in ['INTEREST_RECEIVED', 'interest_received']) {
        final link = NotificationDeepLink.fromData({
          'type': raw,
          'interestId': 'i1',
        });
        expect(link.kind, NotificationDeepLinkKind.interestReceived,
            reason: 'failed for "$raw"');
        expect(link.issue, isNull);
      }
    });

    test('falls back to referenceId for the conversation and interest ids', () {
      final chat = NotificationDeepLink.fromData({
        'type': 'NEW_MESSAGE',
        'referenceId': 'r1',
        'actorId': 'u1',
      });
      expect(chat.kind, NotificationDeepLinkKind.chat);
      expect(chat.conversationId, 'r1');
      expect(chat.senderId, 'u1');

      final interest = NotificationDeepLink.fromData({
        'type': 'INTEREST_ACCEPTED',
        'referenceId': 'i1',
      });
      expect(interest.interestId, 'i1');
      expect(interest.issue, isNull);
    });

    test('falls back to actorId for userId on a shortlist payload', () {
      final link = NotificationDeepLink.fromData({
        'type': 'SHORTLIST_ADDED',
        'actorId': 'u2',
      });
      expect(link.kind, NotificationDeepLinkKind.shortlistAdded);
      expect(link.userId, 'u2');
      expect(link.issue, isNull);
    });

    test('flags an unknown type', () {
      final link = NotificationDeepLink.fromData({'type': 'TIME_TRAVEL'});
      expect(link.kind, NotificationDeepLinkKind.notificationCenter);
      expect(link.issue, NotificationPayloadIssue.unknownType);
    });

    test('flags a missing type', () {
      expect(
        NotificationDeepLink.fromData(const {}).issue,
        NotificationPayloadIssue.unknownType,
      );
    });

    test('flags a chat payload with no conversationId and no senderId', () {
      final link = NotificationDeepLink.fromData({'type': 'chat'});
      expect(link.issue, NotificationPayloadIssue.missingConversationId);
    });

    test('accepts a chat payload carrying only senderId', () {
      final link = NotificationDeepLink.fromData({
        'type': 'chat',
        'senderId': 'u1',
      });
      expect(link.issue, isNull);
    });

    test('flags an interest payload with no interestId', () {
      final link = NotificationDeepLink.fromData({
        'type': 'INTEREST_RECEIVED',
      });
      expect(link.issue, NotificationPayloadIssue.missingInterestId);
    });

    test('flags a shortlist payload with no userId', () {
      final link = NotificationDeepLink.fromData({'type': 'SHORTLIST_ADDED'});
      expect(link.issue, NotificationPayloadIssue.missingUserId);
    });

    test('flags a profile-view payload with no userId', () {
      // Diagnostic only — profileView routes to the viewers list regardless.
      final link = NotificationDeepLink.fromData({'type': 'PROFILE_VIEW'});
      expect(link.kind, NotificationDeepLinkKind.profileView);
      expect(link.issue, NotificationPayloadIssue.missingUserId);
    });

    test('ignores empty and whitespace-only ids', () {
      final link = NotificationDeepLink.fromData({
        'type': 'chat',
        'conversationId': '   ',
        'senderId': '',
      });
      expect(link.conversationId, isNull);
      expect(link.issue, NotificationPayloadIssue.missingConversationId);
    });

    test('reads the delivery id from either FCM spelling', () {
      expect(
        NotificationDeepLink.fromData({
          'type': 'chat',
          'conversationId': 'c1',
          'deliveryId': 'm1',
        }).deliveryId,
        'm1',
      );
      expect(
        NotificationDeepLink.fromData({
          'type': 'chat',
          'conversationId': 'c1',
          'google.message_id': 'm2',
        }).deliveryId,
        'm2',
      );
    });

    test('an in-app payload has no delivery id, so stays re-tappable', () {
      final link = NotificationDeepLink.fromData({
        'type': 'NEW_MATCH',
      });
      expect(link.deliveryId, isNull);
    });
  });

  group('NotificationNavigationService', () {
    // ── Routing per notification type ────────────────────────────────

    testWidgets('chat opens the resolved conversation', (tester) async {
      final h = await _pump(tester, conversations: [_conversation('c1', 'u1')]);

      h.service.handle({
        'type': 'chat',
        'conversationId': 'c1',
        'senderId': 'u1',
      });
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.chatDetail);
      expect(h.container.read(inboxTabProvider), InboxTab.messages);
    });

    testWidgets('chat resolves by senderId when only that is present',
        (tester) async {
      final h = await _pump(tester, conversations: [_conversation('c1', 'u1')]);

      h.service.handle({'type': 'chat', 'senderId': 'u1'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.chatDetail);
    });

    testWidgets('chat with an unresolvable conversation falls back to Inbox',
        (tester) async {
      final h = await _pump(tester, conversations: [_conversation('c1', 'u1')]);

      h.service.handle({'type': 'chat', 'conversationId': 'nope'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.messages);
    });

    testWidgets('chat refetches the conversation list once before giving up',
        (tester) async {
      final h = await _pump(tester, conversations: [_conversation('c1', 'u1')]);
      await h.container.read(conversationsNotifierProvider.future);
      final before = h.conversationRepository.fetchCount;

      h.service.handle({'type': 'chat', 'conversationId': 'nope'});
      await tester.pumpAndSettle();

      expect(h.conversationRepository.fetchCount, before + 1);
    });

    testWidgets('chat with no usable id falls back to Inbox', (tester) async {
      final h = await _pump(tester, conversations: [_conversation('c1', 'u1')]);

      h.service.handle({'type': 'chat'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.messages);
      // The invalid payload must not have cost a network round trip.
      expect(h.conversationRepository.fetchCount, 0);
    });

    testWidgets('interest_received opens the Received Interests tab',
        (tester) async {
      final h = await _pump(tester);

      h.service.handle({'type': 'INTEREST_RECEIVED', 'interestId': 'i1'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.messages);
      expect(h.container.read(inboxTabProvider), InboxTab.interestsReceived);
    });

    testWidgets('interest_declined opens the Received Interests tab',
        (tester) async {
      final h = await _pump(tester);

      h.service.handle({'type': 'INTEREST_DECLINED', 'interestId': 'i1'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.messages);
      expect(h.container.read(inboxTabProvider), InboxTab.interestsReceived);
    });

    testWidgets('interest_accepted opens Matches on My Matches',
        (tester) async {
      final h = await _pump(tester);

      h.service.handle({'type': 'INTEREST_ACCEPTED', 'interestId': 'i1'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.matches);
      expect(h.container.read(matchCategoryProvider), MatchCategory.myMatches);
    });

    testWidgets('interest with no interestId still opens the list',
        (tester) async {
      final h = await _pump(tester);

      // A missing interest id is diagnostic only — the destination is a
      // list, so the tap must still work.
      h.service.handle({'type': 'INTEREST_RECEIVED'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.messages);
    });

    testWidgets('shortlist_added opens the shortlister when loaded',
        (tester) async {
      final h = await _pump(tester, feedProfiles: [_profile('u2')]);
      await h.container.read(discoverFeedProvider.future);

      h.service.handle({'type': 'SHORTLIST_ADDED', 'userId': 'u2'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.profileDetail);
    });

    testWidgets('shortlist_added resolves a profile from the conversations too',
        (tester) async {
      final h = await _pump(tester, conversations: [_conversation('c1', 'u2')]);
      await h.container.read(conversationsNotifierProvider.future);

      h.service.handle({'type': 'SHORTLIST_ADDED', 'userId': 'u2'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.profileDetail);
    });

    testWidgets('shortlist_added for an unknown member falls back to '
        'Shortlisted', (tester) async {
      final h = await _pump(tester);

      h.service.handle({'type': 'SHORTLIST_ADDED', 'userId': 'stranger'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.shortlisted);
    });

    testWidgets('shortlist_added with no userId falls back to Shortlisted',
        (tester) async {
      final h = await _pump(tester, initialLocation: RouteNames.matches);

      h.service.handle({'type': 'SHORTLIST_ADDED'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.shortlisted);
    });

    testWidgets('profile_view opens Profile Viewers', (tester) async {
      final h = await _pump(tester);

      h.service.handle({'type': 'PROFILE_VIEW', 'userId': 'u2'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.profileViewers);
    });

    testWidgets('profile_view opens Profile Viewers even with no userId',
        (tester) async {
      // The viewers list names every viewer itself, so the payload's userId
      // is never load-bearing for this type.
      final h = await _pump(tester);

      h.service.handle({'type': 'PROFILE_VIEW'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.profileViewers);
    });

    testWidgets('profile_view does not open a profile even when loaded',
        (tester) async {
      final h = await _pump(tester, feedProfiles: [_profile('u2')]);
      await h.container.read(discoverFeedProvider.future);

      h.service.handle({'type': 'PROFILE_VIEW', 'userId': 'u2'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.profileViewers);
    });

    testWidgets('kyc_approved opens Verification', (tester) async {
      final h = await _pump(tester);

      h.service.handle({'type': 'KYC_APPROVED'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.verification);
    });

    testWidgets('subscription_expiring opens Premium plans', (tester) async {
      final h = await _pump(tester);

      h.service.handle({'type': 'SUBSCRIPTION_EXPIRING'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.premium);
    });

    testWidgets('subscription_expired opens the renewal checkout',
        (tester) async {
      final h = await _pump(tester);

      h.service.handle({'type': 'SUBSCRIPTION_EXPIRED'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.subscription);
    });

    testWidgets('daily_recommendations opens Discover', (tester) async {
      final h = await _pump(tester, initialLocation: RouteNames.matches);

      h.service.handle({'type': 'DAILY_RECOMMENDATIONS'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.discover);
    });

    testWidgets('new_match opens Matches', (tester) async {
      final h = await _pump(tester);

      h.service.handle({'type': 'NEW_MATCH'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.matches);
    });

    testWidgets('an unknown type falls back to the Notification Center',
        (tester) async {
      final h = await _pump(tester);

      expect(h.service.handle({'type': 'SOMETHING_NEW'}), isTrue);
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.notifications);
    });

    // ── Duplicate suppression ────────────────────────────────────────

    testWidgets('the same FCM delivery through both callbacks navigates once',
        (tester) async {
      final h = await _pump(tester);
      const payload = {
        'type': 'NEW_MATCH',
        'deliveryId': 'msg-1',
      };

      // onMessageOpenedApp ...
      h.service.handle(payload);
      await tester.pumpAndSettle();
      expect(h.location, RouteNames.matches);

      // ... then getInitialMessage() for the same launch tap. Navigate back
      // first so a second navigation would be visible if it happened.
      h.router.go(RouteNames.discover);
      await tester.pumpAndSettle();
      h.service.handle(payload);
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.discover);
    });

    testWidgets('a different delivery for the same destination is not '
        'suppressed as a duplicate delivery', (tester) async {
      final h = await _pump(tester, duplicateTapWindow: Duration.zero);

      h.service.handle({'type': 'NEW_MATCH', 'deliveryId': 'msg-1'});
      await tester.pumpAndSettle();
      h.router.go(RouteNames.discover);
      await tester.pumpAndSettle();

      h.service.handle({'type': 'NEW_MATCH', 'deliveryId': 'msg-2'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.matches);
    });

    testWidgets('a repeat tap on the same destination inside the window is '
        'dropped', (tester) async {
      final h = await _pump(tester);

      h.service.handle({'type': 'NEW_MATCH'});
      await tester.pumpAndSettle();
      h.router.go(RouteNames.discover);
      await tester.pumpAndSettle();

      // No deliveryId — this is the destination-based guard alone.
      h.service.handle({'type': 'NEW_MATCH'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.discover);
    });

    // ── "Target already open" ────────────────────────────────────────

    testWidgets('a tap whose destination is the current route is a no-op',
        (tester) async {
      // Time window disabled so only the already-at-destination guard can
      // be responsible for the result.
      final h = await _pump(
        tester,
        initialLocation: RouteNames.matches,
        duplicateTapWindow: Duration.zero,
      );

      h.service.handle({'type': 'NEW_MATCH'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.matches);
      // Nothing was pushed, so there is nothing to pop back to.
      expect(h.router.canPop(), isFalse);
    });

    testWidgets('a tap for the conversation already on screen is a no-op',
        (tester) async {
      final h = await _pump(
        tester,
        conversations: [_conversation('c1', 'u1')],
        duplicateTapWindow: Duration.zero,
      );

      h.service.handle({'type': 'chat', 'conversationId': 'c1'});
      await tester.pumpAndSettle();
      expect(h.location, RouteNames.chatDetail);

      // Chat Detail registers its thread as active while it's mounted; the
      // stub page in this router doesn't, so seed it directly.
      h.container.read(chatActiveThreadsProvider.notifier).add('c1');
      final fetchesBefore = h.conversationRepository.fetchCount;

      h.service.handle({'type': 'chat', 'conversationId': 'c1'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.chatDetail);
      // Short-circuited before any lookup — no second thread pushed.
      expect(h.conversationRepository.fetchCount, fetchesBefore);
    });

    testWidgets('an unroutable tap while the Notification Center is open '
        'reports that it did nothing', (tester) async {
      final h = await _pump(tester, initialLocation: RouteNames.notifications);

      // False is what makes the in-app list show its "coming soon" notice
      // rather than looking broken.
      expect(h.service.handle({'type': 'SOMETHING_NEW'}), isFalse);
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.notifications);
    });

    // ── Latest tap wins ──────────────────────────────────────────────

    testWidgets('tapping several notifications quickly opens only the last',
        (tester) async {
      final h = await _pump(
        tester,
        conversations: [_conversation('c1', 'u1')],
        gateConversations: true,
      );

      // Chat needs to resolve its conversation, so it suspends...
      h.service.handle({'type': 'chat', 'conversationId': 'c1'});
      await tester.pump();

      // ... and a second tap lands while it's still in flight.
      h.service.handle({'type': 'NEW_MATCH'});
      await tester.pumpAndSettle();
      expect(h.location, RouteNames.matches);

      // The chat lookup now completes; its navigation must abandon itself.
      h.conversationRepository.release();
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.matches);
    });

    // ── Readiness / cold start ───────────────────────────────────────

    testWidgets('a tap on Splash is parked and replayed once the app settles',
        (tester) async {
      final h = await _pump(tester, initialLocation: RouteNames.splash);

      expect(h.service.handle({'type': 'NEW_MATCH'}), isTrue);
      await tester.pumpAndSettle();
      // Still on Splash — nothing was allowed to pre-empt it.
      expect(h.location, RouteNames.splash);

      // Splash finishes and sends the user to Discover, exactly as
      // SplashPage does; the parked link then replays.
      h.router.go(RouteNames.discover);
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.matches);
    });

    testWidgets('a tap while signed out is parked, not routed', (tester) async {
      final h = await _pump(tester, initialLocation: RouteNames.login);

      h.service.handle({'type': 'NEW_MATCH'});
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.login);
    });

    testWidgets('only the newest parked link replays', (tester) async {
      final h = await _pump(tester, initialLocation: RouteNames.splash);

      h.service.handle({'type': 'NEW_MATCH'});
      h.service.handle({'type': 'KYC_APPROVED'});
      await tester.pumpAndSettle();

      h.router.go(RouteNames.discover);
      await tester.pumpAndSettle();

      expect(h.location, RouteNames.verification);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────
// Harness
// ─────────────────────────────────────────────────────────────────────────

class _Harness {
  _Harness({
    required this.router,
    required this.container,
    required this.service,
    required this.conversationRepository,
  });

  final GoRouter router;
  final ProviderContainer container;
  final NotificationNavigationService service;
  final _FakeConversationRepository conversationRepository;

  /// The route on top — matches how the service itself reads the current
  /// location, so pushed routes (Chat Detail, the checkout) are visible.
  String? get location {
    final configuration = router.routerDelegate.currentConfiguration;
    return configuration.isEmpty ? null : router.state.matchedLocation;
  }
}

/// Builds a router over the real [RouteNames] paths with stub pages, wires a
/// [NotificationNavigationService] to it, and pumps it.
Future<_Harness> _pump(
  WidgetTester tester, {
  String initialLocation = RouteNames.discover,
  List<ConversationEntity> conversations = const [],
  List<DiscoveryProfileEntity> feedProfiles = const [],
  bool gateConversations = false,
  Duration duplicateTapWindow = const Duration(seconds: 3),
}) async {
  final conversationRepository = _FakeConversationRepository(
    conversations,
    gated: gateConversations,
  );
  final router = _buildRouter(initialLocation);

  final serviceProvider = Provider<NotificationNavigationService>((ref) {
    final service = NotificationNavigationService(
      ref,
      routerResolver: () => router,
      duplicateTapWindow: duplicateTapWindow,
    );
    ref.onDispose(service.dispose);
    return service;
  });

  final container = ProviderContainer(
    overrides: [
      conversationRepositoryProvider.overrideWithValue(conversationRepository),
      discoverRepositoryProvider
          .overrideWithValue(_FakeDiscoverRepository(feedProfiles)),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );

  return _Harness(
    router: router,
    container: container,
    service: container.read(serviceProvider),
    conversationRepository: conversationRepository,
  );
}

GoRouter _buildRouter(String initialLocation) {
  GoRoute stub(String path, String name) => GoRoute(
        path: path,
        name: name,
        builder: (_, __) => Scaffold(body: Text(name)),
      );

  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      stub(RouteNames.splash, RouteNames.splashName),
      stub(RouteNames.login, RouteNames.loginName),
      stub(RouteNames.discover, RouteNames.discoverName),
      stub(RouteNames.matches, RouteNames.matchesName),
      stub(RouteNames.messages, RouteNames.messagesName),
      stub(RouteNames.premium, RouteNames.premiumName),
      stub(RouteNames.subscription, RouteNames.subscriptionName),
      stub(RouteNames.verification, RouteNames.verificationName),
      stub(RouteNames.notifications, RouteNames.notificationsName),
      stub(RouteNames.shortlisted, RouteNames.shortlistedName),
      stub(RouteNames.profileViewers, RouteNames.profileViewersName),
      stub(RouteNames.profileCompletion, RouteNames.profileCompletionName),
      stub(RouteNames.chatDetail, RouteNames.chatDetailName),
      stub(RouteNames.profileDetail, RouteNames.profileDetailName),
    ],
  );
}

DiscoveryProfileEntity _profile(String id) => DiscoveryProfileEntity(
      id: id,
      matrimonyId: 'NM-$id',
      name: 'Member $id',
      age: 28,
      location: 'Chennai',
      profession: 'Engineer',
      education: 'B.E.',
      photoUrls: const [],
    );

ConversationEntity _conversation(String id, String peerId) =>
    ConversationEntity(
      id: id,
      profile: _profile(peerId),
      lastMessage: 'hi',
      lastMessageAt: DateTime(2026, 1, 1),
    );

/// Only [getConversations] is exercised; everything else on the interface is
/// absent by design — `noSuchMethod` makes an unexpected call fail loudly
/// instead of silently returning a stub value.
class _FakeConversationRepository implements ConversationRepository {
  _FakeConversationRepository(this._conversations, {bool gated = false})
      : _gate = gated ? Completer<void>() : null;

  final List<ConversationEntity> _conversations;

  /// When non-null, [getConversations] suspends until [release] — used to
  /// hold a chat tap mid-resolution while a later tap arrives.
  final Completer<void>? _gate;

  int fetchCount = 0;

  void release() => _gate?.complete();

  @override
  Future<ConversationResultPage> getConversations({
    int page = 1,
    int limit = 20,
  }) async {
    fetchCount++;
    if (_gate != null && !_gate.isCompleted) await _gate.future;
    return ConversationResultPage(
      items: _conversations,
      page: 1,
      limit: 20,
      total: _conversations.length,
      hasMore: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeDiscoverRepository implements DiscoverRepository {
  _FakeDiscoverRepository(this._profiles);

  final List<DiscoveryProfileEntity> _profiles;

  @override
  Future<DiscoverFeedEntity> getDiscoverFeed() async => DiscoverFeedEntity(
        stories: const [],
        profileCompletionPercent: 100,
        aiRecommended: _profiles,
        recentlyJoined: const [],
        verifiedProfiles: const [],
        nearYou: const [],
        premiumMembers: const [],
      );

  @override
  Future<DiscoverProfilePage> getDiscoverProfilesPage({
    int page = 1,
    int limit = 20,
  }) async =>
      DiscoverProfilePage(items: _profiles, page: 1, hasMore: false);
}
