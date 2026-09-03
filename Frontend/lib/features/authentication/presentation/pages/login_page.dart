import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_providers.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/buttons/icon_button.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/buttons/social_button.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../core/widgets/inputs/password_field.dart';
import '../../../../core/widgets/layout/curved_header.dart';
import '../../../../core/widgets/layout/or_divider.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/services/storage_service.dart';
import '../../data/services/backend_sync_service.dart';
import '../../domain/services/login_identifier.dart';
import '../../domain/services/otp_verifier.dart';
import '../controllers/login_controller.dart';
import '../providers/auth_providers.dart';
import '../utils/post_auth_destination.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Login Page (Root)
// ═══════════════════════════════════════════════════════════════════════════

/// Which credential the Login tab opens on.
///
/// The three login entry points on "Welcome back" all land on this one
/// form; this is what makes them arrive somewhere different.
enum LoginFormMode {
  /// Mobile number → OTP. The tab's own default.
  mobileOtp,

  /// Email address + password ("Continue with Email").
  email,

  /// A single field taking **either** an email address or a mobile number,
  /// plus a password. The Mobile / Email segmented control is hidden here —
  /// the field itself covers both, so choosing a channel first would only
  /// be a question the form can answer for the user.
  ///
  /// **No button opens this today, by decision, not by oversight.** It was
  /// reached from the "Login with Password" link on the Welcome Back
  /// screen, and login is the two channels above now; the mode is entered
  /// only by routing to [RouteNames.loginForm] with
  /// `extra: {'mode': 'identifier'}`. It is kept whole — with
  /// [LoginController.loginWithIdentifier] and its tests — because it is
  /// the only mobile + password implementation there is, and nothing
  /// selects it by accident. Adding a CTA is the one line that brings it
  /// back.
  identifier,
}

/// The login screen — login only, backed by Firebase.
///
/// Sign-up is not offered here and has no CTA on this screen: it starts from
/// the landing screen ([RegistrationLandingPage]), which owns all three
/// sign-up buttons and leads into onboarding. Keeping the two apart is what
/// lets this screen ask one question — "which credential?" — instead of two.
///
/// Mobile hands off to the OTP screen, Email and the identifier mode
/// authenticate here, and Google runs [GoogleSignInController]. Every route
/// out ends at Discover, or at [PostAuthDestination] when a Firebase
/// session makes a resumable onboarding step knowable.
class LoginPage extends ConsumerStatefulWidget {
  /// Which credential the form opens on. Defaults to the mobile-OTP channel
  /// it has always opened on.
  final LoginFormMode mode;

  const LoginPage({
    super.key,
    this.mode = LoginFormMode.mobileOtp,
  });

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _loginFormKey = GlobalKey<FormState>();
  final _loginPhoneCtrl = TextEditingController();
  final _loginEmailCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();

  /// The single "email or mobile number" field used by
  /// [LoginFormMode.identifier].
  final _loginIdentifierCtrl = TextEditingController();

  @override
  void dispose() {
    _loginPhoneCtrl.dispose();
    _loginEmailCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _loginIdentifierCtrl.dispose();
    super.dispose();
  }

