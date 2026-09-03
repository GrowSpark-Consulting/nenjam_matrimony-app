import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/tokens/app_radius.dart';
import '../../../../core/utils/auth_trace.dart';
import '../../../../core/widgets/buttons/outlined_button.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../core/widgets/inputs/phone_field.dart';
import '../../../../core/widgets/layout/responsive_layout.dart';
import '../../../../core/widgets/system_ui/nm_status_bar_style.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../authentication/domain/services/account_availability.dart';
import '../../../authentication/presentation/pages/registration_landing_page.dart'
    show SignUpFocus, signupMethodProvider;
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../providers/registration_provider.dart';
import '../widgets/onboarding_scaffold.dart';

/// Step 3 of onboarding — "An active email ID & phone no. are required to
/// secure your profile".
///
/// It captures and stores; it verifies nothing. **No Firebase Phone Auth
/// call is made from this screen.** It used to hand a new number to the real
/// verify-phone screen, which sent a live SMS — that is what produced
/// `BILLING_NOT_ENABLED` on accounts without SMS billing. Verification now
/// happens once, on the final onboarding OTP step, through the development
/// verifier.
///
/// Whatever the account or the chosen sign-up method already knows is
/// prefilled, so nobody retypes an identifier they have already given.
class OnboardingContactPage extends ConsumerStatefulWidget {
  const OnboardingContactPage({super.key});

  @override
  ConsumerState<OnboardingContactPage> createState() =>
      _OnboardingContactPageState();
}

class _OnboardingContactPageState extends ConsumerState<OnboardingContactPage> {
  final _emailCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  String _dialCode = '+91';
  bool _submitting = false;
  bool _showErrors = false;

  /// Set when the backend says one of these identifiers is already taken.
  /// Cleared on every fresh Continue, so an edited value is judged on its
  /// own merits.
  AccountAvailability? _duplicate;

  /// Set when the lookup itself could not be completed — distinct from
  /// "available", and it blocks Continue just as a duplicate does.
  bool _checkFailed = false;

  @override
  void initState() {
    super.initState();

    // Onboarding can run before there is a session, and reading the auth
    // service before Firebase is initialised throws — "no account yet" is
    // the normal case here, not an error.
    User? user;
    try {
      user = ref.read(firebaseAuthServiceProvider).currentUser;
    } catch (_) {
      user = null;
    }

    // Prefill order: what the account actually carries, then what an earlier
    // pass through this screen stored. Both are values the member has
    // already given — asking again would be the bug.
    final accountEmail = user?.email ?? '';
    _emailCtrl.text = accountEmail.isNotEmpty
        ? accountEmail
        : (_readPendingEmail() ?? '');

    final phone = user?.phoneNumber ?? _readPendingPhone() ?? '';
    if (phone.isNotEmpty) {
      // Stored E.164; show the national part beside the dial code rather
      // than repeating the country prefix inside the field.
      final match = kCountryCodes
          .where((c) => phone.startsWith(c.code))
          .fold<String?>(
            null,
            (best, c) =>
                best == null || c.code.length > best.length ? c.code : best,
          );
      _dialCode = match ?? _dialCode;
      _mobileCtrl.text = phone.substring(match?.length ?? 0);
    }
  }

  /// Local storage may not be initialised in a widget test; a missing
  /// prefill is not a failure worth crashing the screen over.
  String? _readPendingEmail() {
    try {
      return storageService.pendingEmail;
    } catch (_) {
      return null;
    }
  }

