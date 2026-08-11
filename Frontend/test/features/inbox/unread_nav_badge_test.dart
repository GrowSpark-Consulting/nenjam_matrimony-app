import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/widgets/navigation/nav_badge.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/inbox/domain/entities/conversation_entity.dart';
import 'package:nenjam_matrimony/features/inbox/domain/entities/message_entity.dart';
import 'package:nenjam_matrimony/features/inbox/domain/repositories/conversation_repository.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/providers/inbox_providers.dart';

void main() {
  group('unreadMessagesCountProvider', () {
    test('sums unread messages across conversations, not conversations', () async {
      // Three rooms, six messages — the nav badge must say 6, while the
      // Inbox "Messages" tab's own badge still counts the 2 unread threads.
      final container = _containerWith([
        _conversation('a', unreadCount: 4),
        _conversation('b', unreadCount: 2),
        _conversation('c'),
      ]);
      addTearDown(container.dispose);
      await container.read(conversationsNotifierProvider.future);

      expect(container.read(unreadMessagesCountProvider), 6);
      expect(container.read(unreadConversationsCountProvider), 2);
    });

    test('is 0 with nothing unread, and while the list is still loading', () {
      final container = _containerWith([_conversation('a')]);
      addTearDown(container.dispose);

      // Read before awaiting the fetch — the badge must be hidden during the
      // initial load rather than rendering a stale or speculative count.
      expect(container.read(unreadMessagesCountProvider), 0);
    });

    test('excludes archived and blocked conversations', () async {
      final container = _containerWith([
        _conversation('a', unreadCount: 3),
        _conversation('b', unreadCount: 5, isArchived: true),
        _conversation('c', unreadCount: 7, isBlocked: true),
      ]);
      addTearDown(container.dispose);
      await container.read(conversationsNotifierProvider.future);

      expect(container.read(unreadMessagesCountProvider), 3);
    });

    test('counts muted conversations — mute silences, it does not mark read', () async {
      final container = _containerWith([
        _conversation('a', unreadCount: 2, isMuted: true),
      ]);
      addTearDown(container.dispose);
      await container.read(conversationsNotifierProvider.future);

      expect(container.read(unreadMessagesCountProvider), 2);
    });

    test('drops to 0 for a thread marked read', () async {
      final container = _containerWith([_conversation('a', unreadCount: 4)]);
      addTearDown(container.dispose);
      await container.read(conversationsNotifierProvider.future);
      expect(container.read(unreadMessagesCountProvider), 4);

      await container.read(conversationsNotifierProvider.notifier).markRead('a');

      expect(container.read(unreadMessagesCountProvider), 0);
    });

    test('bumps on an incoming socket message for an unopened thread', () async {
      final container = _containerWith([_conversation('a', unreadCount: 1)]);
      addTearDown(container.dispose);
      await container.read(conversationsNotifierProvider.future);

      container.read(conversationsNotifierProvider.notifier).applyIncomingMessage(
            _incoming('a'),
          );

      expect(container.read(unreadMessagesCountProvider), 2);
    });

    test('does not bump while the thread is open', () async {
      final container = _containerWith([_conversation('a', unreadCount: 1)]);
      addTearDown(container.dispose);
      await container.read(conversationsNotifierProvider.future);

      container.read(conversationsNotifierProvider.notifier).applyIncomingMessage(
            _incoming('a'),
            bumpUnread: false,
          );

      expect(container.read(unreadMessagesCountProvider), 1);
    });
  });

  group('ConversationsNotifier.refreshSilently', () {
    test('keeps the current count visible while the re-fetch is in flight', () async {
      final repository = _FakeConversationRepository([
        _conversation('a', unreadCount: 3),
      ]);
      final container = ProviderContainer(
        overrides: [conversationRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(conversationsNotifierProvider.future);

      repository.gate();
      final pending =
          container.read(conversationsNotifierProvider.notifier).refreshSilently();

      // The badge must not blink out mid-refresh (this is what `refresh()`,
      // with its AsyncValue.loading(), would do).
      expect(container.read(unreadMessagesCountProvider), 3);
      repository.release();
      await pending;
      expect(container.read(unreadMessagesCountProvider), 3);
    });

    test('keeps the last known count when the re-fetch fails', () async {
      final repository = _FakeConversationRepository([
        _conversation('a', unreadCount: 3),
      ]);
      final container = ProviderContainer(
        overrides: [conversationRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(conversationsNotifierProvider.future);

      repository.failNext = true;
      await container.read(conversationsNotifierProvider.notifier).refreshSilently();

      expect(container.read(unreadMessagesCountProvider), 3);
    });
  });

  group('NavBadge', () {
    testWidgets('renders the exact count', (tester) async {
      await tester.pumpWidget(_host(const NavBadge(count: 7)));
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('collapses to nothing at zero', (tester) async {
      await tester.pumpWidget(_host(const NavBadge(count: 0)));
      await tester.pumpAndSettle();

      // Still mounted (so the pop-in animation has something to play from),
      // but scaled away to invisible.
      final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scale.scale, 0);
    });

    testWidgets('shows 99+ above the cap', (tester) async {
      await tester.pumpWidget(_host(const NavBadge(count: 100)));
      expect(find.text('99+'), findsOneWidget);

      await tester.pumpWidget(_host(const NavBadge(count: 99)));
      expect(find.text('99'), findsOneWidget);
    });

    testWidgets('is at least 18x18 and never smaller than its content', (tester) async {
      await tester.pumpWidget(_host(const NavBadge(count: 1)));
      final small = tester.getSize(find.byType(NavBadge));
      expect(small.width, greaterThanOrEqualTo(NavBadge.minSize));
      expect(small.height, greaterThanOrEqualTo(NavBadge.minSize));

      await tester.pumpWidget(_host(const NavBadge(count: 100)));
      final wide = tester.getSize(find.byType(NavBadge));
      expect(wide.width, greaterThan(small.width));
      expect(wide.height, small.height);
    });

    testWidgets('does not swallow taps meant for the icon underneath', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          GestureDetector(
            // Opaque so the bare SizedBox below still registers hits — the
            // real nav item is an InkWell over a painted circle. What's under
            // test is only whether the badge blocks the tap.
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(width: 40, height: 40),
                Positioned(top: 0, right: 0, child: NavBadge(count: 3)),
              ],
            ),
          ),
        ),
      );

      // warnIfMissed: the tap deliberately does NOT land on the badge — it
      // passes through to the handler behind it, which is the assertion.
      await tester.tap(find.text('3'), warnIfMissed: false);

      expect(taps, 1);
    });
  });
}

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

