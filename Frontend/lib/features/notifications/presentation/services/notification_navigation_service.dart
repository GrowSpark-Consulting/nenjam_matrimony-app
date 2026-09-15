import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/router/profile_navigation.dart';
import '../../../../core/router/route_names.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../../discover/presentation/providers/discover_providers.dart';
import '../../../inbox/domain/entities/conversation_entity.dart';
import '../../../inbox/presentation/providers/inbox_providers.dart';
import '../../../matches/presentation/providers/matches_providers.dart';
import '../../domain/entities/notification_deep_link.dart';

/// How long after navigating a destination an identical tap is dropped.
///
/// Backstop for rapid double taps on the same tray notification. Beyond this
/// window a repeat tap is instead caught by the already-at-destination check
/// in [_goTo] / [_openChat], so "tapping the same notification twice" never
/// stacks screens regardless of timing.
const Duration _duplicateTapWindow = Duration(seconds: 3);

/// How long a given FCM delivery stays recognised as already-handled.
///
/// Exists for one specific case: FCM can deliver the *same* launch tap
/// through both `onMessageOpenedApp` and `getInitialMessage()`, back to back
/// during startup. Both carry the same `messageId`, so remembering the last
/// one for a few seconds collapses them into a single navigation. Kept short
/// and single-slot so it can never suppress a legitimate later tap or grow
/// without bound.
const Duration _deliveryDedupeWindow = Duration(seconds: 10);

/// The single place a notification tap becomes a navigation, for all four
/// entry points:
///
///   1. `FirebaseMessaging.onMessageOpenedApp` — tap while backgrounded
///   2. `FirebaseMessaging.getInitialMessage()` — tap that cold-started the
///      app from terminated
///   3. `flutter_local_notifications` — tap on a notification this app
///      rendered itself (foreground pushes), including the cold-start
///      variant via `getNotificationAppLaunchDetails`
///   4. The in-app Notification Center list
///
/// All four call [handle] with the same normalised map, so a destination is
/// defined once and can never drift between "tapped from the tray" and
/// "tapped in the list".
///
/// Navigation goes through GoRouter named routes, never [Navigator]. A tap
/// can arrive before there is any widget tree to navigate (cold start) or
/// while Splash is still deciding where to send the user, so links that
/// arrive too early are parked in [_pending] and replayed the moment the app
/// settles on a real screen (see [_flushPending]).
///
/// ## Fallbacks
///
/// A tap always lands somewhere. Payload problems degrade rather than drop:
///
/// | Problem                                     | Lands on           |
/// |---------------------------------------------|--------------------|
/// | Unknown/missing `type`                      | `/notifications`   |
/// | Chat with no `conversationId` or `senderId` | `/messages`        |
/// | Chat whose conversation can't be resolved   | `/messages`        |
/// | Shortlist with no `userId`                  | `/shortlisted`     |
/// | Shortlister not loaded on this device       | `/shortlisted`     |
/// | Profile-view with no `userId`               | `/profile-viewers` |
///
/// Profile-view never needs its `userId`: the viewers list names every
/// viewer itself, so that type has no failure mode to fall back from.
class NotificationNavigationService {
  /// [routerResolver] defaults to the app's real router. Tests inject their
  /// own so the service can be driven against a throwaway route table
  /// instead of the whole app, and can shrink the dedupe windows to isolate
  /// the already-at-destination guard from the time-based one.
  NotificationNavigationService(
    this._ref, {
    GoRouter? Function()? routerResolver,
    Duration duplicateTapWindow = _duplicateTapWindow,
    Duration deliveryDedupeWindow = _deliveryDedupeWindow,
  })  : _routerResolver = routerResolver ?? (() => appRouterOrNull),
        _duplicateTapWindowOf = duplicateTapWindow,
        _deliveryDedupeWindowOf = deliveryDedupeWindow {
    _attachRouterListener();
  }

  final Ref _ref;
  final GoRouter? Function() _routerResolver;
  final Duration _duplicateTapWindowOf;
  final Duration _deliveryDedupeWindowOf;

  GoRouter? get _router => _routerResolver();

  /// Set once the router exists; used to drop the listener on dispose.
  GoRouter? _observedRouter;

