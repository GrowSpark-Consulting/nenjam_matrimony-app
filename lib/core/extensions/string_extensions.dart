/// String utility extensions for common transformations and checks.
extension StringExtensions on String {
  /// Capitalizes the first letter.
  String get capitalize =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';

  /// Converts to Title Case.
  String get titleCase => split(' ')
      .map((word) => word.capitalize)
      .join(' ');

  /// Returns initials (max 2 characters).
  String get initials {
    final parts = trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  /// Masks a phone number: +91 9****5678
  String get maskedPhone {
    if (length < 6) return this;
    const visible = 4;
    return '${substring(0, length - visible).replaceAll(RegExp(r'\d'), '*')}${substring(length - visible)}';
  }

  /// Masks an email: j***@example.com
  String get maskedEmail {
    final parts = split('@');
    if (parts.length != 2) return this;
    final name = parts[0];
    if (name.length <= 1) return this;
    return '${name[0]}${'*' * (name.length - 1)}@${parts[1]}';
  }

  /// Checks if string is a valid email.
  bool get isValidEmail =>
      RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(this);

  /// Checks if string is a valid Indian phone number.
  bool get isValidPhone =>
      RegExp(r'^[6-9]\d{9}$').hasMatch(replaceAll(RegExp(r'[\s\-\+]'), ''));

  /// Removes all whitespace.
  String get removeWhitespace => replaceAll(RegExp(r'\s'), '');

  /// Truncates with ellipsis.
  String truncate(int maxLength) {
    if (length <= maxLength) return this;
    return '${substring(0, maxLength)}...';
  }
}

/// Nullable string extensions.
extension NullableStringExtensions on String? {
  /// Returns true if string is null or empty.
  bool get isNullOrEmpty => this == null || this!.isEmpty;

  /// Returns true if string is not null and not empty.
  bool get isNotNullOrEmpty => !isNullOrEmpty;

  /// Returns the string or a default value.
  String orDefault([String defaultValue = '']) => this ?? defaultValue;
}
