import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/realtime/realtime_providers.dart';
import 'package:nenjam_matrimony/core/realtime/realtime_service.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/widgets/cards/chat_card.dart';
import 'package:nenjam_matrimony/core/widgets/feedback/empty_state.dart';
import 'package:nenjam_matrimony/core/widgets/navigation/app_bottom_nav.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/inbox/domain/entities/conversation_entity.dart';
import 'package:nenjam_matrimony/features/inbox/domain/entities/message_entity.dart';
import 'package:nenjam_matrimony/features/inbox/domain/repositories/conversation_repository.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/pages/chat_detail_page.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/pages/inbox_page.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/pages/inbox_shell_page.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/widgets/chat_composer.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/widgets/empty_inbox.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import '../../support/responsive_harness.dart';

/// Chat master-detail.
///
/// Neither route's registration changed: `/messages` is in the Inbox shell
/// branch (here under the real [AppBottomNavShell], so the rail/pill are the
/// production ones) and `/chat-detail/:id` is a ROOT-LEVEL route above the
/// shell. Only what the two route bodies render varies with available width.

const Size _phone = Size(390, 844);
const Size _desktop = Size(1440, 900);

void main() {
  final urlReflectsPushes = GoRouter.optionURLReflectsImperativeAPIs;
  setUpAll(() => GoRouter.optionURLReflectsImperativeAPIs = true);
  tearDownAll(
    () => GoRouter.optionURLReflectsImperativeAPIs = urlReflectsPushes,
  );

  group('topology', () {
    _testWidgets('/messages on a phone is the list alone', (tester) async {
      await _pump(tester, _phone, '/messages');

      expect(find.byType(InboxPage), findsOneWidget);
      expect(find.byType(ChatDetailPage), findsNothing);
      expect(find.byType(NmEmptyState), findsNothing);
    });

    _testWidgets('/messages on desktop is the list plus an empty detail pane', (
      tester,
    ) async {
      await _pump(tester, _desktop, '/messages');

      expect(find.byType(InboxPage), findsOneWidget);
      expect(find.byType(NmEmptyState), findsOneWidget);
      expect(find.byType(ChatDetailPage), findsNothing);
      // The shell rail is still there on /messages.
      expect(find.byKey(const ValueKey('desktop-nav-rail')), findsOneWidget);
    });

    _testWidgets('chat route on a phone is the chat alone, full screen', (
      tester,
    ) async {
      await _pump(tester, _phone, RouteNames.chatDetailPath('c1'));

      expect(find.byType(ChatDetailPage), findsOneWidget);
      expect(find.byType(InboxPage), findsNothing);
    });

    _testWidgets('chat route on desktop is the list beside the chat', (
      tester,
    ) async {
      await _pump(tester, _desktop, RouteNames.chatDetailPath('c1'));

      expect(find.byType(InboxPage), findsOneWidget);
      expect(_openChatId(tester), 'c1');
      expect(_selectedRowIds(tester), ['c1']);
      // Accepted limitation: the chat route sits outside the shell, so a
      // directly-entered chat URL has no navigation rail.
      expect(find.byKey(const ValueKey('desktop-nav-rail')), findsNothing);
    });
  });

  group('composer clearance', () {
    _testWidgets(
      'the chat route is outside the shell, so no bottom pill can cover the '
      'composer',
      (tester) async {
        await _pump(tester, _phone, RouteNames.chatDetailPath('c1'));

        // The floating pill belongs to AppBottomNavShell, which only wraps the
        // four tab branches. The root-level chat route never builds it.
        expect(find.byType(AppBottomNavShell), findsNothing);

        // The composer sits inside the viewport with nothing laid over it.
        final composer = tester.getRect(find.byType(ChatComposer));
        expect(composer.bottom, lessThanOrEqualTo(_phone.height));
        expect(composer.top, greaterThan(0));
      },
    );

    _testWidgets(
      'after a push from /messages the shell is covered, not shown',
      (tester) async {
        final router = await _pump(tester, _phone, '/messages');
        expect(find.byType(AppBottomNavShell), findsOneWidget);

        await tester.tap(find.text('Member c1'));
        await _settle(tester);

        expect(_openChatId(tester), 'c1');
        // The shell is still in the tree beneath the pushed route but offstage:
        // nothing of it is hit-testable or visible over the composer.
        expect(find.byType(AppBottomNavShell), findsNothing);
        expect(
          find.byType(AppBottomNavShell, skipOffstage: false),
          findsOneWidget,
        );
        expect(router.canPop(), isTrue);
      },
    );
  });

  group('phone navigation keeps push semantics', () {
    _testWidgets('open a conversation, then router back returns to /messages', (
      tester,
    ) async {
      final router = await _pump(tester, _phone, '/messages');

      await tester.tap(find.text('Member c1'));
      await _settle(tester);
      expect(_openChatId(tester), 'c1');
      expect(find.byType(InboxPage), findsNothing);

      router.pop();
      await _settle(tester);

      expect(find.byType(ChatDetailPage), findsNothing);
      expect(find.byType(InboxPage), findsOneWidget);
    });

    _testWidgets('the in-app back arrow returns to /messages', (tester) async {
      await _pump(tester, _phone, '/messages');

      await tester.tap(find.text('Member c2'));
      await _settle(tester);
      await tester.tap(find.byType(BackButton));
      await _settle(tester);

      expect(find.byType(ChatDetailPage), findsNothing);
      expect(find.byType(InboxPage), findsOneWidget);
    });

    _testWidgets('Android system back returns to /messages', (tester) async {
      await _pump(tester, _phone, '/messages');

      await tester.tap(find.text('Member c1'));
      await _settle(tester);
      expect(_openChatId(tester), 'c1');

      await tester.binding.handlePopRoute();
      await _settle(tester);

      expect(find.byType(ChatDetailPage), findsNothing);
      expect(find.byType(InboxPage), findsOneWidget);
    });

    _testWidgets('browser back and forward move between the two URLs', (
      tester,
    ) async {
      final router = await _pump(tester, _phone, '/messages');

      await tester.tap(find.text('Member c1'));
      await _settle(tester);
      expect(_openChatId(tester), 'c1');

      // Browser back: the engine reports the previous URL.
      await _browserNavigateTo(tester, '/messages');
      expect(_url(router), '/messages');
      expect(find.byType(ChatDetailPage), findsNothing);
      expect(find.byType(InboxPage), findsOneWidget);

      // Browser forward: no `extra` any more, so the chat resolves by id.
      await _browserNavigateTo(tester, RouteNames.chatDetailPath('c1'));
      expect(_url(router), '/chat-detail/c1');
      expect(_openChatId(tester), 'c1');
    });

    _testWidgets('a cold-start deep link (no extra) resolves by id', (
      tester,
    ) async {
      await _pump(tester, _phone, '/chat-detail/c3?ref=push');

      expect(_openChatId(tester), 'c3');
      expect(find.byType(InboxPage), findsNothing);
    });
  });

  group('desktop selection', () {
    _testWidgets(
      '/messages: picking a row opens it in the pane, URL unchanged',
      (tester) async {
        final router = await _pump(tester, _desktop, '/messages');

        await tester.tap(find.text('Member c1'));
        await _settle(tester);

        expect(_openChatId(tester), 'c1');
        expect(_selectedRowIds(tester), ['c1']);
        // Documented: this selection is local state, not part of the URL.
        expect(_url(router), '/messages');
        expect(find.byType(InboxPage), findsOneWidget);

        await tester.tap(find.text('Member c2'));
        await _settle(tester);
        expect(_openChatId(tester), 'c2');
        expect(_selectedRowIds(tester), ['c2']);
        expect(find.byType(ChatDetailPage), findsOneWidget);
      },
    );

    _testWidgets(
      'chat route: picking rows keeps the URL authoritative and never stacks '
      'history',
      (tester) async {
        // Arrive the way a phone does (push over /messages), then widen.
        final router = await _pump(tester, _phone, '/messages');
        await tester.tap(find.text('Member c1'));
        await _settle(tester);
        await _resize(tester, _desktop);
        expect(_selectedRowIds(tester), ['c1']);

        await tester.tap(find.text('Member c2'));
        await _settle(tester);
        expect(_openChatId(tester), 'c2');
        expect(_url(router), '/chat-detail/c2');

        await tester.tap(find.text('Member c3'));
        await _settle(tester);
        expect(_openChatId(tester), 'c3');
        expect(_url(router), '/chat-detail/c3');
        expect(find.byType(InboxPage), findsOneWidget);
        expect(find.byType(ChatDetailPage), findsOneWidget);

        // c1 -> c2 -> c3 left ONE entry above /messages: a single back lands
        // there, with no stale pane.
        router.pop();
        await _settle(tester);
        expect(_url(router), '/messages');
        expect(find.byType(ChatDetailPage), findsNothing);
        expect(find.byType(InboxPage), findsOneWidget);
        expect(router.canPop(), isFalse);
      },
    );

    _testWidgets('a selected row remains a tappable no-op', (tester) async {
      await _pump(tester, _desktop, RouteNames.chatDetailPath('c1'));

      // The name is also in the chat header, so aim at the list row.
      await tester.tap(
        find.descendant(
          of: find.byType(InboxPage),
          matching: find.text('Member c1'),
        ),
      );
      await _settle(tester);

      expect(_openChatId(tester), 'c1');
      expect(find.byType(ChatDetailPage), findsOneWidget);
    });

    _testWidgets('a route change with both panes live raises no Hero error', (
      tester,
    ) async {
      final router = await _pump(tester, _desktop, '/messages');
      await tester.tap(find.text('Member c1'));
      await _settle(tester);

      // The list row and the chat header share a Hero tag; with both on
      // screen a transition would assert unless the pane gives its Hero up.
      unawaited(router.push('/notifications'));
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('notifications'), findsOneWidget);
    });
  });

  group('resize across the 900 boundary', () {
    _testWidgets('chat route: shrinking keeps the conversation, widening '
        'restores the list', (tester) async {
      await _pump(tester, _desktop, RouteNames.chatDetailPath('c1'));
      expect(find.byType(InboxPage), findsOneWidget);

      await _resize(tester, _phone);
      expect(_openChatId(tester), 'c1');
      expect(find.byType(InboxPage), findsNothing);

      await _resize(tester, _desktop);
      expect(find.byType(InboxPage), findsOneWidget);
      expect(_openChatId(tester), 'c1');
      expect(_selectedRowIds(tester), ['c1']);
    });

    _testWidgets(
      '/messages: a pane-only selection is dropped on a phone, not resurrected',
      (tester) async {
        await _pump(tester, _desktop, '/messages');
        await tester.tap(find.text('Member c1'));
        await _settle(tester);
        expect(_openChatId(tester), 'c1');

        await _resize(tester, _phone);
        expect(find.byType(InboxPage), findsOneWidget);
        expect(find.byType(ChatDetailPage), findsNothing);

        await _resize(tester, _desktop);
        expect(find.byType(NmEmptyState), findsOneWidget);
        expect(find.byType(ChatDetailPage), findsNothing);
      },
    );
  });

  group('composer state', () {
    _testWidgets('switching conversations clears the composer', (tester) async {
      await _pump(tester, _desktop, '/messages');
      await tester.tap(find.text('Member c1'));
      await _settle(tester);

      await tester.enterText(_composerField(), 'for Member c1 only');
      await tester.pump();
      expect(_composerText(tester), 'for Member c1 only');

      await tester.tap(find.text('Member c2'));
      await _settle(tester);

      expect(_openChatId(tester), 'c2');
      // Without the per-conversation ValueKey the composer's State would be
      // reused and c1's text would show up in c2's thread.
      expect(_composerText(tester), isEmpty);
    });

    _testWidgets('switching on the chat route clears the composer too', (
      tester,
    ) async {
      await _pump(tester, _desktop, RouteNames.chatDetailPath('c1'));
      await tester.enterText(_composerField(), 'for Member c1 only');
      await tester.pump();

      await tester.tap(find.text('Member c2'));
      await _settle(tester);

      expect(_openChatId(tester), 'c2');
      expect(_composerText(tester), isEmpty);
    });

    _testWidgets('composer text does not survive a layout switch '
        '(documented limitation)', (tester) async {
      // There is no draft persistence anywhere in the app: the text lives in
      // the composer's own TextEditingController, which is disposed with the
      // widget. Crossing 900 re-parents the chat, so it is lost.
      await _pump(tester, _desktop, RouteNames.chatDetailPath('c1'));
      await tester.enterText(_composerField(), 'half-typed message');
      await tester.pump();
      expect(_composerText(tester), 'half-typed message');

      await _resize(tester, _phone);

      expect(_openChatId(tester), 'c1');
      expect(_composerText(tester), isEmpty);
    });
  });

  group('failure paths', () {
    _testWidgets('an unknown id shows the existing unavailable state, panes '
        'intact', (tester) async {
      final repo = _FakeRepo(count: 3);
      await _pump(
        tester,
        _desktop,
        RouteNames.chatDetailPath('nope'),
        repo: repo,
      );

      expect(find.text('Profile not available'), findsOneWidget);
      // Looked up once, re-fetched once -- not an endless refetch loop.
      expect(repo.fetches, 2);
      expect(find.byType(ChatDetailPage), findsNothing);
      expect(find.byType(InboxPage), findsOneWidget);
      expect(find.text('Member c1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _testWidgets('the unavailable state offers the way back to the inbox', (
      tester,
    ) async {
      await _pump(tester, _phone, RouteNames.chatDetailPath('nope'));

      expect(find.text('Profile not available'), findsOneWidget);
      await tester.tap(find.text('Inbox'));
      await _settle(tester);

      expect(find.byType(InboxPage), findsOneWidget);
    });

    _testWidgets('a backend failure shows retry, not a false not-found', (
      tester,
    ) async {
      final repo = _FakeRepo(count: 3)..failConversations = true;
      await _pump(
        tester,
        _desktop,
        RouteNames.chatDetailPath('c1'),
        repo: repo,
      );

      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('Profile not available'), findsNothing);
      expect(find.byType(ChatDetailPage), findsNothing);
      expect(find.byType(InboxPage), findsOneWidget);
    });

    _testWidgets('loading shows the existing spinner in the pane', (
      tester,
    ) async {
      final repo = _FakeRepo(count: 3)..gate();
      await _pump(
        tester,
        _desktop,
        RouteNames.chatDetailPath('c1'),
        repo: repo,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ChatDetailPage), findsNothing);

      repo.release();
      await _settle(tester);
      expect(_openChatId(tester), 'c1');
    });

    _testWidgets('an empty inbox shows the empty list and the empty pane', (
      tester,
    ) async {
      await _pump(tester, _desktop, '/messages', repo: _FakeRepo(count: 0));

      expect(find.byType(EmptyInbox), findsOneWidget);
      expect(find.byType(NmEmptyState), findsWidgets);
      expect(find.byType(ChatDetailPage), findsNothing);
    });
  });

  group('scrolling', () {
    _testWidgets('the list and the chat scroll independently', (tester) async {
      await _pump(
        tester,
        _desktop,
        RouteNames.chatDetailPath('c1'),
        repo: _FakeRepo(count: 40, messages: 60),
      );

      final list = _scrollable(tester, find.byType(InboxPage));
      final chat = _scrollable(tester, find.byType(ChatDetailPage));
      expect(list.position.maxScrollExtent, greaterThan(0));
      expect(chat.position.maxScrollExtent, greaterThan(0));

      final chatBefore = chat.position.pixels;
      final listBefore = list.position.pixels;

      await tester.fling(find.byType(InboxPage), const Offset(0, -300), 1000);
      await _settle(tester);
      expect(list.position.pixels, isNot(listBefore));
      expect(chat.position.pixels, chatBefore);

      final listMid = list.position.pixels;
      await tester.fling(
        find.byType(ChatDetailPage),
        const Offset(0, 300),
        1000,
      );
      await _settle(tester);
      expect(chat.position.pixels, isNot(chatBefore));
      expect(list.position.pixels, listMid);
    });
  });

  group('no overflow', () {
    final sizes = <String, Size>{
      '320 phone': const Size(320, 568),
      '900 boundary': const Size(900, 700),
      'short desktop': kShortDesktop,
      '1440 desktop': _desktop,
    };
    for (final entry in sizes.entries) {
      for (final location in ['/messages', RouteNames.chatDetailPath('c1')]) {
        _testWidgets('$location at ${entry.key}', (tester) async {
          await _pump(
            tester,
            entry.value,
            location,
            repo: _FakeRepo(count: 5, messages: 8),
          );
          expectNoOverflowIn(drainExceptions(tester));
        });
      }
    }
  });
}

