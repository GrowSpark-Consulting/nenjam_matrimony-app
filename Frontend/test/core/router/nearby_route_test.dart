import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nenjam_matrimony/core/router/app_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/nearby/presentation/pages/nearby_page.dart';

/// Near Me is reachable from the drawer and from the Matches "Near Me" chip,
/// both of which `push(RouteNames.nearby)`. The constant existed before the
/// route did, so those pushes ended on go_router's "no routes for location:
/// /nearby" page. This asserts the real route table — the one `createRouter`
/// builds — actually matches that location, by name and by path.
void main() {
  testWidgets('/nearby resolves to NearbyPage in the real route table', (
    tester,
  ) async {
    final router = await _buildAppRouter(tester);

    final match = router.configuration.findMatch(Uri.parse(RouteNames.nearby));
    expect(match.isError, isFalse);
    expect(match.uri.path, RouteNames.nearby);

    // The matched route builds Near Me, not some other page reusing the path.
    final leaf = match.matches.last;
    final route = leaf.route as GoRoute;
    expect(route.name, RouteNames.nearbyName);
    expect(
      route.builder!(
        _FakeContext(),
        leaf.buildState(router.configuration, match),
      ),
      isA<NearbyPage>(),
    );
  });

  testWidgets('the nearby route name resolves to the same location', (
    tester,
  ) async {
    final router = await _buildAppRouter(tester);
    expect(router.namedLocation(RouteNames.nearbyName), RouteNames.nearby);
  });

  test('Near Me stays behind the auth guard', () {
    // Not public — so the existing redirect keeps sending a signed-out
    // visitor to the landing screen, exactly as before this route existed.
    expect(RouteNames.publicRoutes.contains(RouteNames.nearby), isFalse);
  });
}

/// Builds the app's real [GoRouter] without mounting it, so the assertions are
/// about route registration rather than about what any page renders. Firebase
/// and Google Sign-In are faked because `createRouter` reaches for both the
/// moment it is constructed (its `refreshListenable` subscribes to the auth
/// stream) and neither SDK is initialised in a unit test.
Future<GoRouter> _buildAppRouter(WidgetTester tester) async {
  late GoRouter router;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(_FakeFirebaseAuth()),
        googleSignInProvider.overrideWithValue(_FakeGoogleSignIn()),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          router = createRouter(ref);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return router;
}

class _FakeFirebaseAuth implements FirebaseAuth {
  @override
  User? get currentUser => null;

  @override
  Stream<User?> authStateChanges() => Stream<User?>.value(null);

  @override
  Stream<User?> idTokenChanges() => Stream<User?>.value(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGoogleSignIn implements GoogleSignIn {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The route's builder ignores its context — it returns a const page — so a
/// stand-in is enough to prove which widget it builds.
class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