  String? _readPendingPhone() {
    try {
      return storageService.pendingPhone;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  String get _email => _emailCtrl.text.trim();
  String get _mobile => _mobileCtrl.text.trim();

  /// Deliberately permissive — a shape check, not an RFC parser.
  bool get _emailValid =>
      RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]+$').hasMatch(_email);

  bool get _mobileValid => RegExp(r'^\d{10}$').hasMatch(_mobile);

  bool get _canSubmit => _emailValid && _mobileValid;

  /// Drops a verdict that was about values the member has since changed.
  void _clearVerdict() {
    _duplicate = null;
    _checkFailed = false;
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.onboardingReligion);
    }
  }

  Future<void> _submit() async {
    // The guard that makes rapid taps safe: one check in flight at a time,
    // so a double tap cannot fire two lookups or navigate twice.
    if (_submitting) return;
    if (!_canSubmit) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() {
      _showErrors = false;
      _submitting = true;
      // Any previous verdict belonged to the values as they were then. The
      // check below re-reads the fields, so a member who corrected a
      // duplicate address gets a fresh answer rather than the stale one.
      _duplicate = null;
      _checkFailed = false;
    });

    final phoneE164 = '$_dialCode$_mobile';
    final AccountAvailability availability;
    try {
      availability = await ref
          .read(accountAvailabilityProvider)
          .check(email: _email, phoneE164: phoneE164);
    } on AccountAvailabilityUnavailable {
      // Deliberately not treated as "available": letting signup through on a
      // failed lookup is exactly how a duplicate account gets created.
      AuthTrace.accountCheckUnavailable();
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _checkFailed = true;
      });
      return;
    }
    AuthTrace.accountExists(
      email: availability.emailExists,
      phone: availability.phoneExists,
    );
    if (!mounted) return;

    if (availability.anyExists) {
      setState(() {
        _submitting = false;
        _duplicate = availability;
      });
      return;
    }

    // Stored, not verified. The number is stashed the way the rest of the
    // app stashes a pending one, so the final OTP step knows which number it
    // is confirming; no code is sent from here.
    await ref.read(registrationProvider.notifier).applyOnboardingContact(
          email: _email,
          phoneE164: phoneE164,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    AuthTrace.navigate(RouteNames.profileBasics, reason: 'signup continues');
    context.go(RouteNames.profileBasics);
  }

  /// Sends the member to the login they already have. The existing Welcome
  /// Back route — no second login screen, and never the removed chooser.
  ///
  /// **The only route from signup to Login in the whole flow, and it is
  /// never automatic**: it runs when the member taps "Log In" inside
  /// [_AccountExistsNotice], which appears only after
  /// `POST /auth/account-exists` reported one of these identifiers as
  /// already taken. A signup that reaches this screen with free identifiers
  /// continues to [RouteNames.profileBasics] and never sees Login.
  void _logIn() {
    AuthTrace.navigate(
      RouteNames.login,
      reason: 'member tapped Log In on the account-exists notice',
    );
    context.go(RouteNames.login);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final compact = OnboardingScaffold.isCompact(context);
    final method = ref.watch(signupMethodProvider);

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
                OnboardingBackRow(onBack: _back, compact: compact),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Center(
                            child: OnboardingCrest(
                              icon: Icons.lock_outline_rounded,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            l10n.onboardingContactHeadline,
                            style: AppTypography.bodyLarge.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Text(
                            l10n.onboardingContactEmailLabel,
                            style: AppTypography.titleMedium.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          NmTextField(
                            label: l10n.onboardingContactEmailLabel,
                            hint: l10n.onboardingContactEmailHint,
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            onChanged: (_) => setState(_clearVerdict),
                          ),
                          if (_showErrors && !_emailValid) ...[
                            const SizedBox(height: AppSpacing.xs),
                            _FieldError(
                              text: l10n.onboardingContactEmailInvalid,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            l10n.onboardingContactMobileLabel,
                            style: AppTypography.titleMedium.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          NmPhoneNumberField(
                            controller: _mobileCtrl,
                            initialCountryCode: _dialCode,
                            onCountryChanged: (c) => setState(() {
                              _dialCode = c.code;
                              _clearVerdict();
                            }),
                            onChanged: (_) => setState(_clearVerdict),
                          ),
                          if (_showErrors && !_mobileValid) ...[
                            const SizedBox(height: AppSpacing.xs),
                            _FieldError(
                              text: l10n.onboardingContactMobileInvalid,
                            ),
                          ],
                          // Which button the member pressed on the landing
                          // page decides nothing here beyond which field was
                          // already known — both are always collected.
                          if (method == SignUpFocus.mobile)
                            const SizedBox.shrink(),
                          if (_duplicate != null) ...[
                            const SizedBox(height: AppSpacing.lg),
                            _AccountExistsNotice(
                              availability: _duplicate!,
                              onLogIn: _logIn,
                            ),
                          ] else if (_checkFailed) ...[
                            const SizedBox(height: AppSpacing.lg),
                            _CheckFailedNotice(onRetry: _submit),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                OnboardingFooter(
                  compact: compact,
                  legalText: l10n.onboardingContactLegal,
                  child: NmGradientButton(
                    label: l10n.onboardingContactSubmit,
                    // NmGradientButton swaps the label for a spinner while
                    // loading, so this is the whole "Checking…" state — and
                    // it is also what makes a second tap a no-op.
                    isLoading: _submitting,
                    height: compact ? 48 : 56,
                    // Stays tappable so a first tap can *show* what is wrong
                    // — a disabled button beside two empty fields explains
                    // nothing. _submit refuses and reveals the errors.
                    onPressed: _submit,
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

/// Required-field error, shown only after a Submit that could not proceed —
/// so a member is not scolded for fields they have not reached yet.
class _FieldError extends StatelessWidget {
  final String text;

  const _FieldError({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.bodySmall
          .copyWith(color: Theme.of(context).colorScheme.error),
    );
  }
}

/// Shown when the backend already has an account for one of these
/// identifiers. Names which one, so the member knows what to change, but
/// nothing else about the account — this screen is unauthenticated.
class _AccountExistsNotice extends StatelessWidget {
  final AccountAvailability availability;
  final VoidCallback onLogIn;

  const _AccountExistsNotice({
    required this.availability,
    required this.onLogIn,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    final body = availability.emailExists && availability.phoneExists
        ? l10n.accountExistsBoth
        : availability.emailExists
            ? l10n.accountExistsEmail
            : l10n.accountExistsMobile;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: AppRadius.br16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: AppSpacing.lg,
                color: colors.secondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l10n.accountExistsTitle,
                  style: AppTypography.titleSmall.copyWith(
                    color: colors.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            style: AppTypography.bodySmall
                .copyWith(color: colors.onSecondaryContainer),
          ),
          const SizedBox(height: AppSpacing.md),
          // The way out. Editing the field above is the other way, and
          // needs no button — changing it clears this notice.
          NmOutlinedButton(
            label: l10n.accountExistsLogIn,
            icon: Icons.login_rounded,
            onPressed: onLogIn,
          ),
        ],
      ),
    );
  }
}

/// Shown when the lookup could not be completed. Retrying is the only way
/// forward: signup must not proceed on an unanswered question.
class _CheckFailedNotice extends StatelessWidget {
  final VoidCallback onRetry;

  const _CheckFailedNotice({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: AppRadius.br16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.accountCheckFailed,
            style: AppTypography.bodySmall
                .copyWith(color: colors.onErrorContainer),
          ),
          const SizedBox(height: AppSpacing.md),
          NmOutlinedButton(
            label: l10n.accountCheckRetry,
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
