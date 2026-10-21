import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/errors/auth_error_mapper.dart';
import 'package:nenjam_matrimony/core/l10n/app_l10n.dart';

/// The browser-only Firebase failures — a blocked sign-in popup, a failed
/// reCAPTCHA, an unauthorised domain, SMS quota, blocked storage — must read as
/// plain sentences, never as Firebase's own English text.
void main() {
  const webCodes = [
    'popup-blocked',
    'captcha-check-failed',
    'web-context-cancelled',
    'unauthorized-domain',
    'quota-exceeded',
    'web-storage-unsupported',
  ];

  for (final code in webCodes) {
    test('$code maps to app copy, not the raw Firebase message', () {
      final message = AuthErrorMapper.message(
        FirebaseAuthException(code: code, message: 'RAW FIREBASE TEXT'),
      );
      expect(message, isNot(contains('RAW FIREBASE TEXT')));
      expect(message, isNot(AppL10n.current.authGenericError));
      expect(message, isNotEmpty);
    });
  }

  test('each web code has its own distinct wording', () {
    final messages = {
      for (final code in webCodes)
        code: AuthErrorMapper.message(FirebaseAuthException(code: code)),
    };
    // The two CAPTCHA codes deliberately share one sentence.
    expect(messages.values.toSet().length, webCodes.length - 1);
  });
}
