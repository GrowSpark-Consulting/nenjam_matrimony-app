/// Nenjam Matrimony — Authentication Failure Models
///
/// Sealed hierarchy of typed failures for the authentication domain.
/// All repository methods should return `Result<T, AuthFailure>` instead
/// of throwing raw exceptions, per PROJECT_RULES.md §11.
library;

/// Base sealed class for all auth-related failures.
sealed class AuthFailure {
  final String message;
  final int? statusCode;
  const AuthFailure(this.message, [this.statusCode]);
}

/// Thrown when OTP or credential request fails due to network issues.
class NetworkAuthFailure extends AuthFailure {
  const NetworkAuthFailure([
    super.message = 'Network error. Please check your connection.',
    super.statusCode,
  ]);
}

/// Thrown when provided credentials (phone/email + password) are invalid.
class InvalidCredentialsFailure extends AuthFailure {
  const InvalidCredentialsFailure([
    super.message = 'Invalid credentials. Please try again.',
    super.statusCode = 401,
  ]);
}

/// Thrown when the 6-digit OTP has expired (> 10 minutes old).
class OtpExpiredFailure extends AuthFailure {
  const OtpExpiredFailure([
    super.message = 'OTP has expired. Please request a new one.',
    super.statusCode = 410,
  ]);
}

/// Thrown when the 6-digit OTP is incorrect.
class InvalidOtpFailure extends AuthFailure {
  const InvalidOtpFailure([
    super.message = 'Incorrect OTP. Please check and try again.',
    super.statusCode = 422,
  ]);
}

/// Thrown when the phone number or email is already registered.
class AccountAlreadyExistsFailure extends AuthFailure {
  const AccountAlreadyExistsFailure([
    super.message = 'An account with this contact already exists.',
    super.statusCode = 409,
  ]);
}

/// Thrown when account is suspended or banned by moderation.
class AccountSuspendedFailure extends AuthFailure {
  const AccountSuspendedFailure([
    super.message = 'Your account has been suspended. Contact support.',
    super.statusCode = 403,
  ]);
}

/// Fallback for any unexpected authentication error.
class UnknownAuthFailure extends AuthFailure {
  const UnknownAuthFailure([
    super.message = 'An unexpected error occurred. Please try again.',
    super.statusCode,
  ]);
}