// ---------------------------------------------------------------------------
// Harness

/// Builds the same shape as production: the Inbox as a shell branch under the
/// real [AppBottomNavShell], and the chat as a ROOT-LEVEL route above it.
GoRouter _router(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) =>
          AppBottomNavShell(navigationShell: shell),
      branches: [
        _placeholderBranch('/discover'),
        _placeholderBranch('/matches'),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: RouteNames.messages,
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: InboxShellPage()),
            ),
          ],
        ),
        _placeholderBranch('/premium'),
      ],
    ),
    GoRoute(
      path: RouteNames.chatDetailPattern,
      name: RouteNames.chatDetailName,
      builder: (context, state) => InboxShellPage(
        selectedConversationId: state.pathParameters['conversationId']!,
        initialConversation: state.extra is ConversationEntity
            ? state.extra! as ConversationEntity
            : null,
      ),
    ),
    GoRoute(
      path: '/notifications',
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('notifications'))),
    ),
  ],
);

StatefulShellBranch _placeholderBranch(String path) => StatefulShellBranch(
  routes: [
    GoRoute(
      path: path,
      builder: (context, state) => Scaffold(body: Text('placeholder $path')),
    ),
  ],
);

List<Override> _overrides(_FakeRepo repo) => [
  conversationRepositoryProvider.overrideWithValue(repo),
  // The real service would reach for Firebase; this one never connects.
  realtimeServiceProvider.overrideWithValue(
    RealtimeService(
      baseUrl: 'http://localhost',
      tokenProvider: () async => null,
    ),
  ),
];

