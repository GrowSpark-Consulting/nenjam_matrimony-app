import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/authentication/presentation/providers/auth_providers.dart';
import 'api_client.dart';
import 'api_interceptor.dart';

/// The shared [ApiClient] singleton, with the auth interceptor wired to
/// Firebase's ID token (see [AuthTokenService]) — every request automatically
/// carries `Authorization: Bearer <token>` for the signed-in user, or none at
/// all if signed out (matching FirebaseAuthGuard's expectations on the
/// backend, which then responds 401).
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  final tokenService = ref.watch(authTokenServiceProvider);

  client.addAuthInterceptor(
    AuthInterceptor(
      getAccessToken: () => tokenService.getFirebaseToken(),
      // Firebase's SDK refreshes tokens transparently — there's no separate
      // refresh-token flow to drive here.
      getRefreshToken: () async => null,
      saveTokens: (_, __) async {},
      onTokenExpired: () async {
        // A 401 from our backend while a Firebase user is signed in means
        // something other than "token needs refreshing" (Firebase already
        // handles that) — most likely FIREBASE_* isn't configured on the
        // backend yet. Surface it in debug logs rather than force-signing
        // the user out.
        debugPrint(
          '[API] Got 401 from backend — check that the backend has real '
          'Firebase Admin credentials configured.',
        );
      },
    ),
  );

  return client;
});
