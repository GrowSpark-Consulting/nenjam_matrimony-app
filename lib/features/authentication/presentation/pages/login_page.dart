import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/buttons/social_button.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../core/widgets/inputs/password_field.dart';
import '../../../../core/widgets/inputs/phone_field.dart';
import '../../../../core/widgets/layout/curved_header.dart';
import '../../../../core/widgets/layout/or_divider.dart';
import '../../../registration/presentation/providers/registration_provider.dart';
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
  final _signUpFormKey = GlobalKey<FormState>();
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
    if (!(_signUpFormKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid 10-digit mobile number and details')),
      );
      return;
    }

    final createAccountState = ref.read(createAccountProvider);
    final regNotifier = ref.read(registrationProvider.notifier);
    regNotifier.goToStep(0);
    if (createAccountState.registeringFor.isNotEmpty) {
      regNotifier.setProfileCreatedFor(createAccountState.registeringFor);
    }

    final notifier = ref.read(createAccountProvider.notifier);
    notifier.createAccount().then((_) {
      if (mounted) context.go(RouteNames.registrationWizard);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSignUp = _currentTab == 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: NestedScrollView(
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
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
                  isLoading: _loginLoading,
                  onSendOtp: _onLoginWithOtp,
                  onSignUpTap: () => _tabController.animateTo(1),
                ),
              ),
              _TabFormCard(
                isDark: isDark,
                child: _SignUpForm(
                  formKey: _signUpFormKey,
                  phoneCtrl: _phoneCtrl,
                  emailCtrl: _emailCtrl,
                  passwordCtrl: _passwordCtrl,
                  onCreateAccount: _onCreateAccount,
                  onLoginTap: () => _tabController.animateTo(0),
                ),
              ),
            ],
          ),
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
    return const NmCurvedHeader(
      title: 'Nenjam Matrimony',
      subtitle: 'Welcome Back',
      badgeIcon: Icons.favorite_rounded,
    );
  }
}

