import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_entity_pages.dart';
import 'package:nenjam_matrimony/core/router/route_entity_resolvers.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// What a browser refresh, a copied link or a bookmark does to the two
/// id-carrying routes: the app starts at the URL with no `extra` object, so
/// the id in the path has to be enough.

Widget _app(GoRouter router, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );

GoRouter _probeRouter(String initial, List<String> log) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(path: '/discover', builder: (_, __) => const Text('discover')),
    GoRoute(
      path: RouteNames.chatDetailPattern,
      builder: (_, s) {
        log.add(
          'chat:${s.pathParameters['conversationId']}'
          ':extra=${s.extra}:q=${s.uri.queryParameters['ref']}',
        );
        return const Text('chat');
      },
    ),
    GoRoute(
      path: RouteNames.profileDetailPattern,
      builder: (_, s) {
        log.add('profile:${s.pathParameters['profileId']}');
        return const Text('profile');
      },
    ),
  ],
);

void main() {
  group('route paths', () {
    test('build and recognise id-carrying locations', () {
      expect(RouteNames.chatDetailPath('abc'), '/chat-detail/abc');
      expect(
        RouteNames.profileDetailPath('p 1/x'),
        '/profile-detail/p%201%2Fx',
      );
      expect(RouteNames.isChatDetailLocation('/chat-detail/abc'), isTrue);
      expect(RouteNames.isChatDetailLocation('/chat-detail'), isTrue);
      expect(RouteNames.isChatDetailLocation('/chat-details'), isFalse);
      expect(RouteNames.isProfileDetailLocation('/profile-detail/p1'), isTrue);
      expect(RouteNames.isProfileDetailLocation('/profile'), isFalse);
    });
  });

  group('direct navigation (no extra)', () {
    testWidgets('chat URL yields its id and survives a query string', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(
        _app(_probeRouter('/chat-detail/abc?ref=push', log)),
      );
      await tester.pumpAndSettle();
      expect(find.text('chat'), findsOneWidget);
      expect(log.single, 'chat:abc:extra=null:q=push');
    });

    testWidgets('encoded profile id round-trips', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(
        _app(_probeRouter(RouteNames.profileDetailPath('p 1/x'), log)),
      );
      await tester.pumpAndSettle();
      expect(log.single, 'profile:p 1/x');
    });

    testWidgets('push then pop returns to the page underneath', (tester) async {
      final log = <String>[];
      final router = _probeRouter('/discover', log);
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      router.push(RouteNames.chatDetailPath('abc'), extra: 'payload');
      await tester.pumpAndSettle();
      expect(find.text('chat'), findsOneWidget);
      expect(log.single, 'chat:abc:extra=payload:q=null');

      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('discover'), findsOneWidget);
    });
  });

  group('lookup by id', () {
    testWidgets('chat shows a loading state, then not-available', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          GoRouter(
            initialLocation: RouteNames.chatDetailPath('gone'),
            routes: [
              GoRoute(
                path: RouteNames.chatDetailPattern,
                builder: (_, s) => ChatDetailRoutePage(
                  conversationId: s.pathParameters['conversationId']!,
                ),
              ),
              GoRoute(
                path: RouteNames.messages,
                builder: (_, __) => const Text('inbox'),
              ),
            ],
          ),
          overrides: [
            chatConversationByIdProvider(
              'gone',
            ).overrideWith((ref) async => null),
          ],
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Profile not available'), findsOneWidget);

      // The way out goes to the Inbox rather than stranding the member.
      await tester.tap(find.text('Inbox'));
      await tester.pumpAndSettle();
      expect(find.text('inbox'), findsOneWidget);
    });

    testWidgets('a backend failure offers retry, not a false not-found', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        _app(
          GoRouter(
            initialLocation: RouteNames.profileDetailPath('p1'),
            routes: [
              GoRoute(
                path: RouteNames.profileDetailPattern,
                builder: (_, s) => ProfileDetailRoutePage(
                  profileId: s.pathParameters['profileId']!,
                ),
              ),
            ],
          ),
          overrides: [
            profileByIdProvider('p1').overrideWith((ref) async {
              calls++;
              throw Exception('offline');
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Profile not available'), findsNothing);
      expect(find.text('Try Again'), findsOneWidget);

      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();
      expect(calls, 2);
    });
  });
}
