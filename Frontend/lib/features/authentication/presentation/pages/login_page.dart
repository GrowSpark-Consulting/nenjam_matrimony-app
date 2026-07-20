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
import '../../../registration/presentation/providers/registration_provider.dart';
import '../../data/services/backend_sync_service.dart';
import '../controllers/login_controller.dart';
import '../controllers/phone_auth_controller.dart';
import '../controllers/signup_controller.dart';
import '../providers/auth_providers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Login Page (Root)
// ═══════════════════════════════════════════════════════════════════════════

/// Authentication entry point — Login and Sign Up tabs, backed by Firebase.
class LoginPage extends ConsumerStatefulWidget {
  final int initialTab;
  const LoginPage({super.key, this.initialTab = 0});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  // Login form
  final _loginFormKey = GlobalKey<FormState>();
  final _loginPhoneCtrl = TextEditingController();
  final _loginEmailCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();

  // Sign Up form
  final _signUpFormKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _currentTab,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _currentTab = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginPhoneCtrl.dispose();
    _loginEmailCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
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
    _routeAfterLogin(result.needsVerification);
  }

  // ─── Login: Mobile OTP ─────────────────────────────────────────────
  Future<void> _onLoginMobile() async {
    if (!(_loginFormKey.currentState?.validate() ?? false)) return;
    final phone = '+91${_loginPhoneCtrl.text.trim()}';
    await ref.read(phoneAuthControllerProvider.notifier).sendCode(phone);
    if (!mounted) return;
    context.push(RouteNames.loginOtp, extra: {'phone': phone});
  }

  void _routeAfterLogin(bool needsVerification) {
    // Best-effort: mirrors this Firebase session into the NestJS + Postgres
    // backend. Never awaited — must not block or fail the navigation below.
    unawaited(syncUserWithBackend(ref.read(apiClientProvider)));

    if (!needsVerification) {
      context.go(RouteNames.discover);
      return;
    }
    // Send the user to whichever verification step is still outstanding.
    final emailVerified =
        ref.read(firebaseAuthServiceProvider).currentUser?.emailVerified ??
        false;
    context.go(emailVerified ? RouteNames.verifyPhone : RouteNames.verifyEmail);
  }

  // ─── Sign Up ───────────────────────────────────────────────────────
  Future<void> _onCreateAccount() async {
    if (!(_signUpFormKey.currentState?.validate() ?? false)) return;

    final notifier = ref.read(signupControllerProvider.notifier);
    notifier
      ..setUsername(_usernameCtrl.text.trim())
      ..setEmail(_emailCtrl.text.trim())
      ..setPassword(_passwordCtrl.text)
      ..setPhone(_phoneCtrl.text.trim());

    // Carry the "registering for" choice into the profile wizard.
    final regNotifier = ref.read(registrationProvider.notifier);
    regNotifier.goToStep(0);
    final registeringFor = ref.read(signupControllerProvider).registeringFor;
    if (registeringFor.isNotEmpty) {
      regNotifier.setProfileCreatedFor(registeringFor);
    }

    final ok = await notifier.submit();
    if (!mounted) return;
    if (!ok) {
      _snack(
        ref.read(signupControllerProvider).errorMessage ??
            AppLocalizations.of(context).authGenericError,
      );
      return;
    }
    // Best-effort: mirrors this new Firebase account into the NestJS +
    // Postgres backend. Never awaited — must not block or fail navigation.
    unawaited(syncUserWithBackend(ref.read(apiClientProvider)));

    // Account created + verification email sent → verify email.
    context.go(RouteNames.verifyEmail);
  }

  @override
  Widget build(BuildContext context) {
    final isSignUp = _currentTab == 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final loginLoading = ref.watch(loginControllerProvider);
    final signupLoading = ref.watch(signupControllerProvider).isSubmitting;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: isDark
            ? AppColors.backgroundDark
            : AppColors.backgroundLight,
        body: Stack(
          children: [
            NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverToBoxAdapter(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.08),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: isSignUp
                          ? const _SignUpHeader(key: ValueKey('signup'))
                          : const _LoginHeader(key: ValueKey('login')),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _StickyTabBarDelegate(
                      tabController: _tabController,
                      isDark: isDark,
                    ),
                  ),
                ];
              },
              body: TabBarView(
                controller: _tabController,
                children: [
                  _TabFormCard(
                    isDark: isDark,
                    child: _LoginForm(
                      formKey: _loginFormKey,
                      phoneCtrl: _loginPhoneCtrl,
                      emailCtrl: _loginEmailCtrl,
                      passwordCtrl: _loginPasswordCtrl,
                      isLoading: loginLoading,
                      onLoginEmail: _onLoginEmail,
                      onLoginMobile: _onLoginMobile,
                      onSignUpTap: () => _tabController.animateTo(1),
                    ),
                  ),
                  _TabFormCard(
                    isDark: isDark,
                    child: _SignUpForm(
                      formKey: _signUpFormKey,
                      usernameCtrl: _usernameCtrl,
                      phoneCtrl: _phoneCtrl,
                      emailCtrl: _emailCtrl,
                      passwordCtrl: _passwordCtrl,
                      isLoading: signupLoading,
                      onCreateAccount: _onCreateAccount,
                      onLoginTap: () => _tabController.animateTo(0),
                    ),
                  ),
                ],
              ),
            ),
            // Login is reached both as a flow root (via `go` after Splash/
            // OTP — nothing to pop to) and pushed from Auth Selection (via
            // `push`, where the user needs a way back) — only show a back
            // affordance when there's actually something to pop. White
            // icon: this overlays NmCurvedHeader's navy background.
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
  const _LoginHeader({super.key});
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

