import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/buttons/icon_button.dart';
import '../../../../core/widgets/inputs/otp_input.dart';
import '../../../../core/widgets/layout/responsive_layout.dart';
import '../../../../core/widgets/system_ui/nm_status_bar_style.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/errors/auth_error_mapper.dart';
import '../../../authentication/domain/services/otp_verifier.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../providers/registration_provider.dart';
import '../widgets/onboarding_scaffold.dart';

/// Step 10 — "Verify Mobile Number", the last screen before Discover.
///
/// Verification goes through [OtpVerifier], which is currently wired to
/// [MockOtpVerifier]: **no SMS is sent and no OTP provider is called.** The
/// screen, the flow position and the state it writes are all real, so
/// swapping the provider override turns real verification on without
/// touching this file.
///
/// The production phone-auth stack is untouched and still drives the sign-up
/// and login phone screens.
class OnboardingVerifyMobilePage extends ConsumerStatefulWidget {
  const OnboardingVerifyMobilePage({super.key});

  @override
  ConsumerState<OnboardingVerifyMobilePage> createState() =>
      _OnboardingVerifyMobilePageState();
}

class _OnboardingVerifyMobilePageState
    extends ConsumerState<OnboardingVerifyMobilePage> {
  String _otp = '';
  String _phone = '';
  bool _verifying = false;
  bool _wrongCode = false;

  @override
  void initState() {
    super.initState();
    _phone = storageService.pendingPhone ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_phone.isNotEmpty) ref.read(otpVerifierProvider).send(_phone);
    });
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.onboardingAbout);
    }
  }

  /// Editing the number means verifying the new one, which the Email +
  /// Mobile step already owns — so Edit returns there rather than growing a
  /// second number field here.
  void _edit() => context.go(RouteNames.onboardingContact);

  Future<void> _verify() async {
    final verifier = ref.read(otpVerifierProvider);
    if (_otp.length != verifier.codeLength || _verifying) return;
    setState(() {
      _verifying = true;
      _wrongCode = false;
    });

    final ok = await verifier.verify(_otp);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _verifying = false;
        _wrongCode = true;
      });
      return;
    }

    // Onboarding collected a whole profile without ever asking for a
    // credential, so at this point there is no Firebase session — and
    // Discover, like every authenticated route, correctly refuses one.
    // Without this the router's guard bounced the member straight back to
    // the landing screen the instant they finished.
    //
    // An anonymous session is a real session with a real uid: it satisfies
    // the guard, lets the accumulated draft reach the backend, and can be
    // upgraded in place (linkWithCredential) once a credential is added.
    // No SMS, no password, no billing.
    if (!_hasSession()) {
      try {
        await ref.read(authRepositoryProvider).signInAnonymously();
      } catch (e) {
        if (!mounted) return;
        setState(() => _verifying = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(AuthErrorMapper.message(e))));
        return;
      }
    }

    // Now that a session exists, the answers gathered while signed out can
    // finally be sent. Best-effort — the local draft stays the source of
    // truth if this fails.
    await ref.read(registrationProvider.notifier).flushOnboardingToBackend();

    // Onboarding is finished. The number stops being "pending" the moment
    // it is verified.
    await storageService.clearPendingPhone();
    if (!mounted) return;
    context.go(RouteNames.discover);
  }

  /// Whether Firebase already has a session. Guarded: reading the auth
  /// service before Firebase is initialised throws, and "cannot tell" has to
  /// mean "sign in", never a crash on the last step of onboarding.
  bool _hasSession() {
    try {
      return ref.read(firebaseAuthServiceProvider).currentUser != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final length = ref.watch(otpVerifierProvider).codeLength;

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
                      maxWidth: OnboardingScaffold.contentMaxWidth,
                      child: Column(
                        children: [
                          const Center(
                            child: OnboardingCrest(
                              icon: Icons.verified_user_rounded,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            l10n.onboardingVerifyMobileHeadline,
                            textAlign: TextAlign.center,
                            style: AppTypography.headlineSmall.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            l10n.onboardingVerifyMobileSentTo,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMedium
                                .copyWith(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                _phone,
                                style: AppTypography.titleMedium.copyWith(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextButton(
                                onPressed: _verifying ? null : _edit,
                                child: Text(l10n.onboardingVerifyMobileEdit),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          NmOtpInput(
                            length: length,
                            onCompleted: (value) {
                              _otp = value;
                              _verify();
                            },
                            onChanged: (value) => setState(() {
                              _otp = value;
                              _wrongCode = false;
                            }),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            _wrongCode
                                ? l10n.authInvalidOtp
                                : l10n.onboardingVerifyMobileEnter,
                            textAlign: TextAlign.center,
                            style: AppTypography.labelSmall.copyWith(
                              color: _wrongCode
                                  ? colors.error
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                OnboardingFooter(
                  child: NmGradientButton(
                    label: l10n.authVerifyAndContinue,
                    icon: Icons.arrow_forward_rounded,
                    isLoading: _verifying,
                    onPressed: _otp.length == length ? _verify : null,
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