Future<GoRouter> _pump(
  WidgetTester tester,
  Size size,
  String location, {
  _FakeRepo? repo,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  await tester.binding.setSurfaceSize(size);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = _router(location);
  addTearDown(router.dispose);
  final container = ProviderContainer(
    overrides: _overrides(repo ?? _FakeRepo(count: 3)),
  );
  _container = container;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  if (settle) await _settle(tester);
  return router;
}

/// `testWidgets`, then unmounts the app INSIDE the test (see [_unmount]).
void _testWidgets(
  String description,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(description, (tester) async {
    await body(tester);
    await _unmount(tester);
  });
}

/// The container behind the app under test, so [_unmount] can wind it down.
ProviderContainer? _container;

/// Unmounts the app inside the test and disposes its providers in a safe order.
///
/// `MessagesNotifier.build` registers an `onDispose` that does a `ref.read` of
/// another provider. If the whole container is disposed with a chat open (app
/// teardown, or the end of a test), Riverpod rejects that read and reports an
/// uncaught StateError. It has no user-visible effect and is unrelated to
/// layout, so it is left alone here; the tests sidestep it by invalidating the
/// thread providers while the container is still alive, before disposing it.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final container = _container;
  _container = null;
  if (container == null) return;
  for (final id in const ['c1', 'c2', 'c3', 'c4', 'c5', 'nope']) {
    container.invalidate(messagesProvider(id));
  }
  container.dispose();
  // Let any widget-owned timer (debounces, highlights) fire before the test ends.
  await tester.pump(const Duration(seconds: 10));
}

