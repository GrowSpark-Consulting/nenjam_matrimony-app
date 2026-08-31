import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/auth_error_mapper.dart';
import '../../../../core/services/storage_service.dart';
import '../providers/auth_providers.dart';

/// Immutable state for the signup form + submission lifecycle.
class SignupState {
  final String username;
  final String email;
  final String password;
  final String phone;
  final bool isSubmitting;
  final String? errorMessage;

  const SignupState({
    this.username = '',
    this.email = '',
    this.password = '',
    this.phone = '',
    this.isSubmitting = false,
    this.errorMessage,
  });

  SignupState copyWith({
    String? username,
    String? email,
    String? password,
    String? phone,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SignupState(
      username: username ?? this.username,
      email: email ?? this.email,
      password: password ?? this.password,
      phone: phone ?? this.phone,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  /// E.164 phone for India (+91). The form only accepts 10 digits.
  String get e164Phone => '+91$phone';
}

/// Drives account creation: username uniqueness → Firebase user → email
/// verification link → Firestore record. Navigation is left to the screen.
class SignupController extends Notifier<SignupState> {
  @override
  SignupState build() => const SignupState();

  void setUsername(String v) => state = state.copyWith(username: v, clearError: true);
  void setEmail(String v) => state = state.copyWith(email: v, clearError: true);
  void setPassword(String v) => state = state.copyWith(password: v, clearError: true);
  void setPhone(String v) => state = state.copyWith(phone: v, clearError: true);

  /// Attempts to create the account. Returns `true` when the user is created
  /// and the verification email has been sent (caller should navigate to the
  /// email-verify screen). On failure sets [SignupState.errorMessage].
  ///
  /// The username lives on the Firebase user (`displayName`) and in this
  /// controller state until the backend owns it; the phone is stashed locally
  /// so it survives a cold start before OTP verification.
  Future<bool> submit() async {
    if (state.isSubmitting) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await ref.read(authRepositoryProvider).signUp(
            username: state.username.trim(),
            email: state.email.trim(),
            password: state.password,
          );
      await storageService.setPendingPhone(state.e164Phone);
      state = state.copyWith(isSubmitting: false);
      return true;
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(isSubmitting: false, errorMessage: AuthErrorMapper.message(e));
      return false;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, errorMessage: AuthErrorMapper.message(e));
      return false;
    }
  }

  void reset() => state = const SignupState();
}

final signupControllerProvider =
    NotifierProvider<SignupController, SignupState>(SignupController.new);
