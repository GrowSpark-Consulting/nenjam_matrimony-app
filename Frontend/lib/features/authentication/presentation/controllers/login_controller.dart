import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/auth_error_mapper.dart';
import '../../../../core/l10n/app_l10n.dart';
import '../../data/models/auth_user.dart';
import '../../data/services/google_auth_service.dart';
import '../../domain/services/account_availability.dart';
import '../../domain/services/dummy_otp_session.dart';
import '../../domain/services/local_auth_session.dart';
import '../../domain/services/login_identifier.dart';
import '../../domain/services/otp_verifier.dart';
import '../../../registration/presentation/providers/registration_provider.dart';
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
  /// A pass is exchanged for a REAL Firebase session through the backend
  /// ([DummyOtpSessionStarter]) — the same exchange the signup OTP screen
  /// makes, so a member who signs up and a member who logs back in end up
  /// holding the same kind of credential for the same account.
  ///
  /// It used to open a [LocalAuthSession] instead, because no phone credential
  /// exists to sign in with. That marker proved nothing about identity and
  /// left the session authenticating by header, which is what could leave a
  /// member signed in as an account the backend had never created.
  ///
  /// A failed exchange is a failed login, reported as one: the alternative is
  /// letting someone into the app with no account behind them.
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
      await ref
          .read(dummyOtpSessionStarterProvider)
          .start(phoneE164: phoneE164);
      state = false;
      return const LoginResult(success: true);
    } on DummyOtpSessionException catch (error) {
      state = false;
      return LoginResult(success: false, errorMessage: error.message);
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
      // Exchanged for a REAL Firebase session, the same way the two OTP paths
      // above do, so every login method ends on the same kind of credential
      // for the same uid.
      //
      // This used to open a [LocalAuthSession]: a device-local marker whose
      // requests authenticated by sending the phone number in an
      // `X-Dev-Auth-Phone` header. The backend no longer honours that header,
      // and should never have on a deployed server — with DUMMY_OTP_ENABLED it
      // accepted any well-formed number with no credential at all, and
      // resolved to a different identity than this endpoint returns, so one
      // number could end up owning two accounts.
      //
      // The user-facing flow is unchanged: same screen, same field, same
      // account check before it, same LoginResult out.
      await ref
          .read(dummyOtpSessionStarterProvider)
          .start(phoneE164: phoneE164);
      state = false;
      return const LoginResult(success: true);
    } on DummyOtpSessionException catch (error) {
      // A failed exchange is a failed login. Reporting success without a
      // session would restore exactly what this replaced: signed in as far as
      // the app is concerned, unauthenticated as far as the API is.
      state = false;
      return LoginResult(success: false, errorMessage: error.message);
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

/// Which button the member tapped: "Continue with Google" on the Login
/// screen, or on the Sign Up screen.
///
/// Google authentication itself is identical for both — one credential, one
/// Firebase session — so the provider cannot tell them apart, and nothing
/// downstream could either. That is the whole defect this enum fixes: with no
/// intent recorded, both buttons ran the same code and the app decided what
/// the member had *meant* purely from whatever state their account happened
/// to be in. Someone tapping Log In with a Google account that had never
/// registered was silently enrolled into a 13-step signup they never asked
/// for, and someone tapping Sign Up began onboarding on whatever stale draft
/// the previous session had left behind — because the Google path, alone
/// among the three sign-up buttons, never called `startCreateMode()`.
///
/// The intent is the member's; the account state is the backend's. Both are
/// needed, and they answer different questions.
enum GoogleAuthIntent {
  /// "I already have an account." An established member goes to Discover; a
  /// member part-way through registration resumes their step. A Google
  /// identity with no account behind it is NOT quietly turned into a signup
  /// — see LoginPage's handling.
  login,

  /// "I am creating an account." Starts CREATE mode before routing, exactly
  /// as the mobile and email sign-up buttons do, so onboarding never begins
  /// on a leftover draft. An account that turns out to be already registered
  /// is still sent to Discover rather than made to register twice.
  signup,
}

/// Handles "Continue with Google".
///
/// Kept separate from [LoginController] rather than added as another method
/// on it so the two share no `isLoading` bit: the email Login button and the
/// Google button read different providers and only the tapped one spins.
class GoogleSignInController extends Notifier<bool> {
  @override
  bool build() => false; // isLoading

  /// Authenticates with Google on behalf of [intent].
  ///
  /// One implementation for both buttons — there is only one Google
  /// credential exchange and duplicating it would be two things to keep
  /// right. What [intent] changes is what happens *around* it: a signup
  /// resets the draft first, so the flow that follows starts clean.
  Future<LoginResult> signIn({
    required GoogleAuthIntent intent,
  }) async {
    // A second tap while the first is still open would start a second Google
    // popup (a browser blocks or stacks it) or a second account chooser.
    // Treated like a dismissal: silent, and the first attempt stays in charge.
    if (state) return const LoginResult(success: false, cancelled: true);
    state = true;
    try {
      final user = await ref.read(authRepositoryProvider).loginWithGoogle();

      // Parity with the mobile and email sign-up buttons, which have always
      // done this (see RegistrationLandingPage._signUpWith). Safe for a
      // returning member mid-registration: this clears only the *local*
      // draft, and PostAuthDestination immediately rehydrates the backend's
      // copy — so a resumed signup keeps every answer, while a stale draft
      // from an unrelated session cannot leak into a new one.
      if (intent == GoogleAuthIntent.signup) {
        ref.read(registrationProvider.notifier).startCreateMode();
      }

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
