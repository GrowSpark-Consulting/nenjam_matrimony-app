import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/animations/app_animations.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../l10n/app_localizations.dart';

/// One-time "Let's build your story ❤️" interstitial shown once, right
/// before the first wizard step, for brand-new registrations only. Purely a
/// routing waypoint — reads no registration state, since [startCreateMode]
/// already ran before navigating here (see email_verify_screen.dart).
class RegistrationWelcomePage extends StatelessWidget {
  const RegistrationWelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.splash),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(flex: 2),
                AppAnimations.scale(
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.12),
                      border: Border.all(
                        color: AppColors.secondary.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      size: 56,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                AppAnimations.slide(
                  Text(
                    l10n.registrationWelcomeHeadline,
                    textAlign: TextAlign.center,
                    style: AppTypography.displaySmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AppAnimations.slide(
                  Text(
                    l10n.registrationWelcomeSubtitle,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyLarge.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                const Spacer(flex: 3),
                AppAnimations.fade(
                  SizedBox(
                    width: double.infinity,
                    child: NmGradientButton(
                      label: l10n.registrationWelcomeCta,
                      useAccentGradient: true,
                      icon: Icons.arrow_forward_rounded,
                      onPressed: () =>
                          context.go(RouteNames.registrationWizard),
                    ),
                  ),
                  delay: const Duration(milliseconds: 300),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
