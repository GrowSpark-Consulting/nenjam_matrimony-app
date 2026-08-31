import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/cards/subscription_card.dart';
import '../../../../l10n/app_localizations.dart';

/// Premium plans showcase page.
class PremiumPage extends StatelessWidget {
  const PremiumPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.premiumTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: AppGradients.premiumCard,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.12),
                        border: Border.all(
                          color: AppColors.premiumCream.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        size: 40,
                        color: AppColors.premiumCream,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.premiumHeroTitle,
                      style: AppTypography.headlineSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.premiumHeroSubtitle,
                      style: AppTypography.bodyMedium.copyWith(
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Plans
              const NmSubscriptionCard(
                planName: 'Gold Luxury',
                price: '₹4,999',
                duration: '3 Months',
                isPopular: true,
                isSelected: true,
                features: [
                  'Send 100 direct messages',
                  'View 50 verified contact numbers',
                  'AI Compatibility & Horoscope report',
                  'Priority profile listing',
                ],
              ),
              const SizedBox(height: 20),
              const NmSubscriptionCard(
                planName: 'Platinum VIP',
                price: '₹9,999',
                duration: '6 Months',
                features: [
                  'Unlimited direct messages',
                  'Unlimited contact views',
                  'Dedicated Relationship Manager',
                  'Guaranteed top tier placement',
                ],
              ),
              const SizedBox(height: 32),

              // Proceed CTA
              NmGradientButton(
                label: l10n.premiumProceedToPayment,
                useAccentGradient: true,
                onPressed: () => context.push(RouteNames.subscription),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