  /// A link that arrived before the app was ready to show it (no router yet,
  /// or still on Splash / an auth screen). Replaced rather than queued — if
  /// several notifications are tapped before the app is up, the most recent
  /// one is the one the user actually chose.
  NotificationDeepLink? _pending;

  /// Monotonic tap counter. Every [handle] claims the next value; an
  /// in-flight [_navigate] that has to await (resolving a conversation)
  /// re-checks it after every suspension point and abandons itself if a
  /// newer tap has arrived. This is what guarantees that tapping several
  /// notifications quickly opens only the latest target instead of racing
  /// two navigations to completion.
  int _sequence = 0;

  /// Destination of the last navigation performed, with its timestamp.
  String? _lastKey;
  DateTime? _lastAt;

  /// The last FCM delivery acted on — see [_deliveryDedupeWindow].
  String? _lastDeliveryId;
  DateTime? _lastDeliveryAt;

  bool _disposed = false;

  /// Handles a raw notification payload.
  ///
  /// Returns `true` when this tap has a destination (navigated now, or
  /// parked for replay), `false` when there is nothing to do — an unroutable
  /// payload while the Notification Center is already open. The in-app list
  /// uses that to show its "coming soon" notice instead of appearing dead.
  bool handle(Map<String, dynamic> data) {
    final link = NotificationDeepLink.fromData(data);
    final issue = link.issue;
    _log('tap $link${issue == null ? '' : ' issue=${issue.name}'}');

    if (_isDuplicateDelivery(link)) {
      _log('drop: delivery ${link.deliveryId} already handled');
      return true;
    }

    // The only genuinely nothing-to-do case: the fallback for an unroutable
    // payload is the screen already on display.
    if (issue == NotificationPayloadIssue.unknownType &&
        _currentLocation == RouteNames.notifications) {
      _log('drop: unknown type and already at ${RouteNames.notifications}');
      return false;
    }

    final sequence = ++_sequence;

    if (!_isReadyToNavigate) {
      _log('park: app not ready (location=$_currentLocation)');
      _pending = link;
      return true;
    }

    unawaited(_navigate(link, sequence));
    return true;
  }

  // ── Readiness / replay ──────────────────────────────────────────────

  /// Whether the app is showing a screen a deep link may replace.
  ///
  /// False while the router doesn't exist yet, while Splash is still running
  /// (`SplashPage` finishes with its own `context.go(...)`, which would
  /// immediately wipe out anything pushed before it), and on any public
  /// route — a signed-out user tapping a stale notification must land on
  /// Login, which GoRouter's own `redirect` already enforces; parking the
  /// link means it opens once they're actually signed in.
  bool get _isReadyToNavigate {
    final location = _currentLocation;
    if (location == null) return false;
    return !RouteNames.publicRoutes.contains(location);
  }

