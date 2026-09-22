import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_interceptor.dart';

/// The 401-recovery gate on a dummy-OTP / local-auth build.
///
/// `_shouldAttemptRecovery` skips recovery when a local (dummy-OTP) session is
/// open: there is no Firebase token to refresh, so refreshing would yield
/// null, call `onSessionExpired`, and sign the member out in a loop. A 401
/// there is a backend-configuration answer, not an expired session.
///
/// The audit asked whether that decision can be made from a *stale* view of
/// the session. These pin that it is read live, per 401, from the same
/// callback the request itself used — so clearing the session (logout, delete
/// account) takes effect on the very next 401 with no cache to invalidate.
void main() {
  const phone = '+919876543210';

  /// Records whether the session-expired teardown (logout) ran.
  late bool signedOut;
  late int refreshCalls;

  setUp(() {
    signedOut = false;
    refreshCalls = 0;
  });

  AuthInterceptor build({
    String? firebaseToken,
    String? Function()? devAuthPhone,
  }) => AuthInterceptor(
    dio: Dio(),
    getAccessToken: () async => firebaseToken,
    refreshAccessToken: () async {
      refreshCalls++;
      return firebaseToken;
    },
    onSessionExpired: () async => signedOut = true,
    devAuthPhone: devAuthPhone,
  );

  /// Drives a 401 response through `onResponse`, returning what the caller
  /// would receive. Uses `onResponse` (not `onError`) because ApiClient sets
  /// `validateStatus: status < 500`, so a 401 arrives as a response.
  Future<Response<dynamic>> send401(
    AuthInterceptor interceptor, {
    required bool withAuthHeader,
  }) async {
    final options = RequestOptions(path: '/profiles/draft');
    if (withAuthHeader) {
      options.headers['Authorization'] = 'Bearer stale-token';
    }
    final response = Response<dynamic>(
      requestOptions: options,
      statusCode: 401,
    );
    Response<dynamic>? delivered;
    final handler = ResponseInterceptorHandler();
    await interceptor.onResponse(response, handler);
    delivered ??= response;
    return delivered;
  }

  group('active local/dummy session + 401', () {
    test('does not refresh and does not sign out', () async {
      final interceptor = build(
        firebaseToken: null,
        devAuthPhone: () => phone,
      );

      await send401(interceptor, withAuthHeader: false);

      // The whole point of the gate: no refresh storm, no logout storm.
      expect(refreshCalls, 0, reason: 'nothing to refresh on a local session');
      expect(signedOut, isFalse, reason: 'a 401 here is a config answer');
    });
  });

  group('no local session + 401', () {
    test('an unauthenticated request does not sign the member out', () async {
      final interceptor = build(firebaseToken: null, devAuthPhone: () => null);

      await send401(interceptor, withAuthHeader: false);

      // Recovery is attempted (no local session to block it)...
      expect(refreshCalls, 1);
      // ...but a request that never carried a token is "not signed in yet",
      // not "signed out" — the startup-race fix.
      expect(signedOut, isFalse);
    });

    test('an authenticated request that can no longer refresh signs out', () async {
      final interceptor = build(firebaseToken: null, devAuthPhone: () => null);

      await send401(interceptor, withAuthHeader: true);

      expect(refreshCalls, 1);
      expect(signedOut, isTrue, reason: 'a genuine expiry');
    });
  });

  group('Firebase-authenticated session + 401', () {
    test('never takes the local-session bypass', () async {
      // A real Firebase build supplies null for devAuthPhone entirely.
      final interceptor = build(
        firebaseToken: 'a-real-token',
        devAuthPhone: () => null,
      );

      await send401(interceptor, withAuthHeader: true);

      // Recovery ran: the Firebase path is untouched by the local-session gate.
      expect(refreshCalls, 1);
    });

    test('a Firebase token wins even while a local session lingers', () async {
      // Belt-and-braces: onRequest puts the Firebase token on and never the
      // dev header, so the two are never both in play for one request.
      final interceptor = build(
        firebaseToken: 'a-real-token',
        devAuthPhone: () => phone,
      );

      final options = RequestOptions(path: '/profiles/draft');
      await interceptor.onRequest(options, RequestInterceptorHandler());

      expect(options.headers['Authorization'], 'Bearer a-real-token');
      expect(options.headers.containsKey('X-Dev-Auth-Phone'), isFalse);
    });
  });

  group('local session cleared after logout / delete account', () {
    test('the very next 401 stops bypassing recovery — no stale flag', () async {
      // The callback is the live seam: api_providers wires it to
      // `localAuthSessionProvider.identifier`, which reads SharedPreferences
      // on every call. Clearing the session is modelled here by the callback
      // starting to return null.
      String? identifier = phone;
      final interceptor = build(
        firebaseToken: null,
        devAuthPhone: () => identifier,
      );

      // While the session is open: gate closed, no recovery.
      await send401(interceptor, withAuthHeader: false);
      expect(refreshCalls, 0);

      // Logout / delete account clears it.
      identifier = null;

      // Next 401 re-reads and now attempts recovery normally.
      await send401(interceptor, withAuthHeader: false);
      expect(
        refreshCalls,
        1,
        reason: 'the gate re-read the cleared session, not a cached flag',
      );
    });

    test('a session started mid-flight is honoured on the next 401', () async {
      String? identifier;
      final interceptor = build(
        firebaseToken: null,
        devAuthPhone: () => identifier,
      );

      await send401(interceptor, withAuthHeader: false);
      expect(refreshCalls, 1, reason: 'no session yet');

      identifier = phone;

      await send401(interceptor, withAuthHeader: false);
      expect(refreshCalls, 1, reason: 'now gated — no second refresh');
    });
  });

  group('retry / sign-out behaviour is unchanged', () {
    test('an already-retried request is never retried again', () async {
      final interceptor = build(firebaseToken: null, devAuthPhone: () => null);

      final options = RequestOptions(path: '/profiles/draft');
      options.headers['Authorization'] = 'Bearer stale-token';
      // Mark it as the replay (the interceptor's own private key).
      options.extra['nm_auth_retried'] = true;

      await interceptor.onResponse(
        Response<dynamic>(requestOptions: options, statusCode: 401),
        ResponseInterceptorHandler(),
      );

      expect(refreshCalls, 0, reason: 'single retry only');
      expect(signedOut, isFalse);
    });

    test('a FormData body is never replayed', () async {
      final interceptor = build(firebaseToken: null, devAuthPhone: () => null);

      final options = RequestOptions(path: '/profiles/photos')
        ..headers['Authorization'] = 'Bearer stale-token'
        ..data = FormData();

      await interceptor.onResponse(
        Response<dynamic>(requestOptions: options, statusCode: 401),
        ResponseInterceptorHandler(),
      );

      expect(refreshCalls, 0, reason: 'single-use stream must not be replayed');
    });

    test('a non-401 is passed through untouched', () async {
      final interceptor = build(firebaseToken: null, devAuthPhone: () => null);

      await interceptor.onResponse(
        Response<dynamic>(
          requestOptions: RequestOptions(path: '/profiles/draft'),
          statusCode: 500,
        ),
        ResponseInterceptorHandler(),
      );

      expect(refreshCalls, 0);
      expect(signedOut, isFalse);
    });
  });
}