/// Bounded pump walk: the inbox shimmer and chat animations never settle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _resize(WidgetTester tester, Size size) async {
  expectNoOverflowIn(await resizeTo(tester, size));
  await _settle(tester);
}

/// What the engine does on a browser back/forward: reports a new location.
Future<void> _browserNavigateTo(WidgetTester tester, String location) async {
  final message = const JSONMethodCodec().encodeMethodCall(
    MethodCall('pushRouteInformation', <String, dynamic>{'location': location}),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    message,
    (_) {},
  );
  await _settle(tester);
}

/// The address bar's path. On web the app sets
/// `GoRouter.optionURLReflectsImperativeAPIs`, so a pushed route is reflected
/// in the URL; this reads it the way the browser would.
String _url(GoRouter router) => router.routeInformationParser
    .restoreRouteInformation(router.routerDelegate.currentConfiguration)!
    .uri
    .path;

String _openChatId(WidgetTester tester) =>
    tester.widget<ChatDetailPage>(find.byType(ChatDetailPage)).conversation.id;

/// Ids of the list rows currently drawn as selected.
List<String> _selectedRowIds(WidgetTester tester) => [
  for (final card in tester.widgetList<NmChatCard>(find.byType(NmChatCard)))
    if (card.isSelected) card.name.replaceFirst('Member ', ''),
];

