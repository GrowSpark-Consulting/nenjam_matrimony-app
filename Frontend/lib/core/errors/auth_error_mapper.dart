import 'package:firebase_auth/firebase_auth.dart';

/// Nenjam Matrimony — Firebase Auth Error Mapper
///
/// Translates raw [FirebaseAuthException] codes into friendly, user-facing
/// messages. Never surface raw Firebase error strings to end users — they
/// leak implementation detail and are not localized.
///
/// Per PROJECT_RULES: all auth failures presented to the user must be
/// human-readable. Keep this the single source of truth for auth copy.
abstract final class AuthErrorMapper {
  /// Maps a caught error to a friendly message.
  ///
  /// Accepts [Object] so callers can pass anything from a `catch`.
  static String message(Object error) {
    if (error is FirebaseAuthException) {
      return _fromCode(error.code, error.message);
    }
    if (error is UsernameTakenException) {
      return 'That username is already taken. Please choose another.';
    }
    return 'Something went wrong. Please try again.';
  }

  static String _fromCode(String code, String? fallback) {
    switch (code) {
      // ─── Sign up / credentials ─────────────────────────────────────
      case 'email-already-in-use':
        return 'An account already exists for this email. Try logging in.';
      case 'invalid-email':
        return 'That email address looks invalid. Please check it.';
      case 'weak-password':
        return 'Your password is too weak. Use at least 8 characters with '
            'upper, lower, a number and a symbol.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled. Please contact support.';

      // ─── Login ─────────────────────────────────────────────────────
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password. Please try again.';

      // ─── Phone / OTP ───────────────────────────────────────────────
      case 'invalid-verification-code':
        return 'The OTP you entered is incorrect. Please try again.';
      case 'invalid-verification-id':
      case 'session-expired':
        return 'This code has expired. Please request a new OTP.';
      case 'invalid-phone-number':
        return 'That phone number looks invalid. Please check it.';
      case 'missing-phone-number':
        return 'Please enter a phone number.';
      case 'credential-already-in-use':
      case 'account-exists-with-different-credential':
        return 'This phone number is already linked to another account.';

      // ─── Throttling / network ──────────────────────────────────────
      case 'too-many-requests':
        return 'Too many attempts. Please wait a while and try again.';
      case 'network-request-failed':
        return 'Network error. Please check your connection and try again.';
      case 'requires-recent-login':
        return 'Please log in again to complete this action.';

      default:
        return fallback ?? 'Something went wrong. Please try again.';
    }
  }
}

/// Thrown when a chosen username already exists in Firestore.
class UsernameTakenException implements Exception {
  const UsernameTakenException();
  @override
  String toString() => 'UsernameTakenException';
}
