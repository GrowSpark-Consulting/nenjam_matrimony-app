import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/storage_service.dart';

/// How a local development session was established.
enum LocalAuthMethod {
  /// Mobile number + a code accepted by [MockOtpVerifier].
  mobileOtp,

  /// Mobile number + password, checked only for "does this account exist".
  mobilePassword,
}

/// A signed-in state that Firebase cannot represent yet.
///
/// Two of the four login routes end here rather than in a Firebase session,
/// and for the same underlying reason — there is no credential to exchange:
///
///  * **Mobile + OTP.** The OTP is [MockOtpVerifier] while no SMS provider
///    is connected, so no phone credential is ever minted and
///    `signInWithCredential` is never called.
///  * **Mobile + password.** Firebase Auth has no phone-and-password
///    sign-in, and the backend has no login endpoint of its own — every
///    route there is behind `FirebaseAuthGuard`, i.e. behind Firebase.
///    The most the app can establish today is that the number *has* an
///    account, via `POST /auth/account-exists`.
///
/// Email + password and Google both mint real Firebase sessions and do not
/// come through here at all.
///
/// This is deliberately the **same kind of bridge** as
/// [StorageService.onboardingCompleted], not a second auth system: it is
/// local to the device, holds no token, and proves nothing about identity.
/// It exists so the two routes above leave the app in a coherent
/// authenticated state instead of dropping the user into Discover while
/// every guard still reads "signed out".
///
/// **Deleting it later is one file plus its call sites:** when real OTP and
/// a real mobile-password endpoint land, those two paths return an
/// `AuthUser` like the others, [isActive] stops being consulted by the
/// router guard, the splash and the resume check, and this class goes.
class LocalAuthSession {
  const LocalAuthSession();

  /// Whether a local session is currently open. Guarded: local storage may
  /// not be initialised when the router's redirect runs very early, and
  /// "cannot tell" must mean "not signed in", never a crash in the router.
  bool get isActive {
    try {
      return storageService.localSessionIdentifier != null;
    } catch (_) {
      return false;
    }
  }

  /// The mobile number this session belongs to, or null.
  String? get identifier {
    try {
      return storageService.localSessionIdentifier;
    } catch (_) {
      return null;
    }
  }

  Future<void> start({
    required String identifier,
    required LocalAuthMethod method,
  }) =>
      storageService.setLocalSession(
        identifier: identifier,
        method: method.name,
      );

  Future<void> clear() => storageService.clearLocalSession();
}

final localAuthSessionProvider = Provider<LocalAuthSession>(
  (ref) => const LocalAuthSession(),
);

/// Context-free read of [LocalAuthSession.isActive], for the router guard,
/// the splash and the resume check — all of which decide "is this user
/// allowed in?" without a `Ref` to hand.
bool hasLocalAuthSession() => const LocalAuthSession().isActive;
