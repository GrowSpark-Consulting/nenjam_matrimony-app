import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/auth_error_mapper.dart';
import '../../../../core/l10n/app_l10n.dart';
import '../../data/models/auth_user.dart';
import '../../data/services/google_auth_service.dart';
import '../../domain/services/account_availability.dart';
import '../../domain/services/local_auth_session.dart';
import '../../domain/services/login_identifier.dart';
import '../../domain/services/otp_verifier.dart';
import '../providers/auth_providers.dart';

/// Result of a login attempt, describing where the user should go next.
class LoginResult {
  final bool success;
  final String? errorMessage;
  final AuthUser? user;

  /// True when the account isn't fully verified yet — the caller should route
  /// into the verification flow instead of Home.
  final bool needsVerification;

  /// True when the user backed out of a provider's UI (currently only the
  /// Google account picker). Distinct from a plain failure because there is
  /// nothing to tell the user — showing "something went wrong" after they
  /// deliberately hit back is noise.
  final bool cancelled;

  const LoginResult({
    required this.success,
    this.errorMessage,
    this.user,
    this.needsVerification = false,
    this.cancelled = false,
  });
}

/// Handles email/password login and phone-OTP login.
class LoginController extends Notifier<bool> {
  @override
  bool build() => false; // isLoading

  Future<LoginResult> loginWithEmail({
    required String email,
    required String password,
  }) async {
    state = true;
    try {
      final user = await ref.read(authRepositoryProvider).loginWithEmail(
            email: email.trim(),
            password: password,
          );
      state = false;
      // Email/password login does NOT require phone OTP — only the email
      // verification link gates entry.
      return LoginResult(
        success: true,
        user: user,
        needsVerification: !user.emailVerified,
      );
    } on FirebaseAuthException catch (e) {
      state = false;
      return LoginResult(success: false, errorMessage: AuthErrorMapper.message(e));
    } catch (e) {
      state = false;
      return LoginResult(success: false, errorMessage: AuthErrorMapper.message(e));
    }
  }

  /// Completes a phone-OTP login using a code the user typed.
  Future<LoginResult> loginWithPhoneCode({
    required String verificationId,
    required String smsCode,
  }) async {
    state = true;
    try {
      final user = await ref.read(authRepositoryProvider).loginWithPhoneCredential(
            verificationId: verificationId,
            smsCode: smsCode,
          );
      state = false;
      return LoginResult(
        success: true,
        user: user,
        needsVerification: !user.isFullyVerified,
      );
    } on FirebaseAuthException catch (e) {
      state = false;
      return LoginResult(success: false, errorMessage: AuthErrorMapper.message(e));
    } catch (e) {
      state = false;
      return LoginResult(success: false, errorMessage: AuthErrorMapper.message(e));
    }
  }

  /// Completes a mobile login against the development OTP verifier.
  ///
  /// The whole reason this lives on the controller rather than in the OTP
  /// screen is that "which codes are good" is an auth decision: the screen
  /// asks [OtpVerifier], and when real verification returns only the
  /// [otpVerifierProvider] override and the two lines below change — no
  /// widget contains `if (otp.isNotEmpty)`.
  ///
  /// A pass opens a [LocalAuthSession] rather than a Firebase one, because
  /// no phone credential exists to sign in with. See that class for why
  /// that is a bridge and not a second auth system.
  Future<LoginResult> loginWithMockOtp({
    required String phoneE164,
    required String code,
  }) async {
    state = true;
    try {
      final accepted = await ref.read(otpVerifierProvider).verify(code);
      if (!accepted) {
        state = false;
        return LoginResult(
          success: false,
          errorMessage: AppL10n.current.authInvalidOtp,
        );
      }
      await ref.read(localAuthSessionProvider).start(
            identifier: phoneE164,
            method: LocalAuthMethod.mobileOtp,
          );
      state = false;
      return const LoginResult(success: true);
    } catch (_) {
      state = false;
      return LoginResult(
        success: false,
        errorMessage: AppL10n.current.authGenericError,
      );
    }
  }

