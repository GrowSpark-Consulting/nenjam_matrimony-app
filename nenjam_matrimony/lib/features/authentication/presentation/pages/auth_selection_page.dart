import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/buttons/outlined_button.dart';

/// Authentication Selection Hub Page.
///
/// Decides the user journey:
/// - Login -> navigates to Login tab (0)
/// - Create Account -> navigates to Sign Up tab (1)
class AuthSelectionPage extends StatelessWidget {
  const AuthSelectionPage({super.key});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        body: Column(
          children: [
            // ─── Luxury Hero Header ───────────────────────────────
            Container(
              width: double.infinity,
              height: MediaQuery.of(context).size.height * 0.45,
              decoration: const BoxDecoration(
                gradient: AppGradients.splash,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.accentGold.withValues(alpha: 0.5),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accentGold.withValues(alpha: 0.2),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.volunteer_activism_rounded,
                        size: 48,
                        color: AppColors.accentGold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Nenjam Matrimony',
                      style: AppTypography.headlineLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'FIND YOUR FOREVER',
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.accentGold,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ─── Content & Decision Buttons ───────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Welcome to Nenjam Matrimony',
                      style: AppTypography.headlineMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Experience a premier matrimonial journey curated exclusively for discerning individuals seeking lifelong companionship.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(),
                    // Login Button
                    NmGradientButton(
                      label: 'Login',
                      icon: Icons.login_rounded,
                      onPressed: () => context.push(
                        RouteNames.login,
                        extra: {'tab': 0},
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Create Account Button
                    SizedBox(
                      width: double.infinity,
                      child: NmOutlinedButton(
                        label: 'Create Account',
                        icon: Icons.person_add_alt_1_rounded,
                        onPressed: () => context.push(
                          RouteNames.login,
                          extra: {'tab': 1},
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
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
