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
import '../../../authentication/domain/services/local_auth_session.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../authentication/domain/services/otp_verifier.dart';
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

    // Reaching here means the verifier said yes. With real phone auth that is
    // FirebasePhoneOtpVerifier, so a Firebase session already exists: the
    // credential either signed the member in or was linked to the account
    // they already had, and the router guard sees a genuine user from here.
    //
    // With the dummy OTP there is no credential to exchange, so this opens a
    // LocalAuthSession instead — the same thing the mobile login paths do
    // (see LoginController), for the same reason. Without it a member finished
    // onboarding in a state the app treated as signed out: the flush below
    // sent nothing, no `user_profiles` row was ever written, and every screen
    // afterwards answered 401. Opening it *before* the flush is what makes
    // that flush authenticate.
    final phone = storageService.pendingPhone;
    if (phone != null && phone.isNotEmpty) {
      await ref.read(localAuthSessionProvider).start(
            identifier: phone,
            method: LocalAuthMethod.mobileOtp,
          );
    }

    // Still written for the router's own local-completion bridge, and cleared
    // on sign-out along with everything else.
    await storageService.setOnboardingCompleted(true);

    // Now that a session exists, the answers gathered along the way are sent
    // with a credential attached, so the backend can provision the internal
    // User row and materialize the profile.
    await ref.read(registrationProvider.notifier).flushOnboardingToBackend();

    // Onboarding is finished. The number stops being "pending" the moment
    // it is verified.
    await storageService.clearPendingPhone();
    if (!mounted) return;
    context.go(RouteNames.discover);
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
