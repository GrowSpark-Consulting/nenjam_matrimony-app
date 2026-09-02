import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/authentication/domain/services/otp_verifier.dart';

/// Pins the development OTP contract: **any numeric code of the expected
/// length is accepted, and nothing is sent.**
///
/// This is what keeps a real SMS out of the onboarding flow. Firebase Phone
/// Auth needs SMS billing enabled; calling it from onboarding failed with
/// BILLING_NOT_ENABLED and blocked the last step entirely. The seam stays so
/// real verification can be restored by swapping the provider override.
void main() {
  final verifier = MockOtpVerifier();

  test('sending a code contacts nothing and cannot fail', () async {
    await verifier.send('+919876543210');
  });

  test('any numeric code of the right length is accepted', () async {
    for (final code in ['1234', '0000', '5678', '1111', '9999', '4321']) {
      expect(
        await verifier.verify(code),
        isTrue,
        reason: '"$code" is four digits and must be accepted',
      );
    }
  });

  test('surrounding whitespace does not change the answer', () async {
    expect(await verifier.verify(' 1234 '), isTrue);
  });

  test('a wrong length or a non-numeric code is rejected', () async {
    for (final code in ['', '12', '123', '12345', 'abcd', '12a4', '１２３４']) {
      expect(
        await verifier.verify(code),
        isFalse,
        reason: '"$code" is not four digits and must be rejected',
      );
    }
  });

  test('the code length the UI asks for is configurable', () async {
    final six = MockOtpVerifier(codeLength: 6);
    expect(six.codeLength, 6);
    expect(await six.verify('123456'), isTrue);
    expect(await six.verify('1234'), isFalse);
  });
}
