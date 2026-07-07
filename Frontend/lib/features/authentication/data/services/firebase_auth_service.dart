import 'package:firebase_auth/firebase_auth.dart';

/// Nenjam Matrimony — Firebase Authentication Service
///
/// Wraps [FirebaseAuth] for email/password + phone auth. No UI, no navigation,
/// no Firestore — just the auth SDK surface the app needs. Errors are allowed
/// to propagate as [FirebaseAuthException] so callers can map them centrally.
class FirebaseAuthService {
  FirebaseAuthService(this._auth);

  final FirebaseAuth _auth;

  // ─── Session ───────────────────────────────────────────────────────
  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<void> signOut() => _auth.signOut();

  // ─── Email / Password ──────────────────────────────────────────────

  /// Creates an account with email + password. The password is handed
  /// straight to Firebase and never stored or logged by the app.
  Future<UserCredential> createAccountWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Stores the chosen username on the Firebase user (`displayName`) so it
  /// persists across sessions without a database, then reloads.
  Future<void> updateDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.updateDisplayName(name);
    await user.reload();
  }

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  /// Reloads the user from the server and returns the fresh
  /// `emailVerified` state. Needed because the local [User] is cached and
  /// won't reflect a link tapped in the inbox until reloaded.
  Future<bool> refreshEmailVerified() async {
    await _auth.currentUser?.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  // ─── Phone / OTP ───────────────────────────────────────────────────

  /// Starts phone verification. Firebase drives the flow via callbacks:
  ///
  /// - [onCodeSent] — SMS dispatched; keep the `verificationId` to verify.
  /// - [onAutoVerified] — Android auto-retrieval completed a credential.
  /// - [onFailed] — number invalid, quota exceeded, etc.
  /// - [onTimeout] — auto-retrieval window elapsed.
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(PhoneAuthCredential credential) onAutoVerified,
    required void Function(FirebaseAuthException e) onFailed,
    required void Function(String verificationId) onTimeout,
    int? resendToken,
  }) {
    return _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      forceResendingToken: resendToken,
      verificationCompleted: onAutoVerified,
      verificationFailed: onFailed,
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: onTimeout,
    );
  }

  PhoneAuthCredential buildPhoneCredential({
    required String verificationId,
    required String smsCode,
  }) {
    return PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
  }

  /// Links a verified phone credential to the *current* (email) account so
  /// the same account can later log in by phone. Used during signup.
  Future<void> linkPhoneCredential(PhoneAuthCredential credential) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'requires-recent-login',
        message: 'No signed-in user to link the phone number to.',
      );
    }
    await user.linkWithCredential(credential);
  }

  /// Signs in with a verified phone credential. Used for phone-OTP login.
  Future<UserCredential> signInWithPhoneCredential(
    PhoneAuthCredential credential,
  ) {
    return _auth.signInWithCredential(credential);
  }
}
