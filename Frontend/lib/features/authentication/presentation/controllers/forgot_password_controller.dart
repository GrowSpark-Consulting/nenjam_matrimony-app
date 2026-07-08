import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/auth_error_mapper.dart';
import '../providers/auth_providers.dart';

enum ForgotPasswordStatus { initial, loading, success, error }

/// State for the Forgot Password screen.
class ForgotPasswordState {
  final ForgotPasswordStatus status;
  final String? errorMessage;

  const ForgotPasswordState({
    this.status = ForgotPasswordStatus.initial,
    this.errorMessage,
  });

  bool get isLoading => status == ForgotPasswordStatus.loading;
  bool get isSuccess => status == ForgotPasswordStatus.success;

  ForgotPasswordState copyWith({
    ForgotPasswordStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ForgotPasswordState(
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Sends a Firebase password-reset email.
///
/// Security: to avoid account enumeration, a `user-not-found` result is
/// surfaced as *success* — the UI never reveals whether the address is
/// registered. Real problems (invalid email, throttling, network) still error.
class ForgotPasswordController extends Notifier<ForgotPasswordState> {
  @override
  ForgotPasswordState build() => const ForgotPasswordState();

  Future<void> sendResetLink(String email) async {
    if (state.isLoading) return;
    state = state.copyWith(status: ForgotPasswordStatus.loading, clearError: true);
    try {
      await ref.read(authRepositoryProvider).resetPassword(email.trim());
      state = state.copyWith(status: ForgotPasswordStatus.success);
    } on FirebaseAuthException catch (e) {
      // Don't leak whether the account exists.
      if (e.code == 'user-not-found') {
        state = state.copyWith(status: ForgotPasswordStatus.success);
        return;
      }
      state = state.copyWith(
        status: ForgotPasswordStatus.error,
        errorMessage: AuthErrorMapper.message(e),
      );
    } catch (e) {
      state = state.copyWith(
        status: ForgotPasswordStatus.error,
        errorMessage: AuthErrorMapper.message(e),
      );
    }
  }

  void reset() => state = const ForgotPasswordState();
}

final forgotPasswordControllerProvider =
    NotifierProvider<ForgotPasswordController, ForgotPasswordState>(
  ForgotPasswordController.new,
);