Finder _composerField() => find.descendant(
  of: find.byType(ChatComposer),
  matching: find.byType(TextField),
);

String _composerText(WidgetTester tester) =>
    tester.widget<TextField>(_composerField()).controller!.text;

/// The vertical scrollable under [root] that actually has content to scroll.
ScrollableState _scrollable(WidgetTester tester, Finder root) {
  final candidates = find
      .descendant(of: root, matching: find.byType(Scrollable))
      .evaluate()
      .map((e) => (e as StatefulElement).state as ScrollableState)
      .where(
        (s) =>
            s.position.axis == Axis.vertical &&
            s.position.hasContentDimensions &&
            s.position.maxScrollExtent > 0,
      );
  expect(candidates, isNotEmpty, reason: 'nothing scrollable under $root');
  return candidates.first;
}

// ---------------------------------------------------------------------------
// Fakes

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

/// Hand-written fake (no mocking library in this repo). Anything the chat does
/// not need here is left to `noSuchMethod`, so an unexpected call fails loudly.
class _FakeRepo implements ConversationRepository {
  _FakeRepo({required int count, this.messages = 0})
    : _conversations = [
        for (var i = 1; i <= count; i++)
          ConversationEntity(
            id: 'c$i',
            profile: _profile('c$i'),
            lastMessage: 'hello from $i',
            // Newest first, so c1 is the top row.
            lastMessageAt: DateTime(2026, 1, 1).subtract(Duration(hours: i)),
          ),
      ];

