import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/auth_error_mapper.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/inputs/otp_input.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../registration/presentation/providers/registration_provider.dart';
import '../controllers/phone_auth_controller.dart';
import '../controllers/signup_controller.dart';
import '../providers/auth_providers.dart';

/// Phone (Mobile) OTP verification for the signup flow.
///
/// Sends a real SMS via Firebase Phone Auth, supports Android auto-retrieval,
/// manual 6-digit entry, resend with countdown, and links the verified number
/// to the signed-in account before entering the app.
class PhoneVerifyScreen extends ConsumerStatefulWidget {
  const PhoneVerifyScreen({super.key});

  @override
  ConsumerState<PhoneVerifyScreen> createState() => _PhoneVerifyScreenState();
}

class _PhoneVerifyScreenState extends ConsumerState<PhoneVerifyScreen> {
  String _otp = '';
  bool _verifying = false;
  String _phone = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // Resolve the E.164 number: prefer the in-flight signup state, else the
    // locally-stashed pending phone (survives a cold start), else any number
    // already linked to the Firebase user.
    final signupPhone = ref.read(signupControllerProvider).phone;
    if (signupPhone.isNotEmpty) {
      _phone = ref.read(signupControllerProvider).e164Phone;
    } else {
      _phone = storageService.pendingPhone ??
          ref.read(authRepositoryProvider).currentUser?.phoneNumber ??
          '';
    }
    if (_phone.isNotEmpty) {
      await ref.read(phoneAuthControllerProvider.notifier).sendCode(_phone);
    }
  }

  Future<void> _onAutoVerified() async {
    final controller = ref.read(phoneAuthControllerProvider.notifier);
    final credential = ref.read(phoneAuthControllerProvider).autoCredential;
    if (credential == null || _verifying) return;
    controller.clearAutoCredential();
    setState(() => _verifying = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .confirmAutoPhoneForSignup(credential);
      _onVerifiedSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      _showError(AuthErrorMapper.message(e));
    }
  }

  Future<void> _verifyManual() async {
    final state = ref.read(phoneAuthControllerProvider);
    if (_otp.length != 6 || state.verificationId == null || _verifying) return;
    setState(() => _verifying = true);
    try {
      await ref.read(authRepositoryProvider).confirmPhoneForSignup(
            verificationId: state.verificationId!,
            smsCode: _otp,
          );
      _onVerifiedSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      _showError(AuthErrorMapper.message(e));
    }
  }

  void _onVerifiedSuccess() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.authPhoneVerifiedSuccess),
        backgroundColor: AppColors.success,
      ),
    );
    ref.read(signupControllerProvider.notifier).reset();
    storageService.clearPendingPhone();
    // Account fully created + verified → build the matrimony profile.
    // Always CREATE MODE here — guarantees no stale draft/mode leaks in
    // from a previous session (e.g. a prior user's edit on a shared device).
    ref.read(registrationProvider.notifier).startCreateMode();
    context.go(RouteNames.registrationWizard);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.watch(phoneAuthControllerProvider);

    // React to Android instant verification.
    ref.listen<PhoneAuthState>(phoneAuthControllerProvider, (prev, next) {
      if (next.status == PhoneAuthStatus.autoRetrieved &&
          next.autoCredential != null) {
        _onAutoVerified();
      }
      if (next.status == PhoneAuthStatus.error && next.errorMessage != null) {
        _showError(next.errorMessage!);
      }
    });

    final isSending = state.status == PhoneAuthStatus.sending;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.authVerifyPhoneTitle,
          style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Text(
                l10n.authEnterVerificationCode,
                style: AppTypography.headlineLarge
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceVariantDark
                      : AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.phone_rounded,
                        size: 20, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isSending
                            ? l10n.authSendingOtp
                            : l10n.authOtpSentTo(_phone),
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              NmOtpInput(
                length: 6,
                onCompleted: (value) {
                  _otp = value;
                  _verifyManual();
                },
                onChanged: (value) => setState(() => _otp = value),
              ),
              const SizedBox(height: 40),
              NmGradientButton(
                label: l10n.authVerifyAndContinue,
                icon: Icons.check_circle_outline_rounded,
                isLoading: _verifying,
                onPressed: _otp.length == 6 ? _verifyManual : null,
              ),
              const SizedBox(height: 32),
              Center(
                child: state.secondsRemaining > 0
                    ? Column(
                        children: [
                          Text(
                            l10n.authResendOtpIn,
                            style: AppTypography.bodySmall.copyWith(
                              color: isDark
                                  ? AppColors.textTertiaryDark
                                  : AppColors.textTertiaryLight,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '00:${state.secondsRemaining.toString().padLeft(2, '0')}',
                            style: AppTypography.titleLarge.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      )
                    : TextButton.icon(
                        onPressed: isSending
                            ? null
                            : () => ref
                                .read(phoneAuthControllerProvider.notifier)
                                .resend(),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(l10n.authResendOtp),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          textStyle: AppTypography.labelLarge
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
