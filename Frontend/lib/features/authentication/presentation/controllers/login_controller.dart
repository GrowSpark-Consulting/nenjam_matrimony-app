import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/auth_error_mapper.dart';
import '../../data/models/auth_user.dart';
import '../providers/auth_providers.dart';

/// Result of a login attempt, describing where the user should go next.
class LoginResult {
  final bool success;
  final String? errorMessage;
  final AuthUser? user;

  /// True when the account isn't fully verified yet — the caller should route
  /// into the verification flow instead of Home.
  final bool needsVerification;

  const LoginResult({
    required this.success,
    this.errorMessage,
    this.user,
    this.needsVerification = false,
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
