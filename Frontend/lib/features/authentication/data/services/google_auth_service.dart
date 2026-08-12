import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// TEMPORARY diagnostic logging for the Android Google Sign-In bring-up.
/// Debug-only, so it is stripped from release builds. Remove this and every
/// `_diag(...)` call once sign-in is confirmed working on a device.
///
/// Filter with: `flutter logs | findstr GSI`  (or `adb logcat | grep GSI`)
void _diag(String message) {
  if (kDebugMode) debugPrint('[GSI] $message');
}

/// Play-services failures arrive with a bracketed status code at the front of
/// the description — `[16] Account reauth failed.`, `[10] DEVELOPER_ERROR`.
/// A genuine user dismissal never carries one.
final RegExp _playServicesStatus = RegExp(r'^\s*\[\d+\]');

/// Whether [e] really represents the user backing out.
///
/// google_sign_in_android collapses *every* Credential Manager failure into
/// [GoogleSignInExceptionCode.canceled], including ones the user had no part
/// in: a device account needing re-authentication, or an app signed with a
/// key whose SHA-1 is not registered, both surface as `canceled`. Treating
/// those as a cancellation makes the button silently do nothing, which is
/// indistinguishable from a broken button — the exact symptom seen on device.
///
/// The bracketed status prefix is the only signal the plugin exposes to tell
/// the two apart, so it is what this keys on. Heuristic by necessity: if a
/// future plugin version stops emitting it, this errs toward *showing* an
/// error rather than swallowing one.
bool _isUserCancellation(GoogleSignInException e) {
  if (e.code != GoogleSignInExceptionCode.canceled) return false;
  final description = e.description;
  if (description == null || description.trim().isEmpty) return true;
  return !_playServicesStatus.hasMatch(description);
}

/// Thrown when the user dismisses the Google account picker.
///
/// Deliberately a distinct type rather than an error code: backing out is a
/// normal outcome, not a failure, and callers must return to idle without
/// showing an error. google_sign_in 7.x reports it as a
/// [GoogleSignInException] with `GoogleSignInExceptionCode.canceled` (6.x
/// returned null instead — the APIs are not interchangeable).
class GoogleSignInCancelled implements Exception {
  const GoogleSignInCancelled();

  @override
  String toString() => 'GoogleSignInCancelled';
}

/// Nenjam Matrimony — Google Sign-In Service
///
/// Runs the Google account picker and exchanges the resulting Google ID
/// token for a Firebase session. Mirrors [FirebaseAuthService]'s contract:
/// no UI, no navigation, no persistence — failures propagate for callers to
/// map centrally through `AuthErrorMapper`.
///
/// ## Android configuration this depends on
///
/// Both are already satisfied in this repo — listed so a future
/// `google-services.json` refresh does not silently break sign-in:
///
/// 1. An `oauth_client` entry with `client_type: 1` whose
///    `certificate_hash` is the SHA-1 of the signing key for the build being
///    run. A build signed with a key Firebase does not know fails with
///    `ApiException: 10` (DEVELOPER_ERROR) — the single most common cause of
///    "it works in the emulator but not on a device", because debug and
///    release keystores have different SHA-1s.
/// 2. An `oauth_client` entry with `client_type: 3` (the web client). The
///    google-services Gradle plugin turns it into
///    `R.string.default_web_client_id`, which google_sign_in_android reads
///    automatically as the `serverClientId`. Without it the plugin throws
///    "serverClientId must be provided on Android", and no ID token is
///    issued.
///
/// [initialize] is therefore called with no arguments: passing
/// `serverClientId` here would hardcode a second copy of a value that
/// already lives in `google-services.json` and would override it. iOS will
/// need its own `GoogleService-Info.plist` plus the reversed-client-id URL
/// scheme before this works there.
class GoogleAuthService {
  GoogleAuthService(this._auth, this._googleSignIn);

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  bool _initialized = false;

  /// v7 requires `initialize()` to complete before any other call. It is
  /// idempotent from our side but does platform work, so it runs once.
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      await _googleSignIn.initialize();
      _diag('initialize() OK');
    } catch (e) {
      // "serverClientId must be provided on Android" surfaces here when
      // google-services.json has no client_type 3 entry.
      _diag('initialize() FAILED: ${e.runtimeType} — $e');
      rethrow;
    }
    _initialized = true;
  }

  /// Signs in with Google and returns the resulting Firebase credential.
  ///
  /// Throws [GoogleSignInCancelled] if the user dismissed the picker, and
  /// [FirebaseAuthException] for anything Firebase rejects (for example
  /// `account-exists-with-different-credential` when the same address
  /// already has a password account).
  Future<UserCredential> signIn() async {
    await _ensureInitialized();

    final GoogleSignInAccount account;
    try {
      _diag('authenticate() starting…');
      account = await _googleSignIn.authenticate();
      _diag('authenticate() OK — account id=${account.id}, '
          'email=${account.email}');
    } on GoogleSignInException catch (e) {
      // `details` is where the Android Credential Manager failure lands —
      // e.g. GetCredentialException / ApiException: 10 (DEVELOPER_ERROR),
      // which means the signing SHA-1 is not registered for this package.
      _diag('authenticate() GoogleSignInException'
          '\n    code:        ${e.code}'
          '\n    description: ${e.description}'
          '\n    details:     ${e.details}');
      if (_isUserCancellation(e)) {
        _diag('treated as user cancellation — staying silent');
        throw const GoogleSignInCancelled();
      }
      _diag('treated as a REAL failure — surfacing an error to the user');
      rethrow;
    } catch (e) {
      _diag('authenticate() unexpected ${e.runtimeType} — $e');
      rethrow;
    }

    // v7 exposes only an ID token here; access tokens moved to the separate
    // authorization client. Firebase needs nothing else for Google.
    final idToken = account.authentication.idToken;

    // Diagnostic only. `authorizationForScopes` is the NON-interactive
    // variant — it returns null rather than prompting, so logging it cannot
    // change the sign-in flow. Firebase does not use this token.
    String? accessToken;
    try {
      final authz =
          await account.authorizationClient.authorizationForScopes(['email']);
      accessToken = authz?.accessToken;
    } catch (e) {
      _diag('authorizationForScopes threw ${e.runtimeType} — $e');
    }

    _diag('tokens — idToken != null: ${idToken != null}'
        ' (len ${idToken?.length ?? 0}),'
        ' accessToken != null: ${accessToken != null}');

    if (idToken == null) {
      _diag('ABORT: idToken is null — google-services.json is missing a '
          'client_type 3 (web) entry, or the app was signed with a key whose '
          'SHA-1 is not registered.');
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'Google returned no ID token — check that '
            'google-services.json still contains a client_type 3 entry.',
      );
    }

    try {
      _diag('calling FirebaseAuth.signInWithCredential…');
      final cred = await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      _diag('signInWithCredential OK — uid=${cred.user?.uid}, '
          'isNewUser=${cred.additionalUserInfo?.isNewUser}');
      return cred;
    } on FirebaseAuthException catch (e) {
      _diag('signInWithCredential FirebaseAuthException'
          '\n    code:    ${e.code}'
          '\n    message: ${e.message}');
      rethrow;
    }
  }

  /// Drops the cached Google account so the next sign-in shows the picker
  /// again rather than silently reusing the last account.
  Future<void> signOut() async {
    await _ensureInitialized();
    await _googleSignIn.signOut();
  }
}
