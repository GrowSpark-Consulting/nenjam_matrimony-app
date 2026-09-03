import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/animations/app_animations.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/auth_trace.dart';
import '../../../../core/widgets/buttons/icon_button.dart';
import '../../../../core/widgets/buttons/outlined_button.dart';
import '../../../../core/widgets/buttons/social_button.dart';
import '../../../../core/widgets/system_ui/nm_status_bar_style.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../registration/presentation/providers/registration_provider.dart';

/// Breakpoint above which the hero moves beside the actions rather than
/// above them — the value the previous auth-selection screen used, so
/// tablets and landscape phones keep the layout they already had.
const double _kLandscapeBreakpoint = 600;

/// Which sign-up button the member pressed: email or mobile.
///
/// It does NOT select a login screen or a credential form. This screen once
/// pushed [LoginPage] with the chosen field focused, and that is exactly the
/// behaviour "Sign up with Email lands on Login" describes — it was replaced
/// by [_signUpWith], which routes straight into onboarding. Nothing reads
/// this value to decide a route; only the Email + Mobile step reads it, and
/// only to prefill.
enum SignUpFocus { email, mobile }

/// Which sign-up button the member pressed, for the duration of onboarding.
///
/// Not a parallel state system — a single value the Email + Mobile step reads
/// to know which identifier it already has and which it still needs. Null
/// when onboarding was not entered from a sign-up button (a resumed session,
/// say), which that step treats as "prefill whatever the account carries".
final signupMethodProvider = StateProvider<SignUpFocus?>((ref) => null);

/// The first screen a logged-out user sees after the splash.
///
/// Two ways in (email, mobile) plus a distinct Login affordance for people
/// who already have an account. Every action routes into a flow that already
/// exists, and this screen now owns no authentication logic at all — both
/// sign-up buttons route straight into onboarding.
///
/// Signing up with Google was a third button here and has been withdrawn from
/// the product. Only the sign-up entry point is gone: `GoogleSignInController`
/// and `GoogleAuthIntent` are untouched and still drive "Continue with
/// Google" on the Login screen, so restoring this button later is a matter of
/// re-adding it, not of rebuilding the integration.
class RegistrationLandingPage extends ConsumerStatefulWidget {
  const RegistrationLandingPage({super.key});

  @override
  ConsumerState<RegistrationLandingPage> createState() =>
      _RegistrationLandingPageState();
}