class _SignUpHeader extends StatelessWidget {
  const _SignUpHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const NmCurvedHeader(
      title: 'Create Account',
      subtitle: "Join Nenjam Matrimony's Elite Community",
      badgeChild: Text(
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

  _StickyTabBarDelegate({
    required this.tabController,
    required this.isDark,
  });

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
              tabs: const [
                Tab(text: 'Login'),
                Tab(text: 'Sign Up'),
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
              NmPhoneNumberField(
                controller: widget.phoneCtrl,
                validator: Validators.phone,
              ),
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
                    color: AppColors.accentGold,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            NmPrimaryButton(
              label: 'Login with OTP',
              isLoading: widget.isLoading,
              onPressed: () => widget.onSendOtp(_channel),
            ),

            const NmOrDivider(label: 'or continue with'),

            NmSocialButton(
              label: 'Sign in with Google',
              onPressed: () => context.go(RouteNames.home),
            ),
            const SizedBox(height: 24),

            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  Text(
                    'New here? ',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onSignUpTap,
                    child: Text(
                      'Create Account',
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

// ═══════════════════════════════════════════════════════════════════════════
// Sign Up Form (Stitch Pixel-Perfect & Responsive Implementation)
// ═══════════════════════════════════════════════════════════════════════════

class _SignUpForm extends ConsumerWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController phoneCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final VoidCallback onCreateAccount;
  final VoidCallback onLoginTap;

  const _SignUpForm({
    required this.formKey,
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
    'Friend',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(createAccountProvider);
    final notifier = ref.read(createAccountProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? Colors.white70 : AppColors.textSecondaryLight;

    return Form(
      key: formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Mobile Number ──────────────────────────────────
            Text(
              'Mobile Number',
              style: AppTypography.labelSmall.copyWith(
                color: labelColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _StitchPhoneInput(
              controller: phoneCtrl,
              onChanged: notifier.setPhone,
              onSendOtp: () {
                final phoneError = Validators.phone(phoneCtrl.text.trim());
                if (phoneError != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(phoneError)),
                  );
                  return;
                }
                notifier.setPhone(phoneCtrl.text.trim());
                notifier.sendMobileOtp();
              },
              isSent: state.mobileSentOtp,
            ),
            const SizedBox(height: 16),

            // ─── Email Address ──────────────────────────────────
            Text(
              'Email Address',
              style: AppTypography.labelSmall.copyWith(
                color: labelColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _StitchEmailInput(
              controller: emailCtrl,
              onChanged: notifier.setEmail,
              onSendOtp: () {
                final emailError = Validators.email(emailCtrl.text.trim());
                if (emailError != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(emailError)),
                  );
                  return;
                }
                notifier.setEmail(emailCtrl.text.trim());
                notifier.sendEmailOtp();
              },
              isSent: state.emailSentOtp,
            ),
          const SizedBox(height: 16),

          // ─── OTP Input Section (Responsive Cards) ───────────
          _OtpSection(
            title: 'Enter Mobile OTP',
            onCompleted: notifier.setMobileOtp,
            onChanged: notifier.setMobileOtp,
          ),
          const SizedBox(height: 14),
          _OtpSection(
            title: 'Enter Email OTP',
            onCompleted: notifier.setEmailOtp,
            onChanged: notifier.setEmailOtp,
          ),
          const SizedBox(height: 16),

          // ─── Password ───────────────────────────────────────
          Text(
            'Password',
            style: AppTypography.labelSmall.copyWith(
              color: labelColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _StitchPasswordInput(
            controller: passwordCtrl,
            onChanged: notifier.setPassword,
          ),
          const SizedBox(height: 16),

          // ─── Registering For ────────────────────────────────
          Text(
            'Registering for',
            style: AppTypography.labelSmall.copyWith(
              color: labelColor,
              fontWeight: FontWeight.w600,
            ),
          ),
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
          const SizedBox(height: 20),

          // ─── Login Link ─────────────────────────────────────
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                Text(
                  'Already have an account? ',
                  style: AppTypography.bodyMedium.copyWith(color: labelColor),
                ),
                GestureDetector(
                  onTap: onLoginTap,
                  child: Text(
                    'Login',
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

// ═══════════════════════════════════════════════════════════════════════════
// Reusable Sub-Widgets (Stitch Specific Implementation)
// ═══════════════════════════════════════════════════════════════════════════

/// Stitch pixel-perfect phone input: rounded container with embedded prefix & action button.
class _StitchPhoneInput extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback onSendOtp;
  final bool isSent;

  const _StitchPhoneInput({
    required this.controller,
    this.onChanged,
    required this.onSendOtp,
    required this.isSent,
  });

  @override
  State<_StitchPhoneInput> createState() => _StitchPhoneInputState();
}

class _StitchPhoneInputState extends State<_StitchPhoneInput> {
  CountryInfo _selectedCountry = kCountryCodes.first;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? AppColors.surfaceVariantDark : const Color(0xFFF5F3EE);
    final borderColor = isDark
        ? AppColors.borderDark.withValues(alpha: 0.5)
        : const Color(0xFFC5C6CF).withValues(alpha: 0.4);
    final textColor = isDark ? Colors.white : AppColors.textPrimaryLight;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => showCountryPickerSheet(context, onSelect: (c) {
              setState(() => _selectedCountry = c);
            }),
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 12, top: 16, bottom: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_selectedCountry.flag, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(
                    _selectedCountry.code,
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down_rounded, size: 20, color: textColor.withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  Container(
                    width: 1,
                    height: 24,
                    color: borderColor,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: widget.controller,
              validator: Validators.phone,
              keyboardType: TextInputType.phone,
              onChanged: widget.onChanged,
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
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.isSent ? null : widget.onSendOtp,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Text(
                  widget.isSent ? 'Sent ✓' : 'Send OTP',
                  style: AppTypography.labelMedium.copyWith(
                    color: widget.isSent ? AppColors.success : AppColors.accentGold,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stitch pixel-perfect email input with integrated Send OTP action button.
class _StitchEmailInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback onSendOtp;
  final bool isSent;

  const _StitchEmailInput({
    required this.controller,
    this.onChanged,
    required this.onSendOtp,
    required this.isSent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? AppColors.surfaceVariantDark : const Color(0xFFF5F3EE);
    final borderColor = isDark
        ? AppColors.borderDark.withValues(alpha: 0.5)
        : const Color(0xFFC5C6CF).withValues(alpha: 0.4);
    final textColor = isDark ? Colors.white : AppColors.textPrimaryLight;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              validator: Validators.email,
              keyboardType: TextInputType.emailAddress,
              onChanged: onChanged,
              style: AppTypography.bodyLarge.copyWith(color: textColor),
              decoration: InputDecoration(
                hintText: 'name@example.com',
                hintStyle: AppTypography.bodyLarge.copyWith(
                  color: isDark ? Colors.white38 : AppColors.textTertiaryLight,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.only(
                  left: 16,
                  top: 16,
                  bottom: 16,
                ),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isSent ? null : onSendOtp,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Text(
                  isSent ? 'Sent ✓' : 'Send OTP',
                  style: AppTypography.labelMedium.copyWith(
                    color: isSent ? AppColors.success : AppColors.accentGold,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stitch pixel-perfect password field inside rounded container.
class _StitchPasswordInput extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  const _StitchPasswordInput({
    required this.controller,
    this.onChanged,
  });

  @override
  State<_StitchPasswordInput> createState() => _StitchPasswordInputState();
}

class _StitchPasswordInputState extends State<_StitchPasswordInput> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? AppColors.surfaceVariantDark : const Color(0xFFF5F3EE);
    final borderColor = isDark
        ? AppColors.borderDark.withValues(alpha: 0.5)
        : const Color(0xFFC5C6CF).withValues(alpha: 0.4);
    final textColor = isDark ? Colors.white : AppColors.textPrimaryLight;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: widget.controller,
              obscureText: _obscure,
              onChanged: widget.onChanged,
              style: AppTypography.bodyLarge.copyWith(color: textColor),
              decoration: InputDecoration(
                hintText: '••••••••',
                hintStyle: AppTypography.bodyLarge.copyWith(
                  color: isDark ? Colors.white38 : AppColors.textTertiaryLight,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.only(
                  left: 16,
                  top: 16,
                  bottom: 16,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              _obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
              size: 20,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// OTP section: labeled card container with 6 responsive individual input cells.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark
        ? AppColors.surfaceVariantDark.withValues(alpha: 0.3)
        : const Color(0xFFF0EEE9).withValues(alpha: 0.45);
    final borderColor = isDark
        ? AppColors.borderDark.withValues(alpha: 0.5)
        : const Color(0xFFC5C6CF).withValues(alpha: 0.35);
    final inputBg = isDark ? AppColors.surfaceDark : Colors.white;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            widget.title,
            style: AppTypography.labelMedium.copyWith(
              color: isDark ? Colors.white70 : AppColors.textSecondaryLight,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 6.0;
              final totalGap = gap * (_length - 1);
              final availableWidth = constraints.maxWidth - totalGap;
              final cellWidth = (availableWidth / _length).clamp(30.0, 48.0);
              final cellHeight = (cellWidth * 1.15).clamp(40.0, 56.0);

              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_length, (index) {
                  return Padding(
                    padding: EdgeInsets.only(
                      right: index < _length - 1 ? gap : 0,
                    ),
                    child: SizedBox(
                      width: cellWidth,
                      height: cellHeight,
                      child: KeyboardListener(
                        focusNode: FocusNode(),
                        onKeyEvent: (e) => _onKeyDown(index, e),
                        child: TextFormField(
                          controller: _controllers[index],
                          focusNode: _focusNodes[index],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: _length,
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.textPrimaryLight,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            counterText: '',
                            contentPadding: EdgeInsets.zero,
                            filled: true,
                            fillColor: inputBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.primary,
                                width: 1.8,
                              ),
                            ),
                          ),
                          onChanged: (v) => _onCellChanged(index, v),
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

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

class _TrustDot extends StatelessWidget {
  const _TrustDot();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark
        ? AppColors.textSecondaryDark.withValues(alpha: 0.5)
        : AppColors.textSecondaryLight.withValues(alpha: 0.5);

    return Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}
