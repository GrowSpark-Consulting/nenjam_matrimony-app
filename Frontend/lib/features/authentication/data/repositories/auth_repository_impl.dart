import 'package:firebase_auth/firebase_auth.dart';

import '../models/auth_user.dart';
import '../services/firebase_auth_service.dart';
import '../services/google_auth_service.dart';

/// Nenjam Matrimony — Firebase Auth Repository (auth-only, no database)
///
/// Firebase is the authentication provider only. There is no Cloud Firestore.
/// The username is stored on the Firebase user's `displayName`; the future
/// Node.js + PostgreSQL backend will own the real profile, authenticated with
/// the Firebase ID token (JWT).
class FirebaseAuthRepository {
  FirebaseAuthRepository({
    required FirebaseAuthService auth,
    required GoogleAuthService google,
  })  : _auth = auth,
        _google = google;

  final FirebaseAuthService _auth;
  final GoogleAuthService _google;

  User? get currentUser => _auth.currentUser;
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  AuthUser? get currentAuthUser {
    final u = _auth.currentUser;
    return u == null ? null : AuthUser.fromFirebase(u);
  }

  // ─── Sign up ───────────────────────────────────────────────────────

  /// Creates the Firebase email/password account, saves the [username] on the
  /// user profile (`displayName`), and sends the email verification link.
  ///
  /// No uniqueness check is performed here — that becomes the backend's job at
  /// `POST /api/auth/register`. Throws a [FirebaseAuthException] on failure.
  Future<AuthUser> signUp({
    required String username,
    required String email,
    required String password,
  }) async {
    await _auth.createAccountWithEmail(email: email, password: password);
    await _auth.updateDisplayName(username);
    await _auth.sendEmailVerification();
    return currentAuthUser!;
  }

  // ─── Email verification ────────────────────────────────────────────

  Future<void> resendEmailVerification() => _auth.sendEmailVerification();

  /// Reloads the user and returns the fresh `emailVerified` flag.
  Future<bool> checkEmailVerified() => _auth.refreshEmailVerified();

  // ─── Phone verification (signup: link to existing account) ─────────

  Future<void> startPhoneVerification({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(PhoneAuthCredential credential) onAutoVerified,
    required void Function(FirebaseAuthException e) onFailed,
    required void Function(String verificationId) onTimeout,
    int? resendToken,
  }) {
    return _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      onCodeSent: onCodeSent,
      onAutoVerified: onAutoVerified,
      onFailed: onFailed,
      onTimeout: onTimeout,
      resendToken: resendToken,
    );
  }

  /// Confirms the SMS code by linking the phone credential to the signed-in
  /// account. Firebase then exposes the number as `currentUser.phoneNumber`,
  /// which is how we derive `phoneVerified` — no database needed.
  Future<void> confirmPhoneForSignup({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = _auth.buildPhoneCredential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    await _linkOrIgnoreAlreadyLinked(credential);
  }

  Future<void> confirmAutoPhoneForSignup(
    PhoneAuthCredential credential,
  ) async {
    await _linkOrIgnoreAlreadyLinked(credential);
  }

  /// Links the credential; tolerates only the genuinely idempotent case.
  ///
  /// `provider-already-linked` means THIS account already carries THIS number
  /// — the desired end state, reached twice because auto-retrieval and manual
  /// entry can both fire. Swallowing it is what stops that race hard-failing
  /// a member who did nothing wrong.
  ///
  /// `credential-already-in-use` is the opposite and must NOT be swallowed:
  /// the number belongs to a *different* Firebase account, so the link did not
  /// happen. Treating it as success reported a verification that never
  /// occurred — the caller advanced, `currentUser.phoneNumber` stayed null,
  /// and PostAuthDestination's "no mobile number" gate sent the member
  /// straight back to the Email + Mobile step, to try the same number and be
  /// waved through again. A soft lock, with no way to find out why.
  ///
  /// Every caller already wraps this in a try/catch that renders
  /// `AuthErrorMapper.message(e)`, which has said "already linked to another
  /// account" all along — the message simply could not be reached.
  Future<void> _linkOrIgnoreAlreadyLinked(
    PhoneAuthCredential credential,
  ) async {
    try {
      await _auth.linkPhoneCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked') return;
      rethrow;
    }
  }

  // ─── Login ─────────────────────────────────────────────────────────

  Future<AuthUser> loginWithEmail({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmail(email: email, password: password);
    return AuthUser.fromFirebase(cred.user!);
  }

  Future<AuthUser> loginWithPhoneCredential({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = _auth.buildPhoneCredential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final cred = await _auth.signInWithPhoneCredential(credential);
    return AuthUser.fromFirebase(cred.user!);
  }

  Future<AuthUser> loginWithAutoPhoneCredential(
    PhoneAuthCredential credential,
  ) async {
    final cred = await _auth.signInWithPhoneCredential(credential);
    return AuthUser.fromFirebase(cred.user!);
  }

  /// Runs the Google account picker and signs the resulting credential into
  /// Firebase. Google vouches for the address, so the returned [AuthUser]
  /// already has `emailVerified == true` and the caller can route straight
  /// into the app.
  ///
  /// Throws [GoogleSignInCancelled] when the user dismisses the picker.
  Future<AuthUser> loginWithGoogle() async {
    final cred = await _google.signIn();
    return AuthUser.fromFirebase(cred.user!);
  }

  // ─── Shared ────────────────────────────────────────────────────────

  /// Starts attaching an email address to an account that has none — the
  /// onboarding Email + Mobile step for a phone signup. See
  /// [FirebaseAuthService.startEmailUpdate] for why the address is not on
  /// the account the moment this returns.
  Future<void> startEmailUpdate(String email) => _auth.startEmailUpdate(email);

  Future<void> resetPassword(String email) => _auth.sendPasswordResetEmail(email);

  Future<void> logout() async {
    // Clear the cached Google account first, otherwise the next "Continue
    // with Google" silently reuses the previous account instead of showing
    // the picker — indistinguishable from a broken logout to the user.
    // Best-effort: a Google-side failure must never block Firebase sign-out,
    // which is what the rest of the app treats as the session boundary.
    try {
      await _google.signOut();
    } catch (_) {
      // Intentionally swallowed — see above.
    }
    await _auth.signOut();
  }
}