class _SignUpHeader extends StatelessWidget {
  const _SignUpHeader({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NmCurvedHeader(
      title: l10n.authCreateAccount,
      subtitle: l10n.authJoinCommunity,
      badgeChild: const Text(
        '∞',
        style: TextStyle(
          color: Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.w400,
          height: 1,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Sticky Tab Bar Delegate & Card Content
// ═══════════════════════════════════════════════════════════════════════════

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabController tabController;
  final bool isDark;

  _StickyTabBarDelegate({required this.tabController, required this.isDark});

  @override
  double get minExtent => 62.0;
  @override
  double get maxExtent => 62.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final isPinned = shrinkOffset > 0;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: EdgeInsets.symmetric(horizontal: isPinned ? 0 : 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: isPinned
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          if (isPinned)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            )
          else
            BoxShadow(
              color: const Color(0xFF1B2B4B).withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TabBar(
              controller: tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textTertiaryLight,
              labelStyle: AppTypography.titleSmall.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              unselectedLabelStyle: AppTypography.titleSmall.copyWith(
                fontWeight: FontWeight.w400,
              ),
              indicator: UnderlineTabIndicator(
                borderSide: const BorderSide(
                  color: AppColors.accentGold,
                  width: 2.5,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              tabs: [
                Tab(text: AppLocalizations.of(context).authLogin),
                Tab(text: AppLocalizations.of(context).authSignUp),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: isDark ? AppColors.borderDark : const Color(0xFFF0EEE9),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) {
    return tabController != oldDelegate.tabController ||
        isDark != oldDelegate.isDark;
  }
}

class _TabFormCard extends StatelessWidget {
  final bool isDark;
  final Widget child;
  const _TabFormCard({required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(28),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1B2B4B).withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: child,
          ),
          const SizedBox(height: 16),
          const _TrustBadges(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Login Form
// ═══════════════════════════════════════════════════════════════════════════

class _LoginForm extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController phoneCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool isLoading;
  final VoidCallback onLoginEmail;
  final VoidCallback onLoginMobile;
  final VoidCallback onSignUpTap;

  const _LoginForm({
    required this.formKey,
    required this.phoneCtrl,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.isLoading,
    required this.onLoginEmail,
    required this.onLoginMobile,
    required this.onSignUpTap,
  });

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  String _channel = 'Mobile';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isMobile = _channel == 'Mobile';

    return Form(
      key: widget.formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Segmented Control
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

            if (isMobile) ...[
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
                onPressed: widget.onLoginMobile,
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
                      color: AppColors.accentGold,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              NmPrimaryButton(
                label: l10n.authLogin,
                isLoading: widget.isLoading,
                onPressed: widget.onLoginEmail,
              ),
            ],

            NmOrDivider(label: l10n.authOrContinueWith),

            NmSocialButton(
              label: l10n.authSignInWithGoogle,
              onPressed: () => ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l10n.authComingSoon))),
            ),
            const SizedBox(height: 24),

            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  Text(
                    l10n.authNewHere,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onSignUpTap,
                    child: Text(
                      l10n.authCreateAccount,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.accentGold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
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
// Sign Up Form
// ═══════════════════════════════════════════════════════════════════════════

class _SignUpForm extends ConsumerWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController usernameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool isLoading;
  final VoidCallback onCreateAccount;
  final VoidCallback onLoginTap;

  const _SignUpForm({
    required this.formKey,
    required this.usernameCtrl,
    required this.phoneCtrl,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.isLoading,
    required this.onCreateAccount,
    required this.onLoginTap,
  });

  static const List<String> _registeringForOptions = [
    'Myself',
    'Son',
    'Daughter',
    'Brother',
    'Sister',
    'Friend',
  ];

  String _registeringForLabel(AppLocalizations l10n, String value) {
    switch (value) {
      case 'Myself':
        return l10n.authRegForMyself;
      case 'Son':
        return l10n.authRegForSon;
      case 'Daughter':
        return l10n.authRegForDaughter;
      case 'Brother':
        return l10n.authRegForBrother;
      case 'Sister':
        return l10n.authRegForSister;
      case 'Friend':
        return l10n.authRegForFriend;
      default:
        return value;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final registeringFor = ref.watch(
      signupControllerProvider.select((s) => s.registeringFor),
    );
    final notifier = ref.read(signupControllerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? Colors.white70 : AppColors.textSecondaryLight;

    return Form(
      key: formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Username ───────────────────────────────────────
            _FieldLabel(l10n.authUsername, color: labelColor),
            const SizedBox(height: 8),
            NmTextField(
              controller: usernameCtrl,
              hint: l10n.authUsernameHint,
              keyboardType: TextInputType.text,
              validator: Validators.username,
            ),
            const SizedBox(height: 16),

            // ─── Email ──────────────────────────────────────────
            _FieldLabel(l10n.authEmailAddress, color: labelColor),
            const SizedBox(height: 8),
            NmTextField(
              controller: emailCtrl,
              hint: 'name@example.com',
              keyboardType: TextInputType.emailAddress,
              validator: Validators.email,
            ),
            const SizedBox(height: 16),

            // ─── Password ───────────────────────────────────────
            _FieldLabel(l10n.authPassword, color: labelColor),
            const SizedBox(height: 8),
            NmPasswordField(
              controller: passwordCtrl,
              label: '',
              hint: '••••••••',
              validator: Validators.password,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.authPasswordHint,
              style: AppTypography.labelSmall.copyWith(
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiaryLight,
              ),
            ),
            const SizedBox(height: 16),

            // ─── Mobile Number ──────────────────────────────────
            _FieldLabel(l10n.authMobileNumber, color: labelColor),
            const SizedBox(height: 8),
            _Fixed91PhoneField(
              controller: phoneCtrl,
              validator: Validators.phone,
            ),
            const SizedBox(height: 16),

            // ─── Registering For ────────────────────────────────
            _FieldLabel(l10n.authRegisteringForLabel, color: labelColor),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _registeringForOptions.map((option) {
                return _RegisterChip(
                  label: _registeringForLabel(l10n, option),
                  isSelected: registeringFor == option,
                  onTap: () => notifier.setRegisteringFor(option),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            _PrimaryButton(
              label: l10n.authCreateAccount,
              isLoading: isLoading,
              onPressed: onCreateAccount,
            ),
            const SizedBox(height: 20),

            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  Text(
                    l10n.authAlreadyHaveAccount,
                    style: AppTypography.bodyMedium.copyWith(color: labelColor),
                  ),
                  GestureDetector(
                    onTap: onLoginTap,
                    child: Text(
                      l10n.authLogin,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _FieldLabel(this.text, {required this.color});
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.labelSmall.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
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

  const _Fixed91PhoneField({required this.controller, this.validator});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? AppColors.surfaceVariantDark
        : const Color(0xFFF5F3EE);
    final borderColor = isDark
        ? AppColors.borderDark.withValues(alpha: 0.5)
        : const Color(0xFFC5C6CF).withValues(alpha: 0.4);
    final textColor = isDark ? Colors.white : AppColors.textPrimaryLight;

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
                  color: isDark ? Colors.white38 : AppColors.textTertiaryLight,
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

/// "Registering for" chip.
class _RegisterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _RegisterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.borderLight,
            width: isSelected ? 1.5 : 1.2,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: isSelected ? Colors.white : AppColors.textPrimaryLight,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Full-width navy primary button with loading state.
class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;

  const _PrimaryButton({
    required this.label,
    required this.isLoading,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                label,
                style: AppTypography.labelLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }
}

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

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
