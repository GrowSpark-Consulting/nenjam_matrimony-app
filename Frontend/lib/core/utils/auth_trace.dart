import 'package:flutter/foundation.dart';

/// TEMPORARY — traces which auth intent a member started with, what the
/// backend said about their account, and where the app decided to send
/// them. Remove this file and every `AuthTrace.*` call site once the
/// email-signup routing question is closed.
///
/// Deliberately logs **intents, booleans and route names only**. Never an
/// address, a phone number, a password, an OTP or a Firebase token — the
/// whole point is that a debug build can be run with this on and the output
/// pasted into an issue without redacting anything.
///
/// Uses debugPrint rather than dart:developer's log() for the same reason
/// [StoryPerf] does: log() only surfaces with a VM Service client attached,
/// while debugPrint always reaches stdout/logcat.
class AuthTrace {
  static const _tag = '[AUTH-TRACE]';

  static void _emit(String line) {
    if (!kDebugMode) return;
    debugPrint('$_tag $line');
  }

  /// Which button the member pressed. [channel] is `email`, `mobile` or
  /// `google`; [intent] is `SIGNUP` or `LOGIN`.
  static void intent({required String channel, required String intent}) =>
      _emit('${channel.toUpperCase()} AUTH INTENT = $intent');

  /// Whether the credential exchange with Firebase succeeded. Not emitted
  /// by the email and mobile sign-up buttons, which perform none — see
  /// [unauthenticated].
  static void firebaseAuth({required String channel, required bool success}) =>
      _emit('firebase auth ($channel) success = $success');

  /// The email and mobile sign-up buttons run no credential step at all:
  /// onboarding is walked signed out and a session is opened at the final
  /// OTP screen. Recorded explicitly so its absence in a log is never read
  /// as a failed sign-in.
  static void unauthenticated(String channel) =>
      _emit('firebase auth ($channel) = NOT ATTEMPTED (signed-out onboarding)');

  /// The verdict from `POST /auth/account-exists`.
  static void accountExists({required bool email, required bool phone}) =>
      _emit('Nenjam account exists = email:$email mobile:$phone');

  /// `POST /auth/account-exists` could not be completed. Distinct from
  /// "available" — signup is refused either way.
  static void accountCheckUnavailable() =>
      _emit('Nenjam account exists = UNKNOWN (lookup failed)');

  /// `NEW`, `PARTIAL` or `COMPLETED`, as [PostAuthDestination] reads it.
  static void profileState(String state) => _emit('profile state = $state');

  /// What [PostAuthDestination] answered.
  static void destination(String route) =>
      _emit('resolved destination = $route');

  /// What the screen actually navigated to. [reason] says why, so a route
  /// that did not come from the resolver is never mistaken for one that did.
  static void navigate(String route, {String? reason}) =>
      _emit('navigation route = $route${reason == null ? '' : ' ($reason)'}');
}
