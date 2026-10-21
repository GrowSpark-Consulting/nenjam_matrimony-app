import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/authentication/domain/services/local_auth_session.dart';
import '../../features/authentication/domain/services/otp_verifier.dart';
import '../../features/authentication/presentation/providers/auth_providers.dart';
import '../constants/app_constants.dart';
import 'api_client.dart';
import 'api_interceptor.dart';
import 'backend_connectivity_checker.dart';

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
      refreshAccessToken: () =>
          tokenService.getFirebaseToken(forceRefresh: true),
      onSessionExpired: () => ref.read(authRepositoryProvider).logout(),
      // Marks a local-only (dummy-OTP) session so a 401 on it is not turned
      // into a refresh/sign-out storm. Null unless this build uses the dummy
      // OTP. No header is sent for it — the backend does not read one.
      devAuthPhone: () => dummyOtpEnabled
          ? ref.read(localAuthSessionProvider).identifier
          : null,
    ),
  );

  return client;
});

/// Startup `/health` probe. Runs on its own bare [Dio] rather than the shared
/// [ApiClient] on purpose: `/health` is public, so routing it through the auth
/// interceptor would make the splash wait on a Firebase token it doesn't need
/// (and put a signed-out user's 401 recovery in the startup path).
final serverHealthCheckerProvider = Provider<BackendConnectivityChecker>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: AppConstants.healthCheckTimeout,
      receiveTimeout: AppConstants.healthCheckTimeout,
      sendTimeout: AppConstants.healthCheckTimeout,
      responseType: ResponseType.json,
      headers: {'Accept': 'application/json'},
      validateStatus: (_) => true,
    ),
  );
  ref.onDispose(dio.close);
  return BackendConnectivityChecker(dio);
});
