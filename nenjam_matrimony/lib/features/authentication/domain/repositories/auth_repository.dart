/// Nenjam Matrimony — Authentication Repository Contract
///
/// Pure abstract Dart interface defining the authentication capabilities.
/// Concrete implementations live in `data/repositories/`.
/// No Dio, no HTTP, no Flutter imports — pure business contract.
///
/// Per PROJECT_RULES.md §9: Repositories must contain interfaces.
/// Implementation belongs inside data. No API logic inside contracts.
library;

import '../models/auth_failure.dart';

/// A simple functional Result type for auth operations.
///
/// Usage:
/// ```dart
/// final result = await repo.loginWithPhone('+91 98765 43210');
/// result.fold(
///   (failure) => print(failure.message),
///   (token) => print('Token: $token'),
/// );
/// ```
typedef AuthResult<T> = ({T? data, AuthFailure? failure});

/// Extension for ergonomic fold-pattern on [AuthResult].
extension AuthResultX<T> on AuthResult<T> {
  bool get isSuccess => failure == null;
  bool get isFailure => failure != null;

  R fold<R>(
    R Function(AuthFailure failure) onFailure,
    R Function(T data) onSuccess,
  ) {
    if (isFailure) return onFailure(failure!);
    return onSuccess(data as T);
  }
}

// ─── Value Objects ──────────────────────────────────────────────────────────

/// Represents an authenticated session token pair.
final class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });
}

/// Represents an OTP send confirmation.
final class OtpSentResult {
  final String maskedDestination;
  final DateTime expiresAt;
  const OtpSentResult({
    required this.maskedDestination,
    required this.expiresAt,
  });
}

// ─── Repository Contract ────────────────────────────────────────────────────

/// Abstract authentication repository.
///
/// Prepared for future Firebase phone auth and email/password implementations.
/// No backend calls exist yet — this is the domain interface only.
abstract class AuthRepository {
  /// Sends OTP to the provided phone number.
  ///
  /// [phoneNumber] — E.164 format e.g. `+919876543210`.
  Future<AuthResult<OtpSentResult>> sendPhoneOtp(String phoneNumber);

  /// Sends OTP to the provided email address.
  ///
  /// [email] — Validated email address.
  Future<AuthResult<OtpSentResult>> sendEmailOtp(String email);

  /// Verifies the 6-digit OTP and returns session tokens on success.
  ///
  /// [identifier] — Phone or email that received the OTP.
  /// [otp] — 6-digit code entered by user.
  Future<AuthResult<AuthTokens>> verifyOtp({
    required String identifier,
    required String otp,
  });

  /// Registers a new account using phone + password.
  ///
  /// [phoneNumber] — E.164 format phone number.
  /// [password] — Raw password (will be hashed by implementation).
  /// [email] — Optional email for dual verification.
  Future<AuthResult<AuthTokens>> registerWithPhone({
    required String phoneNumber,
    required String password,
    String? email,
  });

  /// Logs in with phone number and password.
  ///
  /// [phoneNumber] — E.164 format phone number.
  /// [password] — Raw password.
  Future<AuthResult<AuthTokens>> loginWithPassword({
    required String phoneNumber,
    required String password,
  });

  /// Refreshes the access token using the refresh token.
  ///
  /// [refreshToken] — The refresh token from a previous session.
  Future<AuthResult<AuthTokens>> refreshAccessToken(String refreshToken);

  /// Logs out the current session on server and clears local tokens.
  Future<AuthResult<void>> logout();

  /// Returns `true` if a valid session exists locally.
  Future<bool> isAuthenticated();
}
