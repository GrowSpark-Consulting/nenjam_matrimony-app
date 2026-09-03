import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/authentication/domain/services/login_identifier.dart';

/// Pins how the one "email or mobile number" field is read, because that
/// decision is what picks the credential check that follows.
void main() {
  group('classify', () {
    test('an address is an email attempt', () {
      expect(
        LoginIdentifier.classify('name@example.com'),
        LoginIdentifierKind.email,
      );
      expect(
        LoginIdentifier.classify('  Name@Example.COM  '),
        LoginIdentifierKind.email,
      );
    });

    test('a malformed address is still an email attempt, not a number', () {
      // Otherwise a typo'd address falls through to the mobile path and the
      // user is told their email is a bad phone number.
      expect(
        LoginIdentifier.classify('name@'),
        LoginIdentifierKind.email,
      );
    });

    test('national and international numbers are mobile', () {
      for (final value in [
        '9876543210',
        '98765 43210',
        '+91 98765 43210',
        '919876543210',
      ]) {
        expect(
          LoginIdentifier.classify(value),
          LoginIdentifierKind.mobile,
          reason: '"$value" is a mobile number',
        );
      }
    });

    test('empty or unrecognisable input is unknown', () {
      for (final value in ['', '   ', '12345', 'arun']) {
        expect(
          LoginIdentifier.classify(value),
          LoginIdentifierKind.unknown,
          reason: '"$value" is neither',
        );
      }
    });
  });

  group('normalize', () {
    test('emails are trimmed and lowercased, as Firebase stores them', () {
      expect(
        LoginIdentifier.normalizeEmail('  Name@Example.COM '),
        'name@example.com',
      );
    });

    test('a bare national number gets the default dial code', () {
      expect(
        LoginIdentifier.normalizeMobile('98765 43210'),
        '+919876543210',
      );
    });

    test('an already-international number keeps its own code', () {
      expect(LoginIdentifier.normalizeMobile('+1 415 555 0123'), '+14155550123');
      expect(LoginIdentifier.normalizeMobile('919876543210'), '+919876543210');
    });
  });
}
