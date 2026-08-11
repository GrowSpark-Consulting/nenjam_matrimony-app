import '../l10n/app_l10n.dart';

/// Nenjam Matrimony — Form Validators
///
/// Reusable validation functions for forms throughout the app.
/// Returns null on valid input, error message string otherwise.
///
/// Messages are localized through [AppL10n.current] rather than a passed-in
/// `AppLocalizations`: these are used as bare tear-offs
/// (`validator: Validators.email`), and `TextFormField` hands its validator
/// only the field value — there is no `BuildContext` at the call site. The
/// validation *rules* below are unchanged; only the returned strings are.
abstract final class Validators {
  // ─── Name ────────────────────────────────────────────────────────
  static String? name(String? value) {
    final l10n = AppL10n.current;
    if (value == null || value.trim().isEmpty) {
      return l10n.validatorNameRequired;
    }
    if (value.trim().length < 2) {
      return l10n.validatorNameTooShort;
    }
    if (value.trim().length > 50) {
      return l10n.validatorNameTooLong;
    }
    if (!RegExp(r"^[a-zA-Z\s'-]+$").hasMatch(value.trim())) {
      return l10n.validatorNameInvalid;
    }
    return null;
  }

  // ─── Username ────────────────────────────────────────────────────
  /// Username rules: minimum 3 characters, letters/numbers/underscore only,
  /// no spaces or other special symbols. Must start with a letter.
  static String? username(String? value) {
    final l10n = AppL10n.current;
    if (value == null || value.trim().isEmpty) {
      return l10n.validatorUsernameRequired;
    }
    final v = value.trim();
    if (v.length < 3) {
      return l10n.validatorUsernameTooShort;
    }
    if (v.length > 20) {
      return l10n.validatorUsernameTooLong;
    }
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(v)) {
      return l10n.validatorUsernameInvalid;
    }
    return null;
  }

  // ─── Email ───────────────────────────────────────────────────────
  static String? email(String? value) {
    final l10n = AppL10n.current;
    if (value == null || value.trim().isEmpty) {
      return l10n.validatorEmailRequired;
    }
    if (!RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$')
        .hasMatch(value.trim())) {
      return l10n.validatorEmailInvalid;
    }
    return null;
  }

  // ─── Phone ───────────────────────────────────────────────────────
  static String? phone(String? value) {
    final l10n = AppL10n.current;
    if (value == null || value.trim().isEmpty) {
      return l10n.validatorPhoneRequired;
    }
    final cleaned = value.replaceAll(RegExp(r'[\s\-\+]'), '');
    if (cleaned.length != 10 || !RegExp(r'^\d{10}$').hasMatch(cleaned)) {
      return l10n.validatorPhoneInvalid;
    }
    return null;
  }

  // ─── OTP ─────────────────────────────────────────────────────────
  static String? otp(String? value, {int length = 6}) {
    final l10n = AppL10n.current;
    if (value == null || value.trim().isEmpty) {
      return l10n.validatorOtpRequired;
    }
    if (value.trim().length != length) {
      return l10n.validatorOtpLength(length);
    }
    if (!RegExp(r'^\d+$').hasMatch(value.trim())) {
      return l10n.validatorOtpDigitsOnly;
    }
    return null;
  }

  // ─── Password ────────────────────────────────────────────────────
  static String? password(String? value) {
    final l10n = AppL10n.current;
    if (value == null || value.isEmpty) {
      return l10n.validatorPasswordRequired;
    }
    if (value.length < 8) {
      return l10n.validatorPasswordTooShort;
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return l10n.validatorPasswordUppercase;
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return l10n.validatorPasswordLowercase;
    }
    if (!RegExp(r'\d').hasMatch(value)) {
      return l10n.validatorPasswordNumber;
    }
    return null;
  }

  // ─── Confirm Password ───────────────────────────────────────────
  static String? confirmPassword(String? value, String password) {
    final l10n = AppL10n.current;
    if (value == null || value.isEmpty) {
      return l10n.validatorConfirmPasswordRequired;
    }
    if (value != password) {
      return l10n.validatorPasswordsMismatch;
    }
    return null;
  }

  // ─── Age ─────────────────────────────────────────────────────────
  static String? age(String? value) {
    final l10n = AppL10n.current;
    if (value == null || value.trim().isEmpty) {
      return l10n.validatorAgeRequired;
    }
    final age = int.tryParse(value.trim());
    if (age == null) {
      return l10n.validatorNumberInvalid;
    }
    if (age < 18) {
      return l10n.validatorAgeMinimum;
    }
    if (age > 100) {
      return l10n.validatorAgeInvalid;
    }
    return null;
  }

  // ─── Height ──────────────────────────────────────────────────────
  static String? height(String? value) {
    final l10n = AppL10n.current;
    if (value == null || value.trim().isEmpty) {
      return l10n.validatorHeightRequired;
    }
    final height = double.tryParse(value.trim());
    if (height == null) {
      return l10n.validatorHeightInvalid;
    }
    if (height < 100 || height > 250) {
      return l10n.validatorHeightRange;
    }
    return null;
  }

  // ─── Required ────────────────────────────────────────────────────
  /// [fieldName] is nullable rather than defaulting to a literal, since a
  /// default value must be a compile-time constant and the localized
  /// "This field" can only be resolved at call time.
  static String? required(String? value, [String? fieldName]) {
    final l10n = AppL10n.current;
    if (value == null || value.trim().isEmpty) {
      return l10n.validatorFieldRequired(fieldName ?? l10n.commonThisField);
    }
    return null;
  }

  // ─── Bio / About ─────────────────────────────────────────────────
  static String? bio(String? value, {int maxLength = 500}) {
    if (value == null || value.trim().isEmpty) {
      return null; // Bio is optional
    }
    if (value.trim().length > maxLength) {
      return AppL10n.current.validatorBioTooLong(maxLength);
    }
    return null;
  }
}
