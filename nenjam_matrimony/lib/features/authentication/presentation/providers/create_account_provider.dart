import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for the Create Account / Sign Up form.
class CreateAccountState {
  final String phone;
  final String email;
  final String password;
  final String mobileOtp;
  final String emailOtp;
  final String registeringFor;
  final bool mobileSentOtp;
  final bool emailSentOtp;
  final bool isLoading;

  const CreateAccountState({
    this.phone = '',
    this.email = '',
    this.password = '',
    this.mobileOtp = '',
    this.emailOtp = '',
    this.registeringFor = 'Myself',
    this.mobileSentOtp = false,
    this.emailSentOtp = false,
    this.isLoading = false,
  });

  CreateAccountState copyWith({
    String? phone,
    String? email,
    String? password,
    String? mobileOtp,
    String? emailOtp,
    String? registeringFor,
    bool? mobileSentOtp,
    bool? emailSentOtp,
    bool? isLoading,
  }) {
    return CreateAccountState(
      phone: phone ?? this.phone,
      email: email ?? this.email,
      password: password ?? this.password,
      mobileOtp: mobileOtp ?? this.mobileOtp,
      emailOtp: emailOtp ?? this.emailOtp,
      registeringFor: registeringFor ?? this.registeringFor,
      mobileSentOtp: mobileSentOtp ?? this.mobileSentOtp,
      emailSentOtp: emailSentOtp ?? this.emailSentOtp,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  /// True when both OTPs are complete (6 digits each).
  bool get isMobileOtpComplete => mobileOtp.length == 6;
  bool get isEmailOtpComplete => emailOtp.length == 6;

  /// True when the form is ready to submit.
  bool get canSubmit =>
      mobileSentOtp &&
      emailSentOtp &&
      isMobileOtpComplete &&
      isEmailOtpComplete &&
      password.length >= 8;
}

/// Notifier managing all Create Account form state.
class CreateAccountNotifier extends Notifier<CreateAccountState> {
  @override
  CreateAccountState build() => const CreateAccountState();

  void setPhone(String phone) =>
      state = state.copyWith(phone: phone);

  void setEmail(String email) =>
      state = state.copyWith(email: email);

  void setPassword(String password) =>
      state = state.copyWith(password: password);

  void setMobileOtp(String otp) =>
      state = state.copyWith(mobileOtp: otp);

  void setEmailOtp(String otp) =>
      state = state.copyWith(emailOtp: otp);

  void setRegisteringFor(String value) =>
      state = state.copyWith(registeringFor: value);

  void sendMobileOtp() {
    if (state.phone.length >= 10) {
      state = state.copyWith(mobileSentOtp: true);
    }
  }

  void sendEmailOtp() {
    final email = state.email;
    if (email.contains('@') && email.contains('.')) {
      state = state.copyWith(emailSentOtp: true);
    }
  }

  Future<void> createAccount() async {
    state = state.copyWith(isLoading: true);
    await Future<void>.delayed(const Duration(seconds: 1));
    state = state.copyWith(isLoading: false);
    // Navigation is handled by the page.
  }
}

/// Global provider for Create Account state.
final createAccountProvider =
    NotifierProvider<CreateAccountNotifier, CreateAccountState>(
  CreateAccountNotifier.new,
);
