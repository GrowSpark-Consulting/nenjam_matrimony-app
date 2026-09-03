import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_providers.dart';
import '../../presentation/providers/auth_providers.dart';
import 'local_auth_session.dart';

/// Thrown when a passed dummy OTP could not be turned into a real session.
///
/// Deliberately a distinct type rather than a bool: a member who answered the
/// OTP correctly and still has no account has hit a server-side condition
/// (the dummy-OTP flags are off, the number is not whitelisted, Firebase Admin
/// is unconfigured), and the screens must be able to say so rather than wave
/// them into an app where nothing they do will persist.
class DummyOtpSessionException implements Exception {
  DummyOtpSessionException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'DummyOtpSessionException($statusCode): $message';
}

/// Turns a passed dummy OTP into a **real Firebase session**.
///
/// This is the seam that used to be missing. The dummy OTP verifies nothing
/// (see [MockOtpVerifier]) and mints no credential, so a member finished
/// signup with only [LocalAuthSession] — a device-local marker — and every
/// request went out under an `X-Dev-Auth-Phone` header. That produced no
/// Firebase account, and no `users` row wherever the header was not honoured:
/// the member was signed in to an identity that did not exist anywhere.
///
/// The OTP mechanism is untouched. What changed is what a pass *produces*:
/// the backend creates (or reuses) the Firebase Auth account and the internal
/// `users` row, and returns a custom token this exchanges for an ordinary
/// session. From that point `FirebaseAuth.currentUser` is real, its uid is the
/// one the backend stored, and every later request authenticates with a Bearer
/// ID token like any other screen's.
///
/// [LocalAuthSession] is cleared on success rather than left behind: its whole
/// purpose was to stand in for this, and a stale marker would keep the
/// dev-auth header alive as a second identity for the same person.
abstract interface class DummyOtpSessionStarter {
  /// Signs the member in as [phoneE164], carrying [email] along when signup
  /// collected one so the address lands on the same single account.
  ///
  /// Returns the Firebase uid now signed in. Throws
  /// [DummyOtpSessionException] if any step failed — in which case no session
  /// was opened and the caller must not proceed.
  Future<String> start({required String phoneE164, String? email});
}

class ApiDummyOtpSessionStarter implements DummyOtpSessionStarter {
  const ApiDummyOtpSessionStarter(this._ref);

  final Ref _ref;

  @override
  Future<String> start({required String phoneE164, String? email}) async {
    final Response<Map<String, dynamic>> response;
    try {
      response = await _ref.read(apiClientProvider).post<Map<String, dynamic>>(
        ApiEndpoints.dummyOtpSession,
        data: {
          'phone': phoneE164,
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        },
      );
    } on DioException catch (e) {
      // No response at all — offline, DNS, timeout. Distinct from a refusal.
      throw DummyOtpSessionException(
        e.message ?? 'Could not reach the server.',
        statusCode: e.response?.statusCode,
      );
    }

    final Map<String, dynamic> body;
    try {
      body = unwrapOrThrow(response.statusCode, response.data) ?? {};
    } on ApiException catch (e) {
      throw DummyOtpSessionException(e.message, statusCode: e.statusCode);
    }

    final token = body['customToken'];
    final uid = body['uid'];
    if (token is! String || token.isEmpty || uid is! String || uid.isEmpty) {
      throw DummyOtpSessionException(
        'The server did not return a sign-in token.',
        statusCode: response.statusCode,
      );
    }

    final credential =
        await _ref.read(firebaseAuthServiceProvider).signInWithCustomToken(
              token,
            );

    // The uid the client ends up holding must be the one the backend
    // provisioned — believing otherwise is precisely the bug this closes, so
    // it is asserted rather than assumed.
    final signedInUid = credential.user?.uid;
    if (signedInUid != uid) {
      throw DummyOtpSessionException(
        'Signed in as a different account than the server provisioned.',
      );
    }

    await _ref.read(localAuthSessionProvider).clear();
    return signedInUid!;
  }
}

final dummyOtpSessionStarterProvider = Provider<DummyOtpSessionStarter>(
  ApiDummyOtpSessionStarter.new,
);