class _RegistrationLandingPageState
    extends ConsumerState<RegistrationLandingPage> {
  /// Both sign-up buttons go straight to the first onboarding step.
  ///
  /// There is no credential form in front of onboarding: the member is asked
  /// for an email and a mobile part-way through (the Email + Mobile step),
  /// not before they have seen a single question. The chosen method is
  /// recorded so that step can prefill the identifier they picked.
  void _signUpWith(SignUpFocus focus) {
    AuthTrace.intent(channel: focus.name, intent: 'SIGNUP');
    AuthTrace.unauthenticated(focus.name);
    ref.read(signupMethodProvider.notifier).state = focus;
    ref.read(registrationProvider.notifier).startCreateMode();
    AuthTrace.destination(RouteNames.createProfileFor);
    AuthTrace.navigate(RouteNames.createProfileFor, reason: 'signup intent');
    context.go(RouteNames.createProfileFor);
  }

  /// Straight to the login form. There is no screen in between choosing
  /// login and being asked for a credential — this screen is already the
  /// place the two paths part.
  void _login() {
    AuthTrace.intent(channel: 'form', intent: 'LOGIN');
    AuthTrace.navigate(RouteNames.loginForm, reason: 'Log In button');
    context.push(RouteNames.loginForm);
  }

  /// Where Back goes, for both the arrow and the Android system gesture —
  /// one definition so the two can never disagree.
  void _back() => context.go(RouteNames.language);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return NmPageStatusBar(
      background: AppGradients.splash.colors.first,
      child: PopScope(
        // Reached via `go` (which replaces the whole stack), so there is no
        // page underneath to pop back to. Without this, Back would fall
        // through to SystemNavigator.pop and quit the app; Language
        // Selection is the screen that genuinely precedes this one, and is
        // where the auth-selection screen this replaced also sent Back.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Scaffold(
          backgroundColor: AppColors.surfaceLight,
          body: Stack(
            children: [
              LayoutBuilder(
            builder: (context, constraints) {
              final isLandscape =
                  constraints.maxWidth > constraints.maxHeight &&
                  constraints.maxWidth >= _kLandscapeBreakpoint;

              final hero = _BrandHero(l10n: l10n, compact: isLandscape);
              final actions = _LandingActions(
                l10n: l10n,
                onSignUpEmail: () => _signUpWith(SignUpFocus.email),
                onSignUpMobile: () => _signUpWith(SignUpFocus.mobile),
                onLogin: _login,
              );

              // The hero bleeds to the screen edge it sits against, and the
              // actions column takes only the insets that are genuinely
              // screen edges on its own side, so neither double-pads.
              if (isLandscape) {
                return Row(
                  children: [
                    Expanded(flex: 5, child: hero),
                    Expanded(
                      flex: 6,
                      child: SafeArea(left: false, child: actions),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  Expanded(flex: 7, child: hero),
                  Expanded(
                    flex: 13,
                    child: SafeArea(top: false, child: actions),
                  ),
                ],
              );
                },
              ),
              // Layered over the hero rather than placed in the column: the
              // hero bleeds to the screen edge in both orientations, and an
              // arrow in the flow would either push it down or eat into the
              // lockup's breathing room. White, because it always sits on
              // the brand gradient.
              PositionedDirectional(
                top: 0,
                start: AppSpacing.sm,
                child: SafeArea(
                  child: NmIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: l10n.registrationBack,
                    color: AppColors.textOnPrimary,
                    onPressed: _back,
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

/// Logo, app name, and the one-line promise, on the brand gradient.
///
/// The logo is the app's existing mark — the same rounded-square favorite
/// badge the splash and registration-welcome screens use. There is no logo
/// image asset in the project; this treatment is the Nenjam lockup.
class _BrandHero extends StatelessWidget {
  const _BrandHero({required this.l10n, required this.compact});

  final AppLocalizations l10n;

  /// True when rendered beside the actions rather than above them, which
  /// trims the vertical rhythm so the lockup doesn't dominate a short
  /// viewport.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: AppGradients.splash,
        borderRadius: compact
            ? const BorderRadius.only(topRight: Radius.circular(40))
            : const BorderRadius.only(
                bottomLeft: Radius.circular(40),
                bottomRight: Radius.circular(40),
              ),
      ),
      child: SafeArea(
        right: !compact,
        bottom: compact,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Scales with the hero's shorter side so the mark stays
                // proportionate from small phones to tablets.
                final logoSize = (constraints.biggest.shortestSide * 0.30)
                    .clamp(64.0, 112.0);

                // FittedBox lets the whole lockup shrink as one unit when
                // the viewport is short or the system font is scaled up,
                // instead of overflowing.
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AppAnimations.fade(
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: logoSize,
                          height: logoSize,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(
                              logoSize * 0.28,
                            ),
                          ),
                          child: Icon(
                            Icons.favorite_rounded,
                            size: logoSize * 0.48,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          l10n.appName,
                          textAlign: TextAlign.center,
                          style: AppTypography.headlineLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          l10n.registrationLandingHeadline,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyLarge.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// "New to Nenjam?" plus the two sign-up routes, then the Login section.
///
/// Scrollable with a min-height floor rather than a fixed layout: at the
/// largest system font sizes the buttons and their labels genuinely do not
/// fit a small phone, and scrolling is the only answer that neither
/// truncates the copy nor throws a RenderFlex overflow.
class _LandingActions extends StatelessWidget {
  const _LandingActions({
    required this.l10n,
    required this.onSignUpEmail,
    required this.onSignUpMobile,
    required this.onLogin,
  });

  final AppLocalizations l10n;
  final VoidCallback onSignUpEmail;
  final VoidCallback onSignUpMobile;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.lg,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _SignUpSection(
                          l10n: l10n,
                          onSignUpEmail: onSignUpEmail,
                          onSignUpMobile: onSignUpMobile,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _LoginSection(l10n: l10n, onLogin: onLogin),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SignUpSection extends StatelessWidget {
  const _SignUpSection({
    required this.l10n,
    required this.onSignUpEmail,
    required this.onSignUpMobile,
  });

  final AppLocalizations l10n;
  final VoidCallback onSignUpEmail;
  final VoidCallback onSignUpMobile;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.registrationLandingNewTo,
          textAlign: TextAlign.center,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimaryLight,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppAnimations.slide(
          Semantics(
            button: true,
            label: l10n.registrationLandingSignUpEmail,
            child: NmSocialButton(
              label: l10n.registrationLandingSignUpEmail,
              iconWidget: const Icon(
                Icons.mail_outline_rounded,
                size: 22,
                color: AppColors.primary,
              ),
              onPressed: onSignUpEmail,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppAnimations.slide(
          Semantics(
            button: true,
            label: l10n.registrationLandingSignUpMobile,
            child: NmSocialButton(
              label: l10n.registrationLandingSignUpMobile,
              iconWidget: const Icon(
                Icons.smartphone_rounded,
                size: 22,
                color: AppColors.primary,
              ),
              onPressed: onSignUpMobile,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginSection extends StatelessWidget {
  const _LoginSection({required this.l10n, required this.onLogin});

  final AppLocalizations l10n;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.registrationLandingHaveAccount,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Outlined rather than a fourth filled card: visually distinct from
        // the three sign-up routes above (which are this screen's primary
        // intent) while still drawn from the same button family.
        NmOutlinedButton(
          label: l10n.authLogin,
          icon: Icons.login_rounded,
          onPressed: onLogin,
        ),
      ],
    );
  }
}
