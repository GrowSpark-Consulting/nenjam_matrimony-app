import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/auth_error_mapper.dart';
import '../../data/models/auth_user.dart';
import '../../data/services/google_auth_service.dart';
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