  void _attachRouterListener() {
    // The router is built by main.dart's State, which may not have run yet
    // when this provider is first read. Retry on the next frame until it
    // exists; once attached, every route change is a chance to replay a
    // parked link.
    final router = _router;
    if (router == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed) return;
        _attachRouterListener();
      });
      return;
    }
    _observedRouter = router;
    router.routerDelegate.addListener(_flushPending);
    // A link may already be parked from before the router existed.
    _flushPending();
  }

  void _flushPending() {
    final link = _pending;
    if (link == null || !_isReadyToNavigate) return;
    // Cleared before navigating — [_navigate] changes the location, which
    // re-enters this listener.
    _pending = null;
    _log('replay parked $link');
    unawaited(_navigate(link, ++_sequence));
  }

  void dispose() {
    _disposed = true;
    _observedRouter?.routerDelegate.removeListener(_flushPending);
    _observedRouter = null;
  }

  // ── Navigation ──────────────────────────────────────────────────────

  Future<void> _navigate(NotificationDeepLink link, int sequence) async {
    final router = _router;
    if (router == null) return;

    if (_isDuplicateDestination(link)) {
      _log('drop: ${link.dedupeKey} navigated within $_duplicateTapWindowOf');
      return;
    }
    _lastKey = link.dedupeKey;
    _lastAt = DateTime.now();
    if (link.deliveryId != null) {
      _lastDeliveryId = link.deliveryId;
      _lastDeliveryAt = DateTime.now();
    }

    switch (link.kind) {
      case NotificationDeepLinkKind.chat:
        await _openChat(router, link, sequence);
      case NotificationDeepLinkKind.interestReceived:
      case NotificationDeepLinkKind.interestDeclined:
        _ref.read(inboxTabProvider.notifier).state = InboxTab.interestsReceived;
        _goTo(router, RouteNames.messagesName, RouteNames.messages);
      case NotificationDeepLinkKind.interestAccepted:
        _ref.read(matchCategoryProvider.notifier).state =
            MatchCategory.myMatches;
        _goTo(router, RouteNames.matchesName, RouteNames.matches);
      case NotificationDeepLinkKind.shortlistAdded:
        // Shortlisted is this type's own home, so it's the fallback for both
        // "no userId at all" and "valid userId, not loaded on this device" —
        // both mean "we can't show you that member, here is the list".
        await _openMemberProfile(
          router,
          link,
          sequence,
          fallbackRouteName: RouteNames.shortlistedName,
          fallbackRoutePath: RouteNames.shortlisted,
        );
      case NotificationDeepLinkKind.profileView:
        // The viewers list is the destination outright — it already names
        // and shows every viewer, so there is nothing a single profile
        // detail would add, and no id to get wrong.
        //
        // Notification Center first, then the viewers list on top, so Back
        // lands on Notifications the way a tapped Instagram/WhatsApp
        // notification does — rather than dropping the member out of the
        // app from a stack of one. Same go-then-push shape as
        // subscriptionExpired below.
        if (_currentLocation == RouteNames.profileViewers) {
          _log('skip: already at ${RouteNames.profileViewers}');
          return;
        }
        //
        // Only when Notifications is not already on screen. `go` to the
        // location you are already at is not a no-op: it REBUILDS the stack
        // as that route alone, discarding whatever the member pushed
        // Notifications from. Tapping a PROFILE_VIEW row inside the
        // Notification Center — which routes through here, exactly as a
        // system-tray tap does — therefore threw away the Discover route
        // underneath, and popping the viewers list landed on a Notifications
        // page with nothing beneath it and so no back arrow at all.
        final atNotifications = _currentLocation == RouteNames.notifications;
        if (!atNotifications) {
          router.goNamed(RouteNames.notificationsName);
          await _branchSwitchApplied();
          if (_isStale(sequence)) return;
        }
        router.pushNamed(
          RouteNames.profileViewersName,
          queryParameters: const {
            RouteNames.openedFromNotificationParam: 'true',
          },
        );
        _log('${atNotifications ? 'already at ${RouteNames.notifications}' : 'go ${RouteNames.notifications}'} '
            '+ push ${RouteNames.profileViewers}');
      case NotificationDeepLinkKind.verificationApproved:
        _goTo(router, RouteNames.verificationName, RouteNames.verification);
      case NotificationDeepLinkKind.subscriptionExpiring:
        _goTo(router, RouteNames.premiumName, RouteNames.premium);
      case NotificationDeepLinkKind.subscriptionExpired:
        // Plans first, then the renewal checkout on top — so Back from the
        // checkout lands on Premium rather than dumping the member out of
        // the app.
        if (_currentLocation == RouteNames.subscription) {
          _log('skip: already at ${RouteNames.subscription}');
          return;
        }
        router.goNamed(RouteNames.premiumName);
        await _branchSwitchApplied();
        if (_isStale(sequence)) return;
        router.pushNamed(RouteNames.subscriptionName);
        _log('go ${RouteNames.premium} + push ${RouteNames.subscription}');
      case NotificationDeepLinkKind.dailyRecommendations:
        _goTo(router, RouteNames.discoverName, RouteNames.discover);
      case NotificationDeepLinkKind.newMatch:
        _goTo(router, RouteNames.matchesName, RouteNames.matches);
      case NotificationDeepLinkKind.notificationCenter:
        // Unknown type — the documented safe fallback.
        _goTo(router, RouteNames.notificationsName, RouteNames.notifications);
      case NotificationDeepLinkKind.profileCompletion:
        _goTo(
          router,
          RouteNames.profileCompletionName,
          RouteNames.profileCompletion,
        );
    }
  }

  /// Navigates to [path] unless it's already the current location.
  void _goTo(GoRouter router, String name, String path) {
    if (_currentLocation == path) {
      _log('skip: already at $path');
      return;
    }
    _log('go $path');
    router.goNamed(name);
  }

  /// Inbox → the conversation with the sender.
  ///
  /// The conversation is resolved *before* any navigation so there is no
  /// async gap between switching to the Messages branch and pushing the
  /// thread on top of it. An unresolvable conversation (a brand-new thread
  /// this device hasn't fetched, an offline cold start, or a payload with no
  /// usable id at all) still lands the member on the Inbox.
  Future<void> _openChat(
    GoRouter router,
    NotificationDeepLink link,
    int sequence,
  ) async {
    void toInbox() {
      _ref.read(inboxTabProvider.notifier).state = InboxTab.messages;
      _goTo(router, RouteNames.messagesName, RouteNames.messages);
    }

    if (link.issue == NotificationPayloadIssue.missingConversationId) {
      _log('fallback: chat payload has no conversationId/senderId');
      toInbox();
      return;
    }

    // Already reading this exact thread — a repeat tap must not push a
    // second copy of it.
    if (link.conversationId != null &&
        _currentLocation == RouteNames.chatDetail &&
        _ref.read(chatActiveThreadsProvider).contains(link.conversationId)) {
      _log('skip: conversation ${link.conversationId} already open');
      return;
    }

    final conversation = await _resolveConversation(link);
    if (_isStale(sequence)) return;

    if (conversation == null) {
      _log('fallback: conversation ${link.conversationId} not resolvable');
      toInbox();
      return;
    }

    _ref.read(inboxTabProvider.notifier).state = InboxTab.messages;
    router.goNamed(RouteNames.messagesName);
    await _branchSwitchApplied();
    if (_isStale(sequence)) return;
    router.pushNamed(RouteNames.chatDetailName, extra: conversation);
    _log('go ${RouteNames.messages} + push chat ${conversation.id}');
  }

  /// Waits for a preceding [GoRouter.goNamed] to actually take effect.
  ///
  /// `go()` is delivered through the route-information provider and applied
  /// asynchronously, whereas `push()` mutates the current match list right
  /// away. Issuing both in one turn therefore loses the push: the `go`'s
  /// update lands afterwards and replaces the whole stack — the pushed page
  /// silently never appears. Letting a frame complete in between makes the
  /// pushed page land on top of the branch that was just switched to, every
  /// time. (`endOfFrame` schedules a frame itself if none is pending, so
  /// this can't stall.)
  Future<void> _branchSwitchApplied() => WidgetsBinding.instance.endOfFrame;

  Future<ConversationEntity?> _resolveConversation(
    NotificationDeepLink link,
  ) async {
    ConversationEntity? findIn(List<ConversationEntity> all) {
      for (final c in all) {
        if (link.conversationId != null && c.id == link.conversationId) {
          return c;
        }
      }
      // The push always carries `conversationId`, but matching on the peer
      // covers a payload that only identified the sender.
      for (final c in all) {
        if (link.senderId != null && c.profile.id == link.senderId) return c;
      }
      return null;
    }

    try {
      final loaded = await _ref.read(conversationsNotifierProvider.future);
      final match = findIn(loaded);
      if (match != null) return match;

      // A notification for a conversation that started after this device
      // last fetched the list — refetch once before giving up.
      await _ref.read(conversationsNotifierProvider.notifier).refresh();
      return findIn(_ref.read(conversationsNotifierProvider).valueOrNull ??
          const <ConversationEntity>[]);
    } catch (error) {
      // Offline / backend error — the Inbox itself will surface that; never
      // let it escape into the tap handler.
      _log('conversation lookup failed: $error');
      return null;
    }
  }

  /// Opens the member's profile when this device already has it loaded,
  /// otherwise the notification type's own list screen.
  ///
  /// Resolution is deliberately limited to data already in memory (the
  /// Discover feed and the conversation list): there is no
  /// `GET /profiles/:id` endpoint for another member, so there is nothing to
  /// fetch a stranger's profile with. Both failure modes — no `userId` in
  /// the payload, and a valid `userId` this device has never loaded — land
  /// on [fallbackRoutePath], because from the member's point of view they
  /// are the same thing: "here is the list instead".
  Future<void> _openMemberProfile(
    GoRouter router,
    NotificationDeepLink link,
    int sequence, {
    required String fallbackRouteName,
    required String fallbackRoutePath,
  }) async {
    if (link.issue == NotificationPayloadIssue.missingUserId) {
      _log('fallback: profile payload has no userId');
      _goTo(router, fallbackRouteName, fallbackRoutePath);
      return;
    }

    final profile = _findLoadedProfile(link.userId!);
    if (_isStale(sequence)) return;

    if (profile == null) {
      _log('fallback: profile ${link.userId} not loaded on this device');
      _goTo(router, fallbackRouteName, fallbackRoutePath);
      return;
    }
    _log('push profile ${profile.id}');
    openProfileDetailOnRouter(router, profile);
  }

  DiscoveryProfileEntity? _findLoadedProfile(String userId) {
    final feed = _ref.read(discoverFeedProvider).valueOrNull;
    if (feed != null) {
      for (final section in [
        feed.aiRecommended,
        feed.recentlyJoined,
        feed.verifiedProfiles,
        feed.nearYou,
        feed.premiumMembers,
      ]) {
        for (final profile in section) {
          if (profile.id == userId) return profile;
        }
      }
    }
    final conversations =
        _ref.read(conversationsNotifierProvider).valueOrNull ?? const [];
    for (final c in conversations) {
      if (c.profile.id == userId) return c.profile;
    }
    return null;
  }

  // ── Duplicate suppression ───────────────────────────────────────────

  /// True when a newer tap has arrived since [sequence] was claimed, so this
  /// navigation must abandon itself rather than fight the newer one.
  bool _isStale(int sequence) {
    if (sequence == _sequence) return false;
    _log('abandon tap #$sequence — superseded by #$_sequence');
    return true;
  }

  /// True when this exact FCM delivery was already acted on moments ago —
  /// the `onMessageOpenedApp` + `getInitialMessage()` double-fire.
  bool _isDuplicateDelivery(NotificationDeepLink link) {
    final id = link.deliveryId;
    final at = _lastDeliveryAt;
    if (id == null || at == null || _lastDeliveryId != id) return false;
    return DateTime.now().difference(at) < _deliveryDedupeWindowOf;
  }

  /// True when this exact destination was navigated within
  /// [_duplicateTapWindow].
  bool _isDuplicateDestination(NotificationDeepLink link) {
    if (_lastKey != link.dedupeKey) return false;
    final at = _lastAt;
    return at != null && DateTime.now().difference(at) < _duplicateTapWindowOf;
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  /// Path of the route actually on top.
  ///
  /// Deliberately not `currentConfiguration.uri` — `push()` appends an
  /// imperative match without touching the URI (that's why pushing doesn't
  /// change the address bar on web), so a URI-based check would never see
  /// Chat Detail or the subscription checkout and the
  /// already-at-destination guard would silently never fire for them.
  /// `state.matchedLocation` resolves the deepest match, which is the one
  /// the member is looking at.
  String? get _currentLocation {
    final router = _router;
    if (router == null) return null;
    if (router.routerDelegate.currentConfiguration.isEmpty) return null;
    return router.state.matchedLocation;
  }

  /// Debug builds only — these lines are the difference between "the tap did
  /// nothing" and "the tap was dropped because the thread was already open",
  /// which is otherwise indistinguishable in the field. Compiled out of
  /// release builds by [kDebugMode].
  void _log(String message) {
    if (kDebugMode) debugPrint('[NotificationNav] $message');
  }
}

/// Alive for the app's lifetime — `pushNotificationServiceProvider` reads it
/// to hand FCM its tap callback, and the Notification Center reads it for
/// in-app taps.
final notificationNavigationServiceProvider =
    Provider<NotificationNavigationService>((ref) {
  final service = NotificationNavigationService(ref);
  ref.onDispose(service.dispose);
  return service;
});
