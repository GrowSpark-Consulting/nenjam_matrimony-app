import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../registration/presentation/providers/registration_provider.dart';
import '../controllers/signup_controller.dart';
import '../providers/auth_providers.dart';

/// Email Verification screen.
///
/// Firebase sends a verification *link* (not an OTP). We poll
/// `currentUser.emailVerified` every few seconds and also offer a manual
/// "I've verified" check and a throttled "Resend email". On success we move
/// on to phone verification.
class EmailVerifyScreen extends ConsumerStatefulWidget {
  const EmailVerifyScreen({super.key});

  @override
  ConsumerState<EmailVerifyScreen> createState() => _EmailVerifyScreenState();
}

class _EmailVerifyScreenState extends ConsumerState<EmailVerifyScreen> {
  Timer? _pollTimer;
  Timer? _resendTimer;
  bool _checking = false;
  int _resendCooldown = 0;

  @override
  void initState() {
    super.initState();
    // Poll every 4s for the link being tapped in the inbox.
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _checkVerified(silent: true),
    );
    _startResendCooldown();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendCooldown = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendCooldown <= 1) {
        t.cancel();
        if (mounted) setState(() => _resendCooldown = 0);
      } else {
        if (mounted) setState(() => _resendCooldown--);
      }
    });
  }

  Future<void> _checkVerified({bool silent = false}) async {
    if (_checking) return;
    if (!silent) setState(() => _checking = true);
    final verified =
        await ref.read(authRepositoryProvider).checkEmailVerified();
    if (!mounted) return;
    if (!silent) setState(() => _checking = false);
    if (verified) {
      _pollTimer?.cancel();
      // Phone OTP verification is disabled for now — go straight into the app
      // once the email is verified.
      storageService.clearPendingPhone();
      ref.read(signupControllerProvider.notifier).reset();
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.authEmailVerifiedSuccess),
          backgroundColor: AppColors.success,
        ),
      );
      // Always CREATE MODE here — guarantees no stale draft/mode leaks in
      // from a previous session (e.g. a prior user's edit on a shared device).
      ref.read(registrationProvider.notifier).startCreateMode();
      context.go(RouteNames.registrationWelcome);
    } else if (!silent) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.authEmailNotVerifiedYet)),
      );
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(authRepositoryProvider).resendEmailVerification();
      _startResendCooldown();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.authVerificationEmailSent)),
      );
    } catch (_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.authGenericError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final email =
        ref.watch(firebaseAuthServiceProvider).currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            // Always reached via `context.go` (never pushed), so there is
            // no pop stack to fall back on — return to Login explicitly.
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(RouteNames.login);
            }
          },
        ),
        title: Text(
          l10n.authVerifyEmailTitle,
          style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_unread_outlined,
                  size: 40,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                l10n.authVerifyEmailTitle,
                style: AppTypography.headlineMedium
                    .copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.authVerifyEmailSentTo(email),
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondaryLight,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.authVerifyEmailInstruction,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textTertiaryLight,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              NmGradientButton(
                label: l10n.authIveVerified,
                icon: Icons.check_circle_outline_rounded,
                isLoading: _checking,
                onPressed: () => _checkVerified(),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _resendCooldown > 0 ? null : _resend,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  _resendCooldown > 0
                      ? l10n.authResendEmailIn(_resendCooldown.toString())
                      : l10n.authResendEmail,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  textStyle: AppTypography.labelLarge
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
