import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/buttons/outlined_button.dart';
import '../../../../l10n/app_localizations.dart';

/// Breakpoint above which the auth selection hero switches from a
/// stacked (portrait) to a side-by-side (landscape/tablet) layout.
const double _kLandscapeBreakpoint = 600;

/// Authentication Selection Hub Page.
///
/// Decides the user journey:
/// - Login -> navigates to Login tab (0)
/// - Create Account -> navigates to Sign Up tab (1)
///
/// Reached via [GoRouter.go] (which replaces the whole stack), so there is
/// no page underneath to pop back to. Both the Android system back gesture
/// and any back affordance must return to Language Selection instead of
/// falling through to [SystemNavigator.pop] and exiting the app.
class AuthSelectionPage extends StatelessWidget {
  const AuthSelectionPage({super.key});

  void _backToLanguage(BuildContext context) {
    context.go(RouteNames.language);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToLanguage(context);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: isDark
              ? AppColors.surfaceDark
              : AppColors.surfaceLight,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isLandscape =
                  constraints.maxWidth > constraints.maxHeight &&
                  constraints.maxWidth >= _kLandscapeBreakpoint;

              final hero = _HeroHeader(
                isDark: isDark,
                l10n: l10n,
                onBack: () => _backToLanguage(context),
                compact: isLandscape,
              );

              final actions = _AuthActions(l10n: l10n, isDark: isDark);

              if (isLandscape) {
                // Hero occupies the left edge (top/left/bottom insets);
                // content sits to its right and only needs the insets
                // that are real screen edges on that side.
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

              // Hero occupies the top edge; content below it only needs
              // the bottom inset (for gesture nav bars) — its top isn't
              // adjacent to the status bar so it must not double-pad.
              return Column(
                children: [
                  Expanded(flex: 9, child: hero),
                  Expanded(
                    flex: 11,
                    child: SafeArea(top: false, child: actions),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Luxury gradient hero header — logo, app name, and tagline.
///
/// Bleeds under the status bar for a full-bleed premium look; only its
/// inner content respects [SafeArea].
class _HeroHeader extends StatelessWidget {
  final bool isDark;
  final AppLocalizations l10n;
  final VoidCallback onBack;

  /// True when rendered beside the content column (landscape/tablet),
  /// which trims vertical padding so the logo block doesn't dominate
  /// the shorter viewport.
  final bool compact;

  const _HeroHeader({
    required this.isDark,
    required this.l10n,
    required this.onBack,
    required this.compact,
  });

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
        // Only the sides that are real screen edges for this layout need
        // an inset: in landscape the hero's right edge borders the
        // content column (not the screen), while its bottom edge does
        // border the screen; in portrait it's the reverse.
        right: !compact,
        bottom: compact,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Logo diameter scales with the hero's shorter side so
                    // it stays proportionate on small phones, foldables,
                    // and tablets alike.
                    final logoSize = constraints.biggest.shortestSide * 0.32;
                    final clampedLogoSize = logoSize.clamp(64.0, 120.0);

                    // FittedBox lets the whole logo block scale down as a
                    // unit on very short viewports (small phones in
                    // landscape, large text scaling) instead of
                    // overflowing — it stays at natural size whenever
                    // there's room.
                    return FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: clampedLogoSize,
                            height: clampedLogoSize,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.secondary.withValues(
                                  alpha: 0.5,
                                ),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.secondary.withValues(
                                    alpha: 0.2,
                                  ),
                                  blurRadius: 24,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.volunteer_activism_rounded,
                              size: clampedLogoSize * 0.5,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Text(
                            l10n.appName,
                            style: AppTypography.headlineLarge.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            l10n.authTagline,
                            style: AppTypography.labelMedium.copyWith(
                              color: Colors.white70,
                              letterSpacing: 3,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Welcome copy + Login / Create Account actions.
///
/// Title and subtitle sit near the top of the available space while the
/// buttons stay anchored near the bottom — using the intrinsic-height +
/// space-between pattern so the layout adapts without a fixed height and
/// gracefully becomes scrollable if content ever doesn't fit (e.g. large
/// system font scaling on a small device).
class _AuthActions extends StatelessWidget {
  final AppLocalizations l10n;
  final bool isDark;

  const _AuthActions({required this.l10n, required this.isDark});

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
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.authWelcomeTitle,
                              style: AppTypography.headlineMedium.copyWith(
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimaryLight,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              l10n.authWelcomeSubtitle,
                              style: AppTypography.bodyMedium.copyWith(
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight,
                                height: 1.6,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            NmGradientButton(
                              label: l10n.authLogin,
                              icon: Icons.login_rounded,
                              onPressed: () => context.push(
                                RouteNames.login,
                                extra: {'tab': 0},
                              ),
                            ),
                            const SizedBox(height: AppSpacing.base),
                            SizedBox(
                              width: double.infinity,
                              child: NmOutlinedButton(
                                label: l10n.authCreateAccount,
                                icon: Icons.person_add_alt_1_rounded,
                                onPressed: () => context.push(
                                  RouteNames.login,
                                  extra: {'tab': 1},
                                ),
                              ),
                            ),
                          ],
                        ),
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
