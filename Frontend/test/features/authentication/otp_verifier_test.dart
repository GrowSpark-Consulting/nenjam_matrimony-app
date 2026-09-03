import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/authentication/domain/services/otp_verifier.dart';

/// Pins the development OTP contract: **any non-empty code is accepted, and
/// nothing is sent.**
///
/// This is what keeps a real SMS out of the login and onboarding flows.
/// Firebase Phone Auth needs SMS billing enabled; calling it from onboarding
/// failed with BILLING_NOT_ENABLED and blocked the last step entirely. The
/// seam stays so real verification can be restored by swapping the provider
/// override.
void main() {
  const verifier = MockOtpVerifier();

  test('sending a code contacts nothing and cannot fail', () async {
    await verifier.send('+919876543210');
  });

  test('any non-empty code is accepted, whatever its length', () async {
    for (final code in ['123456', '000000', '111111', '9999', '1234', '7']) {
      expect(
        await verifier.verify(code),
        isTrue,
        reason: '"$code" is non-empty and must be accepted',
      );
    }
  });

  test('surrounding whitespace does not change the answer', () async {
    expect(await verifier.verify(' 1234 '), isTrue);
  });

  test('only an empty code is rejected', () async {
    for (final code in ['', '   ', '\t']) {
      expect(
        await verifier.verify(code),
        isFalse,
        reason: 'an empty code is the user not having answered',
      );
    }
  });

  test('codeLength is a UI hint, not a rule verify enforces', () async {
    const six = MockOtpVerifier(codeLength: 6);
    expect(six.codeLength, 6);
    expect(await six.verify('123456'), isTrue);
    // Shorter than the boxes drawn, and still accepted — nothing is being
    // sent, so no length is more real than another.
    expect(await six.verify('1234'), isTrue);
  });
}