  final List<ConversationEntity> _conversations;
  final int messages;
  bool failConversations = false;
  int fetches = 0;
  Completer<void>? _gate;

  void gate() => _gate = Completer<void>();
  void release() => _gate?.complete();

  @override
  Future<ConversationResultPage> getConversations({
    int page = 1,
    int limit = 20,
  }) async {
    fetches++;
    final gate = _gate;
    if (gate != null && !gate.isCompleted) await gate.future;
    if (failConversations) throw Exception('offline');
    return ConversationResultPage(
      items: _conversations,
      page: 1,
      limit: limit,
      total: _conversations.length,
      hasMore: false,
    );
  }

  @override
  Future<MessagePage> getMessages(
    String conversationId, {
    int page = 1,
    int limit = 30,
    String? cursor,
  }) async => MessagePage(
    items: [
      for (var i = 0; i < messages; i++)
        MessageEntity(
          id: '$conversationId-m$i',
          conversationId: conversationId,
          text: 'message number $i',
          sentAt: DateTime(2026, 1, 1, 0, i),
          isMine: i.isEven,
        ),
    ],
    page: 1,
    hasMore: false,
  );

  @override
  Future<void> markRead(String conversationId) async {}

  @override
  Future<void> setTyping(String conversationId, bool isTyping) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
