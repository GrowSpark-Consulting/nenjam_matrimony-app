import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../l10n/app_localizations.dart';

/// Onboarding page with 3 swipeable slides matching the Stitch MCP design.
///
/// Flow: Language → Onboarding (AI → Verified → Astro) → Auth Selection.
/// Back button from slide 1 returns to Language.
/// Persists `onboarding_completed` via [StorageService].
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with TickerProviderStateMixin {
  final _controller = PageController();
  int _currentPage = 0;

  late final AnimationController _floatController;
  late final AnimationController _entryController;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();

    // Floating badge animation (infinite loop)
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    // Entry animation
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _entryFade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOut));

    _entrySlide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
        );

    _entryController.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _floatController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  void _onSkip() {
    storageService.setOnboardingDone();
    _goPastOnboarding();
  }

  void _onNext() {
    if (_currentPage < 2) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      storageService.setOnboardingDone();
      _goPastOnboarding();
    }
  }

  void _goPastOnboarding() {
    context.go(RouteNames.registrationLanding);
  }

  void _onBack() {
    if (_currentPage > 0) {
      _controller.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      context.go(RouteNames.language);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
        body: SafeArea(
          child: FadeTransition(
            opacity: _entryFade,
            child: SlideTransition(
              position: _entrySlide,
              child: Column(
                children: [
                  // ─── Top Bar ────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Back button
                        IconButton(
                          onPressed: _onBack,
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                        // App name
                        Text(
                          AppConstants.appName,
                          style: AppTypography.titleLarge.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        // Skip button
                        TextButton(
                          onPressed: _onSkip,
                          child: Text(
                            l10n.onboardingSkip,
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.textSecondaryLight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ─── Page Indicators (bar style) ───────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (i) {
                        final isActive = i == _currentPage;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: isActive ? 32 : 20,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.secondary
                                : AppColors.dividerLight,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ─── PageView ──────────────────────────────────
                  Expanded(
                    child: PageView(
                      controller: _controller,
                      onPageChanged: (i) => setState(() => _currentPage = i),
                      children: [
                        _AiMatchmakingSlide(
                          l10n: l10n,
                          floatController: _floatController,
                        ),
                        _VerifiedProfilesSlide(
                          l10n: l10n,
                          floatController: _floatController,
                        ),
                        _AstroCompatibilitySlide(
                          l10n: l10n,
                          floatController: _floatController,
                        ),
                      ],
                    ),
                  ),

                  // ─── Bottom CTA ────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: NmGradientButton(
                      label: _currentPage == 2
                          ? l10n.onboardingGetStarted
                          : l10n.onboardingNext,
                      icon: Icons.arrow_forward_rounded,
                      onPressed: _onNext,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SLIDE 1 — AI Matchmaking
// ─────────────────────────────────────────────────────────────────────────────

class _AiMatchmakingSlide extends StatelessWidget {
  final AppLocalizations l10n;
  final AnimationController floatController;

  const _AiMatchmakingSlide({
    required this.l10n,
    required this.floatController,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 24),

          // Hero visual container
          SizedBox(
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background glow blobs
                Positioned(
                  top: 20,
                  left: 0,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accentSoft.withValues(
                        alpha: 0.4,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 10,
                  right: 0,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primarySurface.withValues(
                        alpha: 0.3,
                      ),
                    ),
                  ),
                ),

                // Main glassmorphic hero card
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    gradient: AppGradients.primary,
                    borderRadius: BorderRadius.circular(40),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.25),
                        blurRadius: 40,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 80,
                    color: Colors.white,
                  ),
                ),

                // Floating badge
                AnimatedBuilder(
                  animation: floatController,
                  builder: (context, child) {
                    final offset =
                        math.sin(floatController.value * math.pi) * 10;
                    return Positioned(
                      bottom: 30,
                      right: 20,
                      child: Transform.translate(
                        offset: Offset(0, offset),
                        child: child,
                      ),
                    );
                  },
                  child: _GlassBadge(
                    icon: Icons.auto_awesome,
                    iconColor: AppColors.secondary,
                    label: l10n.onboardingAiBadge,
                    subtitle: l10n.onboardingAiBadgeSub,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // Title
          Text(
            l10n.onboardingAiTitle,
            style: AppTypography.headlineLarge.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Description
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l10n.onboardingAiDescription,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondaryLight,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SLIDE 2 — Verified Profiles
// ─────────────────────────────────────────────────────────────────────────────

class _VerifiedProfilesSlide extends StatelessWidget {
  final AppLocalizations l10n;
  final AnimationController floatController;

  const _VerifiedProfilesSlide({
    required this.l10n,
    required this.floatController,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 24),

          // Hero visual — Shield
          SizedBox(
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background glow
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentSoft.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),

                // Shield container with glassmorphism
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.6),
                    border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.2),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.secondary.withValues(alpha: 0.15),
                        blurRadius: 50,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    size: 80,
                    color: AppColors.secondary,
                  ),
                ),

                // Floating check badge (top-right)
                AnimatedBuilder(
                  animation: floatController,
                  builder: (context, child) {
                    final offset =
                        math.sin(floatController.value * math.pi) * 8;
                    return Positioned(
                      top: 20,
                      right: 40,
                      child: Transform.translate(
                        offset: Offset(0, offset),
                        child: child,
                      ),
                    );
                  },
                  child: const _GlassChip(
                    icon: Icons.check_circle,
                    iconColor: AppColors.success,
                  ),
                ),

                // Floating secure badge (bottom-left)
                AnimatedBuilder(
                  animation: floatController,
                  builder: (context, child) {
                    final offset =
                        math.cos(floatController.value * math.pi) * 8;
                    return Positioned(
                      bottom: 30,
                      left: 30,
                      child: Transform.translate(
                        offset: Offset(0, offset),
                        child: child,
                      ),
                    );
                  },
                  child: _GlassBadge(
                    icon: Icons.lock_rounded,
                    iconColor: AppColors.primary,
                    label: l10n.onboardingVerifiedBadge,
                    iconSize: 16,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // Title
          Text(
            l10n.onboardingVerifiedTitle,
            style: AppTypography.headlineLarge.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Description
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l10n.onboardingVerifiedDescription,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondaryLight,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SLIDE 3 — Astro Compatibility
// ─────────────────────────────────────────────────────────────────────────────

class _AstroCompatibilitySlide extends StatelessWidget {
  final AppLocalizations l10n;
  final AnimationController floatController;

  const _AstroCompatibilitySlide({
    required this.l10n,
    required this.floatController,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 24),

          // Hero visual — Astro mandala
          SizedBox(
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Rotating mandala background
                AnimatedBuilder(
                  animation: floatController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: floatController.value * math.pi * 0.1,
                      child: child,
                    );
                  },
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.secondary.withValues(alpha: 0.1),
                        width: 1,
                      ),
                    ),
                    child: Container(
                      margin: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.secondary.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.secondary.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Central focal point
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.7),
                    border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.2),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        blurRadius: 30,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 36,
                        color: AppColors.secondary,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.onboardingAstroSync,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // Floating Guna badge (top-left)
                AnimatedBuilder(
                  animation: floatController,
                  builder: (context, child) {
                    final offset =
                        math.sin(floatController.value * math.pi) * 6;
                    return Positioned(
                      top: 40,
                      left: 10,
                      child: Transform.translate(
                        offset: Offset(0, offset),
                        child: child,
                      ),
                    );
                  },
                  child: _GlassPill(
                    icon: Icons.stars_rounded,
                    label: l10n.onboardingAstroBadgeGuna,
                  ),
                ),

                // Floating Kundli badge (bottom-right)
                AnimatedBuilder(
                  animation: floatController,
                  builder: (context, child) {
                    final offset =
                        math.cos(floatController.value * math.pi) * 6;
                    return Positioned(
                      bottom: 40,
                      right: 10,
                      child: Transform.translate(
                        offset: Offset(0, offset),
                        child: child,
                      ),
                    );
                  },
                  child: _GlassPill(
                    icon: Icons.balance_rounded,
                    label: l10n.onboardingAstroBadgeKundli,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // Title with magenta highlight
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: l10n.onboardingAstroTitle,
                  style: AppTypography.headlineLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Description
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l10n.onboardingAstroDescription,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondaryLight,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Glassmorphic Widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Glassmorphic badge with icon, label, and optional subtitle.
class _GlassBadge extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final double iconSize;

  const _GlassBadge({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.subtitle,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: iconSize, color: iconColor),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle!,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small glassmorphic chip with just an icon.
class _GlassChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;

  const _GlassChip({
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 22, color: iconColor),
        ),
      ),
    );
  }
}

/// Pill-shaped glassmorphic badge with icon and text.
class _GlassPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _GlassPill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.secondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
