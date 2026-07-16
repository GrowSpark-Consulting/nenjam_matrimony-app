import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/authentication/presentation/providers/auth_providers.dart';
import 'api_client.dart';
import 'api_interceptor.dart';

/// The shared [ApiClient] singleton, with the auth interceptor wired to
/// Firebase's ID token (see [AuthTokenService]) — every request automatically
/// carries `Authorization: Bearer <token>` for the signed-in user, or none at
/// all if signed out (matching FirebaseAuthGuard's expectations on the
/// backend, which then responds 401).
///
/// A 401 triggers one recovery attempt (force-refreshed token, request
/// retried once) before falling back to [FirebaseAuthRepository.logout] —
/// see [AuthInterceptor] for the full flow. That logout is enough: the app
/// reacts to it in exactly one place (NenjamMatrimonyApp's authStateChanges
/// listener clears local state, and app_router.dart's redirect — re-run via
/// its refreshListenable — sends the user to Login), so this provider never
/// needs a BuildContext or navigation logic of its own.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  final tokenService = ref.watch(authTokenServiceProvider);

  client.addAuthInterceptor(
    AuthInterceptor(
      dio: client.dio,
      getAccessToken: () => tokenService.getFirebaseToken(),
      refreshAccessToken: () => tokenService.getFirebaseToken(forceRefresh: true),
      onSessionExpired: () => ref.read(authRepositoryProvider).logout(),
    ),
  );

  return client;
});
