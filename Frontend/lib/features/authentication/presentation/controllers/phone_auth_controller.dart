import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/auth_error_mapper.dart';
import '../providers/auth_providers.dart';

enum PhoneAuthStatus { idle, sending, codeSent, autoRetrieved, error }

/// State for a single phone-number verification session.
class PhoneAuthState {
  final PhoneAuthStatus status;
  final String? verificationId;
  final int? resendToken;

  /// Set when Android auto-retrieval completes; the screen consumes it to
  /// finish sign-in/linking without manual entry.
  final PhoneAuthCredential? autoCredential;
  final String? errorMessage;
  final int secondsRemaining;

  const PhoneAuthState({
    this.status = PhoneAuthStatus.idle,
    this.verificationId,
    this.resendToken,
    this.autoCredential,
    this.errorMessage,
    this.secondsRemaining = 0,
  });

  bool get canResend => secondsRemaining <= 0 &&
      (status == PhoneAuthStatus.codeSent || status == PhoneAuthStatus.error);

  PhoneAuthState copyWith({
    PhoneAuthStatus? status,
    String? verificationId,
    int? resendToken,
    PhoneAuthCredential? autoCredential,
    String? errorMessage,
    int? secondsRemaining,
    bool clearError = false,
    bool clearAutoCredential = false,
  }) {
    return PhoneAuthState(
      status: status ?? this.status,
      verificationId: verificationId ?? this.verificationId,
      resendToken: resendToken ?? this.resendToken,
      autoCredential:
          clearAutoCredential ? null : (autoCredential ?? this.autoCredential),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      secondsRemaining: secondsRemaining ?? this.secondsRemaining,
    );
  }
}

/// Manages sending / resending the SMS OTP and the resend countdown. Verifying
/// the entered code is done by the screen via the repository, because signup
/// (link) and login (sign-in) confirm differently.
class PhoneAuthController extends Notifier<PhoneAuthState> {
  Timer? _timer;
  String _phone = '';

  @override
  PhoneAuthState build() {
    ref.onDispose(() => _timer?.cancel());
    return const PhoneAuthState();
  }

  /// The E.164 number this session is verifying.
  String get phone => _phone;

  /// Sends the initial OTP to [phoneE164] (must be +country format).
  Future<void> sendCode(String phoneE164) async {
    _phone = phoneE164;
    state = state.copyWith(
      status: PhoneAuthStatus.sending,
      clearError: true,
      clearAutoCredential: true,
    );
    await _verify();
  }

  /// Requests a fresh OTP using the stored resend token.
  Future<void> resend() async {
    if (!state.canResend) return;
    state = state.copyWith(status: PhoneAuthStatus.sending, clearError: true);
    await _verify(resendToken: state.resendToken);
  }

  Future<void> _verify({int? resendToken}) async {
    final repo = ref.read(authRepositoryProvider);
    await repo.startPhoneVerification(
      phoneNumber: _phone,
      resendToken: resendToken,
      onCodeSent: (verificationId, token) {
        state = state.copyWith(
          status: PhoneAuthStatus.codeSent,
          verificationId: verificationId,
          resendToken: token,
        );
        _startCountdown();
      },
      onAutoVerified: (credential) {
        state = state.copyWith(
          status: PhoneAuthStatus.autoRetrieved,
          autoCredential: credential,
        );
      },
      onFailed: (e) {
        state = state.copyWith(
          status: PhoneAuthStatus.error,
          errorMessage: AuthErrorMapper.message(e),
        );
      },
      onTimeout: (verificationId) {
        // Auto-retrieval window closed; keep verificationId for manual entry.
        state = state.copyWith(verificationId: verificationId);
      },
    );
  }

  void _startCountdown() {
    _timer?.cancel();
    state = state.copyWith(secondsRemaining: 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final next = state.secondsRemaining - 1;
      if (next <= 0) {
        t.cancel();
        state = state.copyWith(secondsRemaining: 0);
      } else {
        state = state.copyWith(secondsRemaining: next);
      }
    });
  }

  void setError(String message) => state = state.copyWith(
        status: PhoneAuthStatus.error,
        errorMessage: message,
      );

  void clearAutoCredential() => state = state.copyWith(clearAutoCredential: true);
}

final phoneAuthControllerProvider =
    NotifierProvider<PhoneAuthController, PhoneAuthState>(PhoneAuthController.new);
