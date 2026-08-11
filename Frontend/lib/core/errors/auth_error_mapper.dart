import 'package:firebase_auth/firebase_auth.dart';
import '../l10n/app_l10n.dart';

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
    final l10n = AppL10n.current;
    if (error is FirebaseAuthException) {
      return _fromCode(error.code, error.message);
    }
    if (error is UsernameTakenException) {
      return l10n.authErrorUsernameTaken;
    }
    return l10n.authGenericError;
  }

  static String _fromCode(String code, String? fallback) {
    final l10n = AppL10n.current;
    switch (code) {
      // ─── Sign up / credentials ─────────────────────────────────────
      case 'email-already-in-use':
        return l10n.authErrorEmailInUse;
      case 'invalid-email':
        return l10n.authErrorEmailInvalid;
      case 'weak-password':
        return l10n.authErrorWeakPassword;
      case 'operation-not-allowed':
        return l10n.authErrorMethodDisabled;

      // ─── Login ─────────────────────────────────────────────────────
      case 'user-disabled':
        return l10n.authErrorAccountDisabled;
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return l10n.authErrorWrongCredentials;

      // ─── Phone / OTP ───────────────────────────────────────────────
      case 'invalid-verification-code':
        return l10n.authErrorOtpIncorrect;
      case 'invalid-verification-id':
      case 'session-expired':
        return l10n.authErrorOtpExpired;
      case 'invalid-phone-number':
        return l10n.authErrorPhoneInvalid;
      case 'missing-phone-number':
        return l10n.authErrorPhoneMissing;
      case 'credential-already-in-use':
      case 'account-exists-with-different-credential':
        return l10n.authErrorPhoneLinked;

      // ─── Throttling / network ──────────────────────────────────────
      case 'too-many-requests':
        return l10n.authErrorTooManyAttempts;
      case 'network-request-failed':
        return l10n.authErrorNetwork;
      case 'requires-recent-login':
        return l10n.authErrorReauthRequired;

      default:
        return fallback ?? l10n.authGenericError;
    }
  }
}

/// Thrown when a chosen username already exists in Firestore.
class UsernameTakenException implements Exception {
  const UsernameTakenException();
  @override
  String toString() => 'UsernameTakenException';
}
