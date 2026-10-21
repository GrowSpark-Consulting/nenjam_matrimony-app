import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_interceptor.dart';

/// The dummy-OTP flow's authentication seam.
///
/// Onboarding runs signed out from start to finish, so a member arrives at the
/// mobile step with no credential. `LocalAuthSession` records that they passed
/// it, and [AuthInterceptor] is what turns that record into something the
/// backend accepts — without it the app merely *looked* signed in while every
/// request went out bare, which is why onboarding once saved nothing and
/// Discover answered 401 in a loop.
///
/// These pin the header contract rather than the storage plumbing: what goes
/// on the wire, and — more importantly — what must never go on it.
void main() {
  const devHeader = 'X-Dev-Auth-Phone';
  const phone = '+919876543210';

  AuthInterceptor build({
    String? firebaseToken,
    String? Function()? devAuthPhone,
  }) => AuthInterceptor(
    dio: Dio(),
    getAccessToken: () async => firebaseToken,
    refreshAccessToken: () async => firebaseToken,
    onSessionExpired: () async {},
    devAuthPhone: devAuthPhone,
  );

  Future<RequestOptions> send(AuthInterceptor interceptor) async {
    final options = RequestOptions(path: '/profiles/draft/basic-details');
    final handler = RequestInterceptorHandler();
    await interceptor.onRequest(options, handler);
    return options;
  }

  group('the retired dummy-OTP header', () {
    test('is NOT sent even on a local dummy session', () async {
      // The backend's guard no longer reads this header (only a Firebase ID
      // token authenticates), and sending it made every cross-origin browser
      // request fail its CORS preflight, because the API does not allow it.
      // The local session now only suppresses 401 refresh/sign-out storms.
      final options = await send(
        build(firebaseToken: null, devAuthPhone: () => phone),
      );

      expect(options.headers.containsKey(devHeader), isFalse);
      expect(options.headers.containsKey('Authorization'), isFalse);
    });

    test('is NOT sent when a Firebase token exists', () async {
      // The real credential always wins. The two are never sent together —
      // which is also the condition the backend guard requires before it will
      // look at the dev header at all, so sending both would be the one shape
      // that could let a dummy session ride alongside a real token.
      final options = await send(
        build(firebaseToken: 'a-real-token', devAuthPhone: () => phone),
      );

      expect(options.headers['Authorization'], 'Bearer a-real-token');
      expect(options.headers.containsKey(devHeader), isFalse);
    });

    test('is NOT sent when there is no session at all', () async {
      // Logout clears LocalAuthSession, so `identifier` returns null and the
      // next request authenticates as nobody — the property that stops a
      // signed-out device from silently resuming the account it just left.
      final options = await send(
        build(firebaseToken: null, devAuthPhone: () => null),
      );

      expect(options.headers.containsKey(devHeader), isFalse);
      expect(options.headers.containsKey('Authorization'), isFalse);
    });

    test('is NOT sent by a build that does not use the dummy OTP', () async {
      // api_providers supplies null for `devAuthPhone` unless the build uses
      // the dummy OTP, so an ordinary release has no path to this header.
      final options = await send(build(firebaseToken: null));

      expect(options.headers.containsKey(devHeader), isFalse);
    });

    test('an empty identifier is not a session', () async {
      final options = await send(
        build(firebaseToken: null, devAuthPhone: () => ''),
      );

      expect(options.headers.containsKey(devHeader), isFalse);
    });
  });
}
