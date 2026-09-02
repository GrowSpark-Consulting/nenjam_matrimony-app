import 'package:flutter/foundation.dart';

import '../../../../core/services/storage_service.dart';

/// LOCAL DEVELOPMENT AUTHENTICATION — the client half of `dev-auth.ts`.
///
/// Signup currently ends at a dummy OTP screen ([MockOtpVerifier]) that
/// accepts any 4-digit code and mints no Firebase session, because real phone
/// verification needs SMS billing this project has not enabled. With no
/// session there is no ID token, so every authenticated request was rejected:
/// `flushOnboardingToBackend()` sent nothing, no `user_profiles` row was ever
/// written, and Discover answered 401 in a loop.
///
/// This holds the phone number the dummy OTP "verified", which
/// [AuthInterceptor] sends as `X-Dev-Auth-Phone` when there is no Firebase
/// token. The backend accepts it only when it is itself running with dev auth
/// switched on; see `dev-auth.ts` for that side's two independent switches.
///
/// ## The one switch that matters here
///
/// [isEnabled] is the single predicate for "this build uses the dummy OTP",
/// and `otp_verifier.dart` reads it too rather than keeping its own copy — so
/// the dummy OTP and the session standing in for it can never be out of step.
///
/// A debug build has it on by default. A release build has it off unless
/// `--dart-define=DUMMY_OTP=true` is passed, which is the temporary
/// production configuration: paired with the backend's `DUMMY_OTP_ENABLED`
/// plus a `DUMMY_OTP_PHONES` whitelist, so a deployed build can demo signup
/// before SMS billing is on, and only for numbers the operator configured.
///
/// `--dart-define=USE_REAL_OTP=true` overrides both and restores real Firebase
/// Phone Auth, which is the one-flag path back when billing is enabled.
///
/// Delete this class, `dev-auth.ts` and [MockOtpVerifier] together when real
/// phone verification is switched on.
class DevAuthSession {
  const DevAuthSession();

  /// The master switch back to real Firebase Phone Auth — mirrors the
  /// backend's `USE_REAL_OTP`, so one name means one thing on both sides.
  static const bool _useRealOtp = bool.fromEnvironment('USE_REAL_OTP');

  /// Opt-in for release builds. Off unless passed, so a normal release has no
  /// path to the header at all.
  static const bool _dummyOtpInRelease = bool.fromEnvironment('DUMMY_OTP');

  /// Whether this build uses the dummy OTP and the session that backs it.
  static bool get isEnabled =>
      !_useRealOtp && (kDebugMode || _dummyOtpInRelease);

  /// The dev-authenticated number, or null when there is no dev session.
  ///
  /// Guarded: local storage may not be initialised when the very first
  /// request goes out, and "cannot tell" must mean "no dev session" rather
  /// than a crash inside a Dio interceptor.
  String? get phone {
    if (!isEnabled) return null;
    try {
      final value = storageService.devAuthPhone;
      return (value != null && value.isNotEmpty) ? value : null;
    } catch (_) {
      return null;
    }
  }

  bool get isActive => phone != null;

  /// Records that the dummy OTP accepted [phoneE164]. Best-effort for the
  /// same reason as above: a storage failure must not turn a passed OTP into
  /// an error the member sees.
  Future<void> establish(String phoneE164) async {
    if (!isEnabled || phoneE164.isEmpty) return;
    try {
      await storageService.setDevAuthPhone(phoneE164);
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      await storageService.clearDevAuthPhone();
    } catch (_) {}
  }
}

/// Global instance — mirrors `storageService`, which it wraps.
const devAuthSession = DevAuthSession();
