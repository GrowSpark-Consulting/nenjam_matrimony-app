import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_providers.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/inputs/otp_input.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/services/backend_sync_service.dart';
import '../controllers/login_controller.dart';
import '../controllers/phone_auth_controller.dart';
import '../providers/auth_providers.dart';

/// Phone-OTP **login** screen (login Option 2).
///
/// The OTP is already being sent by the login page before navigation. This
/// screen reads the shared [phoneAuthControllerProvider] session, lets the
/// user enter the code (or completes via auto-retrieval), signs in, and routes
/// based on the account's verification state.
class LoginOtpScreen extends ConsumerStatefulWidget {
  const LoginOtpScreen({super.key});

  @override
  ConsumerState<LoginOtpScreen> createState() => _LoginOtpScreenState();
}

class _LoginOtpScreenState extends ConsumerState<LoginOtpScreen> {
  String _otp = '';

  Future<void> _verify() async {
    final phoneState = ref.read(phoneAuthControllerProvider);
    if (_otp.length != 6 || phoneState.verificationId == null) return;
    final result =
        await ref.read(loginControllerProvider.notifier).loginWithPhoneCode(
              verificationId: phoneState.verificationId!,
              smsCode: _otp,
            );
    _handleResult(result);
  }

  Future<void> _verifyAuto() async {
    final credential = ref.read(phoneAuthControllerProvider).autoCredential;
    if (credential == null) return;
    ref.read(phoneAuthControllerProvider.notifier).clearAutoCredential();
    final result = await ref
        .read(loginControllerProvider.notifier)
        .loginWithAutoCredential(credential);
    _handleResult(result);
  }

  void _handleResult(LoginResult result) {
    if (!mounted) return;
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.errorMessage ?? AppLocalizations.of(context).authGenericError,
          ),
        ),
      );
      return;
    }
    // Best-effort: mirrors this Firebase session into the NestJS + Postgres
    // backend. Never awaited — must not block or fail the navigation below.
    unawaited(syncUserWithBackend(ref.read(apiClientProvider)));

    if (result.needsVerification) {
      final emailVerified =
          ref.read(firebaseAuthServiceProvider).currentUser?.emailVerified ??
              false;
      context.go(emailVerified ? RouteNames.verifyPhone : RouteNames.verifyEmail);
    } else {
      context.go(RouteNames.discover);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final phoneState = ref.watch(phoneAuthControllerProvider);
    final isLoading = ref.watch(loginControllerProvider);

    ref.listen<PhoneAuthState>(phoneAuthControllerProvider, (prev, next) {
      if (next.status == PhoneAuthStatus.autoRetrieved &&
          next.autoCredential != null) {
        _verifyAuto();
      }
      if (next.status == PhoneAuthStatus.error && next.errorMessage != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.authVerifyMobile,
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
                        l10n.authOtpSentTo(
                          ref.read(phoneAuthControllerProvider.notifier).phone,
                        ),
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
                  _verify();
                },
                onChanged: (value) => setState(() => _otp = value),
              ),
              const SizedBox(height: 40),
              NmGradientButton(
                label: l10n.authVerifyAndContinue,
                icon: Icons.check_circle_outline_rounded,
                isLoading: isLoading,
                onPressed: _otp.length == 6 ? _verify : null,
              ),
              const SizedBox(height: 32),
              Center(
                child: phoneState.secondsRemaining > 0
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
                            '00:${phoneState.secondsRemaining.toString().padLeft(2, '0')}',
                            style: AppTypography.titleLarge.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      )
                    : TextButton.icon(
                        onPressed: () => ref
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
