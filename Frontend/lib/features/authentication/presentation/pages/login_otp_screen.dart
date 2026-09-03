import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/inputs/otp_input.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/services/otp_verifier.dart';
import '../controllers/login_controller.dart';

/// Phone-OTP **login** screen (login Option 2).
///
/// The code is already requested by the screen before this one ("Welcome
/// back" or the Login tab), which also stashes the number. Verification
/// goes through [OtpVerifier], currently [MockOtpVerifier]: **no SMS is
/// sent and no OTP provider is contacted**, and any non-empty code is
/// accepted. The screen, its position in the flow and the session it opens
/// are all real, so connecting a provider later is an override in
/// `otpVerifierProvider` and no change here.
///
/// Which codes count is deliberately not decided in this file —
/// [LoginController.loginWithMockOtp] owns it, and owns opening the
/// session that follows.
class LoginOtpScreen extends ConsumerStatefulWidget {
  const LoginOtpScreen({super.key});

  @override
  ConsumerState<LoginOtpScreen> createState() => _LoginOtpScreenState();
}

class _LoginOtpScreenState extends ConsumerState<LoginOtpScreen> {
  String _otp = '';
  String _phone = '';

  /// Shown under the boxes when the code was refused — an empty one, for
  /// now. Cleared as soon as the user types again.
  String? _error;

  Timer? _resendTimer;
  int _secondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    _phone = storageService.pendingPhone ?? '';
    _startCountdown();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _resendTimer?.cancel();
    setState(() => _secondsRemaining = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _secondsRemaining -= 1);
      if (_secondsRemaining <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    if (_secondsRemaining > 0 || _phone.isEmpty) return;
    await ref.read(otpVerifierProvider).send(_phone);
    if (!mounted) return;
    _startCountdown();
  }

  Future<void> _verify() async {
    if (ref.read(loginControllerProvider)) return; // already verifying
    if (_otp.trim().isEmpty) {
      setState(() => _error = AppLocalizations.of(context).authOtpRequired);
      return;
    }
    setState(() => _error = null);
    final result =
        await ref.read(loginControllerProvider.notifier).loginWithMockOtp(
              phoneE164: _phone,
              code: _otp,
            );
    await _handleResult(result);
  }

  Future<void> _handleResult(LoginResult result) async {
    if (!mounted) return;
    if (!result.success) {
      final message =
          result.errorMessage ?? AppLocalizations.of(context).authGenericError;
      setState(() => _error = message);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    // The number stops being "pending" the moment it is verified.
    await storageService.clearPendingPhone();
    if (!mounted) return;

    // `go`, not `push` — authentication is over, so this screen and the
    // login screen under it must not remain on the stack for Back to
    // return to.
    context.go(RouteNames.discover);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLoading = ref.watch(loginControllerProvider);
    final codeLength = ref.watch(otpVerifierProvider).codeLength;

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
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.phone_rounded,
                        size: 20, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.authOtpSentTo(_phone),
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondaryLight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              NmOtpInput(
                length: codeLength,
                onCompleted: (value) {
                  _otp = value;
                  _verify();
                },
                onChanged: (value) => setState(() {
                  _otp = value;
                  _error = null;
                }),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: AppTypography.bodySmall
                      .copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 40),
              NmGradientButton(
                label: l10n.authVerifyAndContinue,
                icon: Icons.check_circle_outline_rounded,
                isLoading: isLoading,
                // Enabled on any entered code, not only a full one: the
                // verifier accepts any non-empty code while it is the
                // development one, and an empty field is answered with the
                // inline error above rather than a dead button.
                onPressed: isLoading ? null : _verify,
              ),
              const SizedBox(height: 32),
              Center(
                child: _secondsRemaining > 0
                    ? Column(
                        children: [
                          Text(
                            l10n.authResendOtpIn,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textTertiaryLight,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '00:${_secondsRemaining.toString().padLeft(2, '0')}',
                            style: AppTypography.titleLarge.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      )
                    : TextButton.icon(
                        onPressed: isLoading ? null : _resend,
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