ProviderContainer _containerWith(List<ConversationEntity> conversations) =>
    ProviderContainer(
      overrides: [
        conversationRepositoryProvider
            .overrideWithValue(_FakeConversationRepository(conversations)),
      ],
    );

DiscoveryProfileEntity _profile(String id) => DiscoveryProfileEntity(
      id: 'peer-$id',
      matrimonyId: 'NM-$id',
      name: 'Member $id',
      age: 28,
      location: 'Chennai',
      profession: 'Engineer',
      education: 'B.E.',
      photoUrls: const [],
    );

ConversationEntity _conversation(
  String id, {
  int unreadCount = 0,
  bool isArchived = false,
  bool isBlocked = false,
  bool isMuted = false,
}) =>
    ConversationEntity(
      id: id,
      profile: _profile(id),
      lastMessage: 'hi',
      lastMessageAt: DateTime(2026, 1, 1),
      unreadCount: unreadCount,
      isArchived: isArchived,
      isBlocked: isBlocked,
      isMuted: isMuted,
    );

MessageEntity _incoming(String conversationId) => MessageEntity(
      id: 'm-$conversationId-1',
      conversationId: conversationId,
      text: 'hello',
      sentAt: DateTime(2026, 1, 2),
      isMine: false,
    );

/// Only [getConversations] and [markRead] are exercised; everything else on
/// the interface is absent by design — `noSuchMethod` makes an unexpected
/// call fail loudly instead of silently returning a stub value.
class _FakeConversationRepository implements ConversationRepository {
  _FakeConversationRepository(this._conversations);

  final List<ConversationEntity> _conversations;

  /// When non-null, [getConversations] suspends until [release] — used to
  /// observe the badge *during* a silent refresh.
  Completer<void>? _gate;

  bool failNext = false;

  void gate() => _gate = Completer<void>();

  void release() => _gate?.complete();

  @override
  Future<ConversationResultPage> getConversations({
    int page = 1,
    int limit = 20,
  }) async {
    final gate = _gate;
    if (gate != null && !gate.isCompleted) await gate.future;
    if (failNext) {
      failNext = false;
      throw Exception('offline');
    }
    return ConversationResultPage(
      items: _conversations,
      page: 1,
      limit: 20,
      total: _conversations.length,
      hasMore: false,
    );
  }

  @override
  Future<void> markRead(String conversationId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