  void _snack(String message, {Color? color}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  // ─── Login: Email + Password ───────────────────────────────────────
  Future<void> _onLoginEmail() async {
    if (!(_loginFormKey.currentState?.validate() ?? false)) return;
    final result = await ref
        .read(loginControllerProvider.notifier)
        .loginWithEmail(
          email: _loginEmailCtrl.text.trim(),
          password: _loginPasswordCtrl.text,
        );
    if (!mounted) return;
    if (!result.success) {
      _snack(
        result.errorMessage ?? AppLocalizations.of(context).authGenericError,
      );
      return;
    }
    await _routeAfterLogin(result.needsVerification);
  }

  // ─── Login: Mobile OTP ─────────────────────────────────────────────
  //
  // Requests the code through [OtpVerifier] — currently [MockOtpVerifier],
  // so nothing is sent and no provider is contacted — and hands the number
  // to the OTP screen the same way "Welcome back" does, so both entry
  // points reach one implementation.
  Future<void> _onLoginMobile() async {
    if (!(_loginFormKey.currentState?.validate() ?? false)) return;
    final phone = '+91${_loginPhoneCtrl.text.trim()}';
    await storageService.setPendingPhone(phone);
    await ref.read(otpVerifierProvider).send(phone);
    if (!mounted) return;
    context.push(RouteNames.loginOtp, extra: {'phone': phone});
  }

  // ─── Login: Email or Mobile + Password ─────────────────────────────
  //
  // Which of the two it is, and which credential check that implies, is
  // [LoginController.loginWithIdentifier]'s decision — this screen only
  // collects the two fields.
  Future<void> _onLoginIdentifier() async {
    if (!(_loginFormKey.currentState?.validate() ?? false)) return;
    final result = await ref
        .read(loginControllerProvider.notifier)
        .loginWithIdentifier(
          identifier: _loginIdentifierCtrl.text,
          password: _loginPasswordCtrl.text,
        );
    if (!mounted) return;
    if (!result.success) {
      _snack(
        result.errorMessage ?? AppLocalizations.of(context).authGenericError,
      );
      return;
    }
    // A mobile + password login has no Firebase user to resolve a
    // destination from — it opened a LocalAuthSession instead — so it goes
    // straight to Discover. An email login has one, and takes the same
    // route every other Firebase sign-in takes.
    if (result.user == null) {
      context.go(RouteNames.discover);
      return;
    }
    await _routeAfterLogin(result.needsVerification);
  }

  // ─── Login: Google ─────────────────────────────────────────────────
  //
  // LOGIN intent. An established member goes to Discover and a member
  // part-way through registration resumes their step — but a Google identity
  // with no account behind it is NOT enrolled into signup here. That is what
  // this button used to do: it ran exactly the same code as the Sign Up
  // button, so tapping "Log In" with an unregistered Google account dropped
  // the member into Profile For and a full onboarding they never chose.
  Future<void> _onLoginGoogle() async {
    final l10n = AppLocalizations.of(context);
    final result = await ref
        .read(googleSignInControllerProvider.notifier)
        .signIn(intent: GoogleAuthIntent.login);
    if (!mounted) return;
    // Dismissing the account picker is a decision, not a fault — return to
    // idle silently rather than accusing the user of an error.
    if (result.cancelled) return;
    if (!result.success) {
      _snack(result.errorMessage ?? l10n.authGenericError);
      return;
    }

    if (result.needsVerification) {
      await _routeAfterLogin(true);
      return;
    }

    // Best-effort: mirrors this Firebase session into the NestJS + Postgres
    // backend. Awaited here, unlike the other login paths, because the very
    // next thing this does is ask that backend whether the account exists —
    // a row it may have learned of milliseconds ago. It never throws, so
    // awaiting it cannot turn a successful sign-in into a failure.
    await syncUserWithBackend(ref.read(apiClientProvider));
    final route = await ref.read(postAuthDestinationProvider).resolve();
    if (!mounted) return;

    // `createProfileFor` is what the resolver returns when the account has
    // answered *nothing* — no finalized profile, no draft. On the signup
    // path that is a new member starting out; on the login path it means
    // there is no Nenjam account behind this Google identity, and beginning
    // a 13-step signup is not what "Log In" asked for. Say so, and leave the
    // choice on the screen that owns it.
    if (route == RouteNames.createProfileFor) {
      _snack(l10n.authGoogleNoAccount);
      context.go(RouteNames.registrationLanding);
      return;
    }

    // Everything else is a real member: Discover when registration is
    // finished, or the step they stopped on when it is not.
    context.go(route);
  }

  Future<void> _routeAfterLogin(bool needsVerification) async {
    // Best-effort: mirrors this Firebase session into the NestJS + Postgres
    // backend. Never awaited — must not block or fail the navigation below.
    unawaited(syncUserWithBackend(ref.read(apiClientProvider)));

    if (needsVerification) {
      // Send the user to whichever verification step is still outstanding.
      final emailVerified =
          ref.read(firebaseAuthServiceProvider).currentUser?.emailVerified ??
          false;
      context.go(
        emailVerified ? RouteNames.verifyPhone : RouteNames.verifyEmail,
      );
      return;
    }

    // Verified is not the same as registered: a signed-in account with a
    // half-finished (or absent) profile belongs back in the registration
    // flow, not in Discover with nothing to show. PostAuthDestination is
    // the single place that decision is made — see its doc comment.
    final route = await ref.read(postAuthDestinationProvider).resolve();
    if (!mounted) return;
    context.go(route);
  }


  @override
  Widget build(BuildContext context) {
    final loginLoading = ref.watch(loginControllerProvider);
    final googleLoading = ref.watch(googleSignInControllerProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
        body: Stack(
          children: [
            // One scroll view for the whole screen. The tabbed version
            // needed a NestedScrollView so the pinned tab bar could sit
            // between the header and two independently scrolling forms;
            // with one form and no tab bar there is nothing left to nest,
            // and a single scroll view is also what keeps the keyboard from
            // fighting an inner scrollable for the focused field.
            SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                children: [
                  const _LoginHeader(),
                  _FormCard(
                    child: _LoginForm(
                      formKey: _loginFormKey,
                      mode: widget.mode,
                      phoneCtrl: _loginPhoneCtrl,
                      emailCtrl: _loginEmailCtrl,
                      identifierCtrl: _loginIdentifierCtrl,
                      passwordCtrl: _loginPasswordCtrl,
                      isLoading: loginLoading,
                      isGoogleLoading: googleLoading,
                      onLoginEmail: _onLoginEmail,
                      onLoginMobile: _onLoginMobile,
                      onLoginIdentifier: _onLoginIdentifier,
                      onLoginGoogle: _onLoginGoogle,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _TrustBadges(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
            // Login is reached both as a flow root (via `go` after Splash/
            // OTP — nothing to pop to) and pushed from the landing screen
            // (via `push`, where the user needs a way back) — only show a
            // back affordance when there's actually something to pop.
            // White icon: this overlays NmCurvedHeader's plum background.
            if (context.canPop())
              Positioned(
                top: MediaQuery.paddingOf(context).top,
                left: 4,
                child: NmIconButton(
                  icon: Icons.arrow_back_rounded,
                  onPressed: () => context.pop(),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Headers
// ═══════════════════════════════════════════════════════════════════════════

class _LoginHeader extends StatelessWidget {
  const _LoginHeader();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NmCurvedHeader(
      title: l10n.appName,
      subtitle: l10n.authWelcomeBack,
      badgeIcon: Icons.favorite_rounded,
    );
  }
}


// ═══════════════════════════════════════════════════════════════════════════
// Card Content
// ═══════════════════════════════════════════════════════════════════════════


/// The white card the form sits on.
///
/// Rounded on all four corners, where it used to be rounded only at the
/// bottom: the tab bar drew the top edge and the top two corners, sitting
/// flush between the curved header and this card. With the tab bar gone a
/// bottom-only radius would read as a card whose top had been cut off, so
/// the shape is completed here — same margin, same fill, same shadow, one
/// rounded rectangle instead of two halves. The 62px the tab strip occupied
/// is simply gone; the form starts that much closer to the header.
class _FormCard extends StatelessWidget {
  final Widget child;
  const _FormCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Login Form
// ═══════════════════════════════════════════════════════════════════════════

class _LoginForm extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final LoginFormMode mode;
  final TextEditingController phoneCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController identifierCtrl;
  final TextEditingController passwordCtrl;
  final bool isLoading;

  /// Separate from [isLoading] so tapping Google does not also put the email
  /// Login button into a spinner.
  final bool isGoogleLoading;
  final VoidCallback onLoginEmail;
  final VoidCallback onLoginMobile;
  final VoidCallback onLoginIdentifier;
  final VoidCallback onLoginGoogle;

  const _LoginForm({
    required this.formKey,
    required this.mode,
    required this.phoneCtrl,
    required this.emailCtrl,
    required this.identifierCtrl,
    required this.passwordCtrl,
    required this.isLoading,
    required this.isGoogleLoading,
    required this.onLoginEmail,
    required this.onLoginMobile,
    required this.onLoginIdentifier,
    required this.onLoginGoogle,
  });

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  late String _channel =
      widget.mode == LoginFormMode.email ? 'Email' : 'Mobile';

  /// Identifier mode is one field for both channels, so the Mobile / Email
  /// control has nothing left to switch between.
  bool get _isIdentifierMode => widget.mode == LoginFormMode.identifier;

  /// Accepts either credential. Delegates to [Validators.email] once the
  /// value looks like an address so a typo'd email gets the email message
  /// rather than being told it is a bad phone number.
  String? _validateIdentifier(String? value) {
    final l10n = AppLocalizations.of(context);
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return l10n.authIdentifierRequired;
    switch (LoginIdentifier.classify(raw)) {
      case LoginIdentifierKind.email:
        return Validators.email(raw);
      case LoginIdentifierKind.mobile:
        return null;
      case LoginIdentifierKind.unknown:
        return l10n.authIdentifierInvalid;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isMobile = _channel == 'Mobile';

    return Form(
      key: widget.formKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Segmented Control
            if (!_isIdentifierMode) ...[
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariantLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    _SegmentTab(
                      label: l10n.authChannelMobile,
                      selected: isMobile,
                      onTap: () => setState(() => _channel = 'Mobile'),
                    ),
                    _SegmentTab(
                      label: l10n.authChannelEmail,
                      selected: !isMobile,
                      onTap: () => setState(() => _channel = 'Email'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            if (_isIdentifierMode) ...[
              // One field, either credential — the same styling the email
              // and mobile branches below use, so this reads as the same
              // form rather than a second login screen.
              Text(l10n.authIdentifierLabel, style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              NmTextField(
                controller: widget.identifierCtrl,
                hint: l10n.authIdentifierHint,
                keyboardType: TextInputType.emailAddress,
                validator: _validateIdentifier,
              ),
              const SizedBox(height: 20),
              NmPasswordField(
                controller: widget.passwordCtrl,
                label: l10n.authPassword,
                hint: '••••••••',
                validator: (v) =>
                    (v == null || v.isEmpty) ? l10n.authPasswordRequired : null,
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => context.push(
                    RouteNames.forgotPassword,
                    extra: {'email': widget.identifierCtrl.text.trim()},
                  ),
                  child: Text(
                    l10n.authForgotPassword,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              NmPrimaryButton(
                label: l10n.commonContinue,
                isLoading: widget.isLoading,
                onPressed: widget.isLoading ? null : widget.onLoginIdentifier,
              ),
            ] else if (isMobile) ...[
              Text(l10n.authPhoneNumber, style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              _Fixed91PhoneField(
                controller: widget.phoneCtrl,
                validator: Validators.phone,
              ),
              const SizedBox(height: 24),
              NmPrimaryButton(
                label: l10n.authLoginWithOtp,
                isLoading: widget.isLoading,
                onPressed: widget.isLoading ? null : widget.onLoginMobile,
              ),
            ] else ...[
              Text(l10n.authEmailAddress, style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              NmTextField(
                controller: widget.emailCtrl,
                hint: 'name@example.com',
                keyboardType: TextInputType.emailAddress,
                validator: Validators.email,
              ),
              const SizedBox(height: 20),
              NmPasswordField(
                controller: widget.passwordCtrl,
                label: l10n.authPassword,
                hint: '••••••••',
                validator: (v) =>
                    (v == null || v.isEmpty) ? l10n.authPasswordRequired : null,
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => context.push(
                    RouteNames.forgotPassword,
                    extra: {'email': widget.emailCtrl.text.trim()},
                  ),
                  child: Text(
                    l10n.authForgotPassword,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              NmPrimaryButton(
                label: l10n.authLogin,
                isLoading: widget.isLoading,
                onPressed: widget.isLoading ? null : widget.onLoginEmail,
              ),
            ],

            NmOrDivider(label: l10n.authOrContinueWith),

            NmSocialButton(
              label: l10n.authSignInWithGoogle,
              isLoading: widget.isGoogleLoading,
              onPressed: widget.isGoogleLoading || widget.isLoading
                  ? null
                  : widget.onLoginGoogle,
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SegmentTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: selected ? Colors.white : AppColors.textSecondaryLight,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}



// ═══════════════════════════════════════════════════════════════════════════
// Reusable Sub-Widgets
// ═══════════════════════════════════════════════════════════════════════════

/// Phone field with a fixed +91 (India) prefix and 10-digit limit.
class _Fixed91PhoneField extends StatelessWidget {
  final TextEditingController controller;
  final String? Function(String?)? validator;

  const _Fixed91PhoneField({
    required this.controller,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    const bgColor = AppColors.surfaceVariantLight;
    const borderColor = AppColors.borderLight;
    const textColor = AppColors.textPrimaryLight;

    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🇮🇳', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Text(
                  '+91',
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(width: 10),
                Container(width: 1, height: 24, color: borderColor),
              ],
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: controller,
              validator: validator,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              style: AppTypography.bodyLarge.copyWith(color: textColor),
              decoration: InputDecoration(
                hintText: '9876543210',
                hintStyle: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textTertiaryLight,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorStyle: const TextStyle(height: 0.8),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width plum primary button with loading state.

// ═══════════════════════════════════════════════════════════════════════════
// Trust Badges Footer
// ═══════════════════════════════════════════════════════════════════════════

class _TrustBadges extends StatelessWidget {
  const _TrustBadges();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          _TrustItem(icon: Icons.shield_outlined, label: l10n.authTrustSecure),
          _TrustItem(
            icon: Icons.lock_outline_rounded,
            label: l10n.authTrustPrivate,
          ),
          _TrustItem(
            icon: Icons.verified_outlined,
            label: l10n.authTrustVerified,
          ),
        ],
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TrustItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    const color = AppColors.textSecondaryLight;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}