  /// Logs in from the single "email or mobile number" field.
  ///
  /// Email goes through [loginWithEmail] — a real Firebase credential
  /// check, with real failures. Mobile cannot: Firebase Auth has no
  /// phone-and-password sign-in and the backend has no login endpoint of
  /// its own, so the strongest question the app can ask today is the one
  /// `POST /auth/account-exists` already answers. A number with no account
  /// is refused (never quietly signed in), a lookup that fails is refused
  /// as "try again" (never read as success), and only a number the backend
  /// confirms opens a [LocalAuthSession].
  Future<LoginResult> loginWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    final l10n = AppL10n.current;
    if (password.isEmpty) {
      return LoginResult(
        success: false,
        errorMessage: l10n.authPasswordRequired,
      );
    }

    switch (LoginIdentifier.classify(identifier)) {
      case LoginIdentifierKind.email:
        return loginWithEmail(
          email: LoginIdentifier.normalizeEmail(identifier),
          password: password,
        );
      case LoginIdentifierKind.mobile:
        return _loginWithMobilePassword(
          phoneE164: LoginIdentifier.normalizeMobile(identifier),
        );
      case LoginIdentifierKind.unknown:
        return LoginResult(
          success: false,
          errorMessage: l10n.authIdentifierInvalid,
        );
    }
  }

  Future<LoginResult> _loginWithMobilePassword({
    required String phoneE164,
  }) async {
    final l10n = AppL10n.current;
    state = true;
    try {
      final availability = await ref.read(accountAvailabilityProvider).check(
            email: '',
            phoneE164: phoneE164,
          );
      if (!availability.phoneExists) {
        state = false;
        return LoginResult(
          success: false,
          errorMessage: l10n.authNoAccountForMobile,
        );
      }
      await ref.read(localAuthSessionProvider).start(
            identifier: phoneE164,
            method: LocalAuthMethod.mobilePassword,
          );
      state = false;
      return const LoginResult(success: true);
    } on AccountAvailabilityUnavailable {
      // "Could not tell" is not "available" — refuse rather than sign in.
      state = false;
      return LoginResult(
        success: false,
        errorMessage: l10n.authAccountCheckUnavailable,
      );
    } catch (_) {
      state = false;
      return LoginResult(
        success: false,
        errorMessage: l10n.authGenericError,
      );
    }
  }

  /// Completes a phone-OTP login from an auto-retrieved credential.
  Future<LoginResult> loginWithAutoCredential(
    PhoneAuthCredential credential,
  ) async {
    state = true;
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .loginWithAutoPhoneCredential(credential);
      state = false;
      return LoginResult(
        success: true,
        user: user,
        needsVerification: !user.isFullyVerified,
      );
    } on FirebaseAuthException catch (e) {
      state = false;
      return LoginResult(success: false, errorMessage: AuthErrorMapper.message(e));
    } catch (e) {
      state = false;
      return LoginResult(success: false, errorMessage: AuthErrorMapper.message(e));
    }
  }
}

final loginControllerProvider =
    NotifierProvider<LoginController, bool>(LoginController.new);

/// Handles "Continue with Google".
///
/// Kept separate from [LoginController] rather than added as another method
/// on it so the two share no `isLoading` bit: the email Login button and the
/// Google button read different providers and only the tapped one spins.
class GoogleSignInController extends Notifier<bool> {
  @override
  bool build() => false; // isLoading

  Future<LoginResult> signIn() async {
    state = true;
    try {
      final user = await ref.read(authRepositoryProvider).loginWithGoogle();
      state = false;
      // Google asserts the address, so `emailVerified` is already true and
      // this evaluates false — the same rule email/password login uses,
      // which routes the user straight to Discover.
      return LoginResult(
        success: true,
        user: user,
        needsVerification: !user.emailVerified,
      );
    } on GoogleSignInCancelled {
      state = false;
      return const LoginResult(success: false, cancelled: true);
    } on FirebaseAuthException catch (e) {
      state = false;
      return LoginResult(success: false, errorMessage: AuthErrorMapper.message(e));
    } catch (e) {
      state = false;
      return LoginResult(success: false, errorMessage: AuthErrorMapper.message(e));
    }
  }
}

final googleSignInControllerProvider =
    NotifierProvider<GoogleSignInController, bool>(GoogleSignInController.new);
