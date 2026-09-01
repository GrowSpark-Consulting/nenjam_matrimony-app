import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How the onboarding OTP step verifies a code.
///
/// One seam, so the mock below can be swapped for the real Firebase path
/// without touching a screen. The onboarding step talks to this and nothing
/// else; the real phone-auth stack (`PhoneAuthController`,
/// `AuthRepository.confirmPhoneForSignup`) is untouched and still used by the
/// sign-up and login phone screens.
abstract interface class OtpVerifier {
  /// Starts verification for [phoneE164]. The mock sends nothing.
  Future<void> send(String phoneE164);

  /// Whether [code] is accepted. Never throws for a wrong code — a wrong
  /// code is an answer, not a failure.
  Future<bool> verify(String code);

  /// Digits the UI should ask for.
  int get codeLength;
}

/// Development verifier: accepts **any** numeric code of the expected
/// length and contacts nothing.
///
/// Deliberately permissive rather than a single magic value — nobody should
/// have to memorise a code to walk the flow, and a fixed one invites being
/// hardcoded into a screen. Screens ask [OtpVerifier.verify] instead of
/// comparing strings themselves, so turning real verification back on is a
/// one-line change in [otpVerifierProvider] with no screen changes at all.
///
/// While this is wired up: no SMS is sent, `verifyPhoneNumber` is never
/// called, no OTP provider is contacted, and no Firebase billing is needed.
class MockOtpVerifier implements OtpVerifier {
  const MockOtpVerifier({this.codeLength = 4});

  @override
  final int codeLength;

  @override
  Future<void> send(String phoneE164) async {
    // Intentionally nothing: no SMS, no provider call, no network at all.
  }

  /// True for any string of exactly [codeLength] digits. Anything shorter,
  /// longer, or non-numeric is rejected, so the screen's error path stays
  /// exercised.
  @override
  Future<bool> verify(String code) async {
    final trimmed = code.trim();
    return trimmed.length == codeLength &&
        trimmed.runes.every((r) => r >= 0x30 && r <= 0x39);
  }
}

/// The verifier the onboarding OTP step uses.
///
/// Swap this override for a Firebase-backed implementation to turn real
/// verification back on — nothing else needs to change.
final otpVerifierProvider = Provider<OtpVerifier>(
  (ref) => const MockOtpVerifier(),
);
