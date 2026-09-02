import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/auth_error_mapper.dart';
import '../../../../core/services/storage_service.dart';
import '../../data/services/dev_auth_session.dart';
import '../../presentation/controllers/phone_auth_controller.dart';
import '../../presentation/providers/auth_providers.dart';

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
  MockOtpVerifier({this.codeLength = 4});

  @override
  final int codeLength;

  /// The number [send] was called with, so [verify] knows who it just let in.
  /// Held on the instance rather than read back from storage because the
  /// login and onboarding screens stash the pending phone under different
  /// keys, and this verifier is handed it directly either way.
  String? _phoneE164;

  @override
  Future<void> send(String phoneE164) async {
    // No SMS, no provider call, no network at all — only remember who is
    // being "verified", for the dev session established in `verify`.
    _phoneE164 = phoneE164;
  }

  /// True for any string of exactly [codeLength] digits. Anything shorter,
  /// longer, or non-numeric is rejected, so the screen's error path stays
  /// exercised.
  @override
  Future<bool> verify(String code) async {
    final trimmed = code.trim();
    final accepted = trimmed.length == codeLength &&
        trimmed.runes.every((r) => r >= 0x30 && r <= 0x39);
    if (!accepted) return false;

    // Establish the dev session this mock previously left missing.
    //
    // Returning `true` without one was the whole defect: the caller took it as
    // "authenticated", walked into the app, and every request went out with no
    // credential — so onboarding saved nothing and Discover answered 401 in a
    // loop. A verifier that reports success owes the app a session, and in a
    // debug build this is the session it can honestly give.
    // Guarded: local storage may not be initialised (a widget test, a very
    // early call), and a verifier that already accepted the code must not
    // turn that into a thrown error. No number simply means no dev session.
    String? phone = _phoneE164;
    if (phone == null) {
      try {
        phone = storageService.pendingPhone;
      } catch (_) {
        phone = null;
      }
    }
    if (phone != null && phone.isNotEmpty) {
      await devAuthSession.establish(phone);
    }
    return true;
  }
}

/// Real verification, over the same Firebase phone-auth stack the login
/// screens already use.
///
/// Adds no authentication system and no OTP logic of its own: [send] drives
/// [PhoneAuthController] (the SMS request, the resend token, the 60-second
/// countdown, Android auto-retrieval and the error mapping all already live
/// there), and [verify] hands the code to [FirebaseAuthRepository] exactly as
/// `login_otp_screen.dart` does. The code goes to Google, never to this app's
/// backend — Firebase is what decides whether it is right, and the only thing
/// that reaches our API afterwards is the ID token it mints.
///
/// Signup arrives here in one of two states, and both already have a method:
///
///   * **Already signed in** (Google or email signup) — the number is *linked*
///     to that account, so one member does not become two.
///   * **No session** (the common path: onboarding collects a whole profile
///     before asking for any credential) — the phone credential *signs in*,
///     and that is what finally gives the member a real session.
///
/// Fails closed by construction. Every "no" — wrong code, expired session,
/// phone auth disabled in the Firebase console, no network — ends as `false`
/// or as an absent `verificationId`, and there is no branch that returns
/// `true` without Firebase having accepted the credential.
class FirebasePhoneOtpVerifier implements OtpVerifier {
  const FirebasePhoneOtpVerifier(this._ref);

  final Ref _ref;

  /// Firebase SMS codes are always six digits. The onboarding screen reads
  /// this for both its input boxes and its submit gate, so the UI follows
  /// automatically — nothing hardcodes a length.
  @override
  int get codeLength => 6;

  @override
  Future<void> send(String phoneE164) =>
      _ref.read(phoneAuthControllerProvider.notifier).sendCode(phoneE164);

  @override
  Future<bool> verify(String code) async {
    // No verificationId means no SMS session was ever established — the send
    // failed, or Firebase rejected the number. Nothing to verify against, and
    // approving here would be approving nothing.
    final verificationId = _ref.read(phoneAuthControllerProvider).verificationId;
    if (verificationId == null) return false;

    final repository = _ref.read(authRepositoryProvider);

    try {
      if (_ref.read(firebaseAuthServiceProvider).currentUser != null) {
        await repository.confirmPhoneForSignup(
          verificationId: verificationId,
          smsCode: code,
        );
      } else {
        await repository.loginWithPhoneCredential(
          verificationId: verificationId,
          smsCode: code,
        );
      }
      return true;
    } on FirebaseAuthException catch (e) {
      // A wrong or stale code is an answer, not a failure — the interface
      // contract, and what lets the screen show "that code isn't right"
      // instead of an error dialog.
      if (_isRejectedCode(e.code)) return false;

      // Anything else (network down, phone auth not enabled, quota) is a
      // genuine failure. It still answers `false` — the screen has no throwing
      // path and an exception escaping here would crash it — but the real
      // reason is recorded on the shared phone-auth state rather than
      // discarded, so it stays diagnosable. AuthErrorMapper is the same
      // translation the login screens use; it never echoes the code back.
      _ref
          .read(phoneAuthControllerProvider.notifier)
          .setError(AuthErrorMapper.message(e));
      return false;
    } catch (e) {
      _ref
          .read(phoneAuthControllerProvider.notifier)
          .setError(AuthErrorMapper.message(e));
      return false;
    }
  }

  /// Firebase's ways of saying "that code does not match this session".
  static bool _isRejectedCode(String code) =>
      code == 'invalid-verification-code' ||
      code == 'session-expired' ||
      code == 'invalid-verification-id';
}

/// The verifier the onboarding OTP step uses.
///
/// Debug keeps the mock by default, and not for convenience: Firebase Phone
/// Auth requires SMS billing on the project, and calling it from onboarding
/// failed with BILLING_NOT_ENABLED, which is why the mock exists at all.
///
/// Release builds get [FirebasePhoneOtpVerifier] unless
/// `--dart-define=DUMMY_OTP=true` is passed. That opt-in is the *temporary*
/// production configuration for demoing signup before billing is enabled, and
/// it is only half of it: the backend must also run with `DUMMY_OTP_ENABLED`
/// and list the number in `DUMMY_OTP_PHONES`, so a release built with the flag
/// still authenticates nobody the operator did not configure. A release built
/// without it has no path to the mock at all.
///
/// `--dart-define=USE_REAL_OTP=true` overrides both and restores real Firebase
/// Phone Auth — the same switch CI or a device test can flip, so "does real
/// verification work?" is answerable without cutting a special build, and the
/// one flag to set when billing goes live.
///
/// The condition itself lives on [DevAuthSession.isEnabled]; see
/// `dev_auth_session.dart` for why it is defined in exactly one place.

final otpVerifierProvider = Provider<OtpVerifier>((ref) {
  // One predicate, owned by DevAuthSession, rather than a second copy of the
  // same condition here: a verifier that accepts a dummy code must always be
  // paired with the session that makes the resulting requests authenticate,
  // and two separately-maintained booleans is exactly how those drift apart.
  //
  // No longer const: the mock remembers the number `send` was given so
  // `verify` can establish a session for it. Provider caches one instance per
  // container, so the send and the verify are the same object.
  if (DevAuthSession.isEnabled) return MockOtpVerifier();
  return FirebasePhoneOtpVerifier(ref);
});
