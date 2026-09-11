import 'package:firebase_auth/firebase_auth.dart';

/// Nenjam Matrimony — Firebase JWT / ID Token Service
///
/// Bridges Firebase Authentication to the future Node.js backend. The Firebase
/// ID token is a signed JWT the backend verifies with the Firebase Admin SDK
/// before creating/reading the PostgreSQL user record.
///
/// Usage (future):
/// ```dart
/// final token = await tokenService.getFirebaseToken();
/// dio.options.headers['Authorization'] = 'Bearer $token';
/// ```
class AuthTokenService {
  AuthTokenService(this._auth);

  final FirebaseAuth _auth;

  /// How long to wait for Firebase to restore a persisted session before
  /// concluding there isn't one.
  ///
  /// Restoring reads the credential off disk and is normally near-instant;
  /// this only has to be longer than that, not long enough to cover a slow
  /// network. It is a readiness wait, not a request timeout.
  static const Duration _sessionRestoreTimeout = Duration(seconds: 5);

  /// Returns the current user's Firebase ID token (JWT), or `null` if signed
  /// out. Firebase auto-refreshes tokens; pass [forceRefresh] to mint a fresh
  /// one (e.g. after custom claims change).
  ///
  /// `currentUser` is populated asynchronously at startup: for a short window
  /// after launch it is null even for a member with a perfectly good
  /// persisted session. Reading it synchronously (which is what this used to
  /// do) meant any request issued in that window went out with NO
  /// Authorization header, took a 401, and — because the retry's refresh read
  /// the same still-null `currentUser` — was reported to AuthInterceptor as
  /// "this session cannot be recovered", which signs the member out. A cold
  /// start that raced the restore therefore ended in a spurious logout rather
  /// than a request.
  ///
  /// So when there is no user yet, wait for `authStateChanges` to emit.
  /// Firebase replays the current value to a new subscriber, so this returns
  /// immediately once restore has finished, and immediately with `null` for a
  /// genuinely signed-out member — the wait only materialises during the
  /// startup window it exists to cover. Bounded, so a Firebase that never
  /// reports readiness degrades to "no token" instead of hanging the caller.
  ///
  /// That last guarantee was only true of the intent, not of the code: the
  /// wait used `firstWhere((user) => user != null)`, which discards the very
  /// `null` that says "signed out" and blocked for the full timeout instead.
  /// See `_awaitRestoredUser`.
  Future<String?> getFirebaseToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser ?? await _awaitRestoredUser();
    if (user == null) return null;
    return user.getIdToken(forceRefresh);
  }

  Future<User?> _awaitRestoredUser() async {
    try {
      // `.first`, NOT `firstWhere((user) => user != null)`.
      //
      // authStateChanges() replays the restored state to each new subscriber,
      // and for a genuinely signed-out member that state is `null`. Waiting
      // for a non-null user therefore refused the very emission that answers
      // the question, and — since the stream stays open — blocked for the
      // whole `_sessionRestoreTimeout` before returning null anyway.
      //
      // AuthInterceptor awaits this on every request, and onboarding runs
      // entirely signed out (auth is the last step), so each location request
      // sat here for 5s before it was even sent. Measured: 5,029ms with
      // firstWhere vs 2ms with first; a restored user still arrives in the
      // first emission, so the signed-in path is unchanged.
      return await _auth
          .authStateChanges()
          .first
          .timeout(_sessionRestoreTimeout);
    } catch (_) {
      // Timed out, or the stream closed without emitting at all — both mean
      // "no session", which is exactly what null already says.
      return null;
    }
  }

  /// Convenience for the `Authorization` header value, or `null` if signed out.
  Future<String?> getBearerHeader() async {
    final token = await getFirebaseToken();
    return token == null ? null : 'Bearer $token';
  }
}
