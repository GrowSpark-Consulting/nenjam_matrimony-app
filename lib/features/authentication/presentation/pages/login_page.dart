import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../core/widgets/inputs/password_field.dart';
import '../providers/create_account_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Login Page (Root)
// ═══════════════════════════════════════════════════════════════════════════

/// Authentication entry point — Login and Sign Up tabs.
///
/// Design: Navy gradient hero that dynamically switches header copy
/// based on active tab (heart/"Welcome Back" vs infinity/"Create Account").
class LoginPage extends ConsumerStatefulWidget {
  final int initialTab;
  const LoginPage({super.key, this.initialTab = 0});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  // Login form state (local — no Riverpod needed for simple login)
  final _loginFormKey = GlobalKey<FormState>();
  final _loginPhoneCtrl = TextEditingController();
  final _loginEmailCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();
  bool _loginLoading = false;

  // Sign Up controllers (reading from Riverpod provider for state, but
  // we keep controllers for text field binding)
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
    _tabController = TabController(length: 2, vsync: this, initialIndex: _currentTab);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _currentTab = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginFormKey.currentState?.dispose();
    _loginPhoneCtrl.dispose();
    _loginEmailCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _onLoginWithOtp(String channel) {
    if (_loginFormKey.currentState?.validate() ?? false) {
      setState(() => _loginLoading = true);
      final isMobile = channel == 'Mobile';
      final identifier = isMobile ? _loginPhoneCtrl.text.trim() : _loginEmailCtrl.text.trim();
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) {
          setState(() => _loginLoading = false);
          context.push(RouteNames.otp, extra: {
            'identifier': identifier.isEmpty ? '9876543210' : identifier,
            'channel': isMobile ? 'phone' : 'email',
            'flow': 'login',
          });
        }
      });
    }
  }

  void _onCreateAccount() {
    final notifier = ref.read(createAccountProvider.notifier);
    notifier.createAccount().then((_) {
      if (mounted) context.go(RouteNames.profile);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSignUp = _currentTab == 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF1B2B4B),
        body: Column(
          children: [
            // ─── Dynamic Navy Header ──────────────────────────────
            AnimatedSwitcher(
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

            // ─── Scrollable Content Card ───────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  children: [
                    // Floating tab card
                    _AuthCard(
                      tabController: _tabController,
                      loginContent: _LoginForm(
                        formKey: _loginFormKey,
                        phoneCtrl: _loginPhoneCtrl,
                        emailCtrl: _loginEmailCtrl,
                        passwordCtrl: _loginPasswordCtrl,
                        isLoading: _loginLoading,
                        onSendOtp: _onLoginWithOtp,
                        onSignUpTap: () => _tabController.animateTo(1),
                      ),
                      signUpContent: _SignUpForm(
                        phoneCtrl: _phoneCtrl,
                        emailCtrl: _emailCtrl,
                        passwordCtrl: _passwordCtrl,
                        onCreateAccount: _onCreateAccount,
                        onLoginTap: () => _tabController.animateTo(0),
                      ),
                    ),

                    // ─── Trust Indicators ────────────────────────
                    const SizedBox(height: 4),
                    const _TrustBadges(),
                    const SizedBox(height: 24),
                  ],
                ),
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
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.accentGold.withValues(alpha: 0.45),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.favorite_rounded,
                size: 26,
                color: AppColors.accentGold,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Welcome Back',
              style: AppTypography.headlineMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sign in to continue your journey',
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white.withValues(alpha: 0.6),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignUpHeader extends StatelessWidget {
  const _SignUpHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
        child: Column(
          children: [
            // Infinity symbol badge
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.accentGold.withValues(alpha: 0.45),
                  width: 1.5,
                ),
              ),
              child: const Center(
                child: Text(
                  '∞',
                  style: TextStyle(
                    color: AppColors.accentGold,
                    fontSize: 26,
                    fontWeight: FontWeight.w300,
                    height: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Create Account',
              style: AppTypography.headlineMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Join Nenjam Matrimony's Elite Community",
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white.withValues(alpha: 0.6),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Auth Card with Tabs
// ═══════════════════════════════════════════════════════════════════════════

class _AuthCard extends StatelessWidget {
  final TabController tabController;
  final Widget loginContent;
  final Widget signUpContent;

  const _AuthCard({
    required this.tabController,
    required this.loginContent,
    required this.signUpContent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      transform: Matrix4.translationValues(0, -24, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B2B4B).withValues(alpha: 0.18),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ─── Tab Bar ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
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
              tabs: const [
                Tab(text: 'Login'),
                Tab(text: 'Sign Up'),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF0EEE9)),

          // ─── Tab Content ─────────────────────────────────────
          SizedBox(
            height: 620,
            child: TabBarView(
              controller: tabController,
              children: [loginContent, signUpContent],
            ),
          ),
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
  final void Function(String channel) onSendOtp;
  final VoidCallback onSignUpTap;

  const _LoginForm({
    required this.formKey,
    required this.phoneCtrl,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.isLoading,
    required this.onSendOtp,
    required this.onSignUpTap,
  });

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  String _channel = 'Mobile';

  @override
  Widget build(BuildContext context) {
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
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _channel = 'Mobile'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isMobile ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Mobile',
                          style: AppTypography.labelMedium.copyWith(
                            color: isMobile ? Colors.white : AppColors.textSecondaryLight,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _channel = 'Email'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !isMobile ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Email',
                          style: AppTypography.labelMedium.copyWith(
                            color: !isMobile ? Colors.white : AppColors.textSecondaryLight,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (isMobile) ...[
              Text('Phone Number', style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              _PhoneInputRow(controller: widget.phoneCtrl),
            ] else ...[
              Text('Email Address', style: AppTypography.labelLarge),
              const SizedBox(height: 8),
              NmTextField(
                controller: widget.emailCtrl,
                hint: 'name@example.com',
                keyboardType: TextInputType.emailAddress,
                validator: Validators.email,
              ),
            ],
            const SizedBox(height: 20),

            NmPasswordField(
              controller: widget.passwordCtrl,
              label: 'Password',
              hint: '••••••••',
            ),
            const SizedBox(height: 10),

            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () {},
                child: Text(
                  'Forgot Password?',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            _PrimaryButton(
              label: 'Login',
              isLoading: widget.isLoading,
              onPressed: () => widget.onSendOtp(_channel),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: () => widget.onSendOtp(_channel),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primary, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  'Continue with OTP',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondaryLight),
                  ),
                  GestureDetector(
                    onTap: widget.onSignUpTap,
                    child: Text(
                      'Create Account',
                      style: AppTypography.bodySmall.copyWith(
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

// ═══════════════════════════════════════════════════════════════════════════
// Sign Up Form
// ═══════════════════════════════════════════════════════════════════════════

class _SignUpForm extends ConsumerWidget {
  final TextEditingController phoneCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final VoidCallback onCreateAccount;
  final VoidCallback onLoginTap;

  const _SignUpForm({
    required this.phoneCtrl,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.onCreateAccount,
    required this.onLoginTap,
  });

  static const List<String> _registeringForOptions = [
    'Myself',
    'Son',
    'Daughter',
    'Brother',
    'Sister',
    'Relative',
    'Friend',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(createAccountProvider);
    final notifier = ref.read(createAccountProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Mobile Number ──────────────────────────────────
          Text('Mobile Number', style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          _OtpSendRow(
            onSend: () {
              notifier.setPhone(phoneCtrl.text.trim());
              notifier.sendMobileOtp();
            },
            alreadySent: state.mobileSentOtp,
            child: _PhoneInputRow(
              controller: phoneCtrl,
              onChanged: notifier.setPhone,
            ),
          ),
          const SizedBox(height: 16),

          // ─── Email Address ──────────────────────────────────
          Text('Email Address', style: AppTypography.labelLarge),
          const SizedBox(height: 8),
          _OtpSendRow(
            onSend: () {
              notifier.setEmail(emailCtrl.text.trim());
              notifier.sendEmailOtp();
            },
            alreadySent: state.emailSentOtp,
            child: Expanded(
              child: NmTextField(
                controller: emailCtrl,
                hint: 'name@example.com',
                keyboardType: TextInputType.emailAddress,
                validator: Validators.email,
                onChanged: notifier.setEmail,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Mobile OTP ─────────────────────────────────────
          _OtpSection(
            title: 'Enter Mobile OTP',
            onCompleted: notifier.setMobileOtp,
            onChanged: notifier.setMobileOtp,
          ),
          const SizedBox(height: 12),

          // ─── Email OTP ──────────────────────────────────────
          _OtpSection(
            title: 'Enter Email OTP',
            onCompleted: notifier.setEmailOtp,
            onChanged: notifier.setEmailOtp,
          ),
          const SizedBox(height: 16),

          // ─── Password ───────────────────────────────────────
          NmPasswordField(
            controller: passwordCtrl,
            label: 'Password',
            hint: '••••••••',
            onChanged: notifier.setPassword,
          ),
          const SizedBox(height: 16),

          // ─── Registering For ────────────────────────────────
          Text('Registering for', style: AppTypography.labelLarge),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _registeringForOptions.map((option) {
              final isSelected = state.registeringFor == option;
              return _RegisterChip(
                label: option,
                isSelected: isSelected,
                onTap: () => notifier.setRegisteringFor(option),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // ─── Create Account Button ──────────────────────────
          _PrimaryButton(
            label: 'Create Account',
            isLoading: state.isLoading,
            onPressed: onCreateAccount,
          ),
          const SizedBox(height: 16),

          // ─── Login Link ─────────────────────────────────────
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                Text(
                  'Already have an account? ',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondaryLight),
                ),
                GestureDetector(
                  onTap: onLoginTap,
                  child: Text(
                    'Login',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Reusable Sub-Widgets (private to this file)
// ═══════════════════════════════════════════════════════════════════════════

/// Phone number input row: [🇮🇳 +91] [phone input]
class _PhoneInputRow extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  const _PhoneInputRow({this.controller, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          // Country Picker
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariantLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🇮🇳', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 4),
                Text(
                  '+91',
                  style: AppTypography.labelMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryLight,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: NmTextField(
              controller: controller,
              hint: '9876543210',
              keyboardType: TextInputType.phone,
              validator: Validators.phone,
              onChanged: onChanged,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
        ],
      ),
    );
  }
}

/// A row that wraps [child] and adds a gold "Send OTP" button on the right.
class _OtpSendRow extends StatelessWidget {
  final Widget child;
  final VoidCallback onSend;
  final bool alreadySent;

  const _OtpSendRow({
    required this.child,
    required this.onSend,
    required this.alreadySent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariantLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          child,
          GestureDetector(
            onTap: alreadySent ? null : onSend,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                alreadySent ? 'Sent ✓' : 'Send OTP',
                style: AppTypography.labelMedium.copyWith(
                  color: alreadySent
                      ? AppColors.success
                      : AppColors.accentGold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// OTP section: labeled gray container with 6 individual input cells.
class _OtpSection extends StatefulWidget {
  final String title;
  final ValueChanged<String> onCompleted;
  final ValueChanged<String>? onChanged;

  const _OtpSection({
    required this.title,
    required this.onCompleted,
    this.onChanged,
  });

  @override
  State<_OtpSection> createState() => _OtpSectionState();
}

class _OtpSectionState extends State<_OtpSection> {
  static const int _length = 6;
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_length, (_) => TextEditingController());
    _focusNodes = List.generate(_length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  void _onCellChanged(int index, String value) {
    if (value.length > 1) {
      // Paste support — distribute across cells
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < _length; i++) {
        _controllers[i].text = i < digits.length ? digits[i] : '';
      }
      final last = (digits.length - 1).clamp(0, _length - 1);
      _focusNodes[last].requestFocus();
      setState(() {});
    } else {
      if (value.length == 1 && index < _length - 1) {
        _focusNodes[index + 1].requestFocus();
      }
    }
    final otp = _otp;
    widget.onChanged?.call(otp);
    if (otp.length == _length) widget.onCompleted(otp);
  }

  void _onKeyDown(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariantLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            widget.title,
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(_length, (index) {
              return SizedBox(
                width: 42,
                height: 44,
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (e) => _onKeyDown(index, e),
                  child: TextFormField(
                    controller: _controllers[index],
                    focusNode: _focusNodes[index],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: _length, // allow paste
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryLight,
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      counterText: '',
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.borderLight,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.borderLight,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.8,
                        ),
                      ),
                    ),
                    onChanged: (v) => _onCellChanged(index, v),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// "Registering for" chip — dark navy filled when selected, outlined otherwise.
/// Uses custom styling instead of NmFilterChip for this specific design.
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

/// "or continue with" divider.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFE4E1DA))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or continue with',
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textTertiaryLight,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFFE4E1DA))),
      ],
    );
  }
}

/// Google sign-in button.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: () {},
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimaryLight,
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFDDD9D0), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.g_mobiledata_rounded,
                size: 24, color: Color(0xFF4285F4)),
            const SizedBox(width: 8),
            Text(
              'Sign in with Google',
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.textPrimaryLight,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TrustItem(icon: Icons.shield_outlined, label: 'SECURE'),
          SizedBox(width: 4),
          _TrustDot(),
          SizedBox(width: 4),
          _TrustItem(icon: Icons.lock_outline_rounded, label: 'PRIVATE'),
          SizedBox(width: 4),
          _TrustDot(),
          SizedBox(width: 4),
          _TrustItem(icon: Icons.verified_outlined, label: 'VERIFIED'),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: 13,
            color: Colors.white.withValues(alpha: 0.55)),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _TrustDot extends StatelessWidget {
  const _TrustDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.35),
      ),
    );
  }
}
