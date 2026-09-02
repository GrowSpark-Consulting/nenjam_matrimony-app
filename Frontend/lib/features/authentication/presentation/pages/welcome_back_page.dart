import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/network/api_providers.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/buttons/icon_button.dart';
import '../../../../core/widgets/buttons/social_button.dart';
import '../../../../core/widgets/inputs/phone_field.dart';
import '../../../../core/widgets/layout/or_divider.dart';
import '../../../../core/widgets/layout/responsive_layout.dart';
import '../../../../core/widgets/system_ui/nm_status_bar_style.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/services/backend_sync_service.dart';
import '../../../registration/presentation/providers/registration_provider.dart';
import '../controllers/login_controller.dart';
import '../utils/post_auth_destination.dart';

/// "Welcome back" — the one login screen.
///
/// Replaces the tabbed Login / Sign Up page as the login entry: sign-up is
/// its own screen now, reached from the landing page or from the link at the
/// bottom of this one, so neither flow has to explain the other.
///
/// Owns no authentication of its own. Mobile hands off to the existing OTP
/// screen, Google runs [GoogleSignInController], and password and email open
/// the forms that already implement them. Every route out of here ends at
/// [PostAuthDestination], so a member with onboarding still to finish
/// resumes it rather than landing in an empty app.
class WelcomeBackPage extends ConsumerStatefulWidget {
  const WelcomeBackPage({super.key});

  @override
  ConsumerState<WelcomeBackPage> createState() => _WelcomeBackPageState();
}

class _WelcomeBackPageState extends ConsumerState<WelcomeBackPage> {
  final _mobileCtrl = TextEditingController();
  String _dialCode = '+91';

  /// Covers the backend sync and destination lookup that follow a Google
  /// sign-in — [GoogleSignInController]'s own flag only spans the picker.
  bool _resolving = false;

  @override
  void dispose() {
    _mobileCtrl.dispose();
    super.dispose();
  }

  bool get _mobileValid => RegExp(r'^\d{10}$').hasMatch(_mobileCtrl.text.trim());

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.registrationLanding);
    }
  }

  /// Hands the number to the existing login-OTP screen, which sends the code
  /// and signs in. Stashed the same way the sign-up phone flow stashes it,
  /// so that screen finds it however it was reached.
  Future<void> _getOtp() async {
    if (!_mobileValid) return;
    await storageService.setPendingPhone('$_dialCode${_mobileCtrl.text.trim()}');
    if (!mounted) return;
    context.push(RouteNames.loginOtp);
  }

  Future<void> _google() async {
    if (_resolving) return;
    final l10n = AppLocalizations.of(context);

    final result =
        await ref.read(googleSignInControllerProvider.notifier).signIn();
    if (!mounted) return;

    // Dismissing the account picker is a decision, not a fault.
    if (result.cancelled) return;
    if (!result.success) {
      _snack(result.errorMessage ?? l10n.authGenericError);
      return;
    }

    // Awaited, unlike other call sites: this is the one path that asks the
    // backend about an account it may have learned of milliseconds ago. It
    // never throws, so awaiting cannot turn a good sign-in into a failure.
    setState(() => _resolving = true);
    await syncUserWithBackend(ref.read(apiClientProvider));
    final route = await ref.read(postAuthDestinationProvider).resolve();
    if (!mounted) return;
    setState(() => _resolving = false);
    context.go(route);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final googleBusy =
        ref.watch(googleSignInControllerProvider) || _resolving;

    return NmPageStatusBar(
      background: theme.scaffoldBackgroundColor,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: NmIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: l10n.registrationBack,
                      onPressed: _back,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.xl,
                    ),
                    child: NmContentConstraint(
                      maxWidth: 480,
                      child: Column(
                        children: [
                          const _NenjamMark(),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            l10n.welcomeBackHeadline,
                            textAlign: TextAlign.center,
                            style: AppTypography.headlineMedium.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            l10n.welcomeBackSubtitle,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMedium
                                .copyWith(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          NmPhoneNumberField(
                            controller: _mobileCtrl,
                            initialCountryCode: _dialCode,
                            onCountryChanged: (c) =>
                                setState(() => _dialCode = c.code),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          NmGradientButton(
                            label: l10n.welcomeBackGetOtp,
                            onPressed: _mobileValid ? _getOtp : null,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextButton(
                            // The password form already exists; this screen
                            // does not reimplement it.
                            //
                            // `loginForm`, not `login`: RouteNames.login builds
                            // THIS page, so pushing it stacked a second copy of
                            // the screen the member was already looking at and
                            // the button read as dead. The form lives behind
                            // `loginForm`, which opens LoginPage on tab 0
                            // (Login) — the `{'mode': ...}` payload it used to
                            // send was never read by that route's builder.
                            onPressed: () => context.push(
                              RouteNames.loginForm,
                              extra: const {'tab': 0},
                            ),
                            child: Text(l10n.welcomeBackPassword),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          const NmOrDivider(),
                          const SizedBox(height: AppSpacing.base),
                          NmSocialButton(
                            label: l10n.welcomeBackGoogle,
                            isLoading: googleBusy,
                            onPressed: _google,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          NmSocialButton(
                            label: l10n.welcomeBackEmail,
                            iconWidget: Icon(
                              Icons.mail_outline_rounded,
                              size: AppSpacing.lg,
                              color: colors.primary,
                            ),
                            // Same correction as the password button above:
                            // this pushed RouteNames.login, which is this very
                            // page, so "Continue with Email" went nowhere.
                            onPressed: googleBusy
                                ? null
                                : () => context.push(
                                      RouteNames.loginForm,
                                      extra: const {'tab': 0},
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.base,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        l10n.welcomeBackNoAccount,
                        style: AppTypography.bodySmall
                            .copyWith(color: colors.onSurfaceVariant),
                      ),
                      TextButton(
                        // Straight into onboarding — there is no credential
                        // form in front of it any more.
                        onPressed: () {
                          ref
                              .read(registrationProvider.notifier)
                              .startCreateMode();
                          context.go(RouteNames.createProfileFor);
                        },
                        child: Text(l10n.welcomeBackSignUpFree),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Nenjam mark — the rounded-square favorite badge the splash and
/// landing screens already use. There is no logo image asset in the project;
/// this treatment is the lockup.
class _NenjamMark extends StatelessWidget {
  const _NenjamMark();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: AppSpacing.xl4,
      height: AppSpacing.xl4,
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(AppSpacing.base),
      ),
      child: Icon(
        Icons.favorite_rounded,
        size: AppSpacing.xl,
        color: colors.onPrimary,
      ),
    );
  }
}
