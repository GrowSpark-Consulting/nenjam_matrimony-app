/// What the user typed into the one "email or mobile number" field.
enum LoginIdentifierKind { email, mobile, unknown }

/// Reads a login identifier and decides which credential path it belongs to.
///
/// One place, so the password screen does not have to know the rules and
/// the two paths can never disagree about what "9876543210" is.
abstract final class LoginIdentifier {
  /// Anything containing an `@` is treated as an email attempt — including
  /// a malformed one, which must fail validation as a *bad email* rather
  /// than silently fall through to the mobile path and fail as a bad
  /// number.
  static LoginIdentifierKind classify(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return LoginIdentifierKind.unknown;
    if (value.contains('@')) return LoginIdentifierKind.email;
    if (_mobilePattern.hasMatch(_digits(value))) {
      return LoginIdentifierKind.mobile;
    }
    return LoginIdentifierKind.unknown;
  }

  /// Trimmed and lowercased — the same rule
  /// `ApiAccountAvailabilityChecker.normalizeEmail` and Firebase itself
  /// apply, so a stray space from an autofill cannot read as a different
  /// account.
  static String normalizeEmail(String raw) => raw.trim().toLowerCase();

  /// The number in E.164, using [defaultDialCode] when the user typed a
  /// bare national number — which is what the mobile field elsewhere in the
  /// app produces, so both paths hand the backend the same shape.
  static String normalizeMobile(String raw, {String defaultDialCode = '+91'}) {
    final trimmed = raw.trim();
    final digits = _digits(trimmed);
    if (trimmed.startsWith('+')) return '+$digits';
    if (digits.length > 10) return '+$digits';
    return '$defaultDialCode$digits';
  }

  static String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');

  /// 10 digits (the national form the app collects) or a 11–15 digit
  /// international number.
  static final RegExp _mobilePattern = RegExp(r'^\d{10}$|^\d{11,15}$');
}
