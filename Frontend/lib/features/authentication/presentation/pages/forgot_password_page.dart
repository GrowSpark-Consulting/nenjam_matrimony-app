import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../controllers/forgot_password_controller.dart';

/// Forgot Password screen.
///
/// Collects the registered email, validates it, and asks Firebase to send a
/// password-reset link via [FirebaseAuth.sendPasswordResetEmail]. Handles
/// initial / loading / success / error states. The app never sets or stores a
/// password — Firebase owns the reset token and the new password.
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Reset any stale state from a previous visit.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(forgotPasswordControllerProvider.notifier).reset();
      final extra = GoRouterState.of(context).extra;
      if (extra is Map && extra['email'] is String) {
        _emailCtrl.text = extra['email'] as String;
      }
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(forgotPasswordControllerProvider.notifier)
        .sendResetLink(_emailCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(forgotPasswordControllerProvider);

    ref.listen<ForgotPasswordState>(forgotPasswordControllerProvider,
        (prev, next) {
      if (next.status == ForgotPasswordStatus.error &&
          next.errorMessage != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.authForgotPasswordTitle,
          style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: state.isSuccess
              ? _SuccessView(email: _emailCtrl.text.trim())
              : _FormView(
                  formKey: _formKey,
                  emailCtrl: _emailCtrl,
                  isLoading: state.isLoading,
                  onSubmit: _submit,
                ),
        ),
      ),
    );
  }
}

class _FormView extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final bool isLoading;
  final VoidCallback onSubmit;

  const _FormView({
    required this.formKey,
    required this.emailCtrl,
    required this.isLoading,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_reset_rounded,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            l10n.authForgotPasswordTitle,
            style: AppTypography.headlineMedium
                .copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.authForgotPasswordSubtitle,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondaryLight,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.authEmailAddress,
              style: AppTypography.labelLarge,
            ),
          ),
          const SizedBox(height: 8),
          NmTextField(
            controller: emailCtrl,
            hint: 'name@example.com',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            validator: Validators.email,
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 28),
          NmPrimaryButton(
            label: l10n.authSendResetLink,
            icon: Icons.send_rounded,
            isLoading: isLoading,
            onPressed: onSubmit,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              l10n.authBackToLogin,
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  final String email;
  const _SuccessView({required this.email});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            size: 44,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: 28),
        Text(
          l10n.authResetEmailSentTitle,
          style:
              AppTypography.headlineMedium.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.authResetEmailSent,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondaryLight,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        if (email.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            email,
            style: AppTypography.bodyMedium
                .copyWith(fontWeight: FontWeight.w700, color: AppColors.primary),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 36),
        NmPrimaryButton(
          label: l10n.authBackToLogin,
          icon: Icons.arrow_back_rounded,
          onPressed: () => context.pop(),
        ),
      ],
    );
  }
}
