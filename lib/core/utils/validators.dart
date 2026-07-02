/// Nenjam Matrimony — Form Validators
///
/// Reusable validation functions for forms throughout the app.
/// Returns null on valid input, error message string otherwise.
abstract final class Validators {
  // ─── Name ────────────────────────────────────────────────────────
  static String? name(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your name';
    }
    if (value.trim().length < 2) {
      return 'Name must be at least 2 characters';
    }
    if (value.trim().length > 50) {
      return 'Name must be less than 50 characters';
    }
    if (!RegExp(r"^[a-zA-Z\s'-]+$").hasMatch(value.trim())) {
      return 'Name can only contain letters, spaces, hyphens, and apostrophes';
    }
    return null;
  }

  // ─── Email ───────────────────────────────────────────────────────
  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email';
    }
    if (!RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$')
        .hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  // ─── Phone ───────────────────────────────────────────────────────
  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your phone number';
    }
    final cleaned = value.replaceAll(RegExp(r'[\s\-\+]'), '');
    if (cleaned.length != 10 || !RegExp(r'^\d{10}$').hasMatch(cleaned)) {
      return 'Please enter a valid 10-digit mobile number';
    }
    return null;
  }

  // ─── OTP ─────────────────────────────────────────────────────────
  static String? otp(String? value, {int length = 6}) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter the OTP';
    }
    if (value.trim().length != length) {
      return 'OTP must be $length digits';
    }
    if (!RegExp(r'^\d+$').hasMatch(value.trim())) {
      return 'OTP must contain only digits';
    }
    return null;
  }

  // ─── Password ────────────────────────────────────────────────────
  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain at least one lowercase letter';
    }
    if (!RegExp(r'\d').hasMatch(value)) {
      return 'Password must contain at least one number';
    }
    return null;
  }

  // ─── Confirm Password ───────────────────────────────────────────
  static String? confirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != password) {
      return 'Passwords do not match';
    }
    return null;
  }

  // ─── Age ─────────────────────────────────────────────────────────
  static String? age(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your age';
    }
    final age = int.tryParse(value.trim());
    if (age == null) {
      return 'Please enter a valid number';
    }
    if (age < 18) {
      return 'You must be at least 18 years old';
    }
    if (age > 100) {
      return 'Please enter a valid age';
    }
    return null;
  }

  // ─── Height ──────────────────────────────────────────────────────
  static String? height(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your height';
    }
    final height = double.tryParse(value.trim());
    if (height == null) {
      return 'Please enter a valid height';
    }
    if (height < 100 || height > 250) {
      return 'Please enter height between 100 and 250 cm';
    }
    return null;
  }

  // ─── Required ────────────────────────────────────────────────────
  static String? required(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  // ─── Bio / About ─────────────────────────────────────────────────
  static String? bio(String? value, {int maxLength = 500}) {
    if (value == null || value.trim().isEmpty) {
      return null; // Bio is optional
    }
    if (value.trim().length > maxLength) {
      return 'Bio must be less than $maxLength characters';
    }
    return null;
  }
}
