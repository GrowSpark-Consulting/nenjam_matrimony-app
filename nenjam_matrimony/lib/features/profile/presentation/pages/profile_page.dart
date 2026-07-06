import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/badges/premium_badge.dart';
import '../../../../core/widgets/badges/verification_badge.dart';
import '../../../../core/widgets/cards/horoscope_card.dart';
import '../../../../core/widgets/chips/info_chip.dart';

/// User Profile Page with horoscope match, bio, and preferences.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            onPressed: () => context.push(RouteNames.settings),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar & Info Header
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: isDark
                          ? AppColors.surfaceVariantDark
                          : AppColors.surfaceVariantLight,
                      child: const Icon(Icons.person_rounded, size: 50),
                    ),
                    const SizedBox(height: 16),
                    Text('Arjun Sundar, 28', style: AppTypography.titleLarge),
                    const SizedBox(height: 4),
                    Text('NM984523 • Chennai', style: AppTypography.bodySmall),
                    const SizedBox(height: 12),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        NmPremiumBadge(showLabel: true),
                        SizedBox(width: 8),
                        NmVerificationBadge(showLabel: true),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Horoscope Card
              const NmHoroscopeCard(
                partnerName: 'Perfect Compatibility',
                gunaScore: 32,
              ),
              const SizedBox(height: 24),

              // About Me
              Text('About Me', style: AppTypography.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Senior Product Designer based in Chennai. Passionate about art, traveling, and building meaningful relationships grounded in mutual respect.',
                style: AppTypography.bodyMedium.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              // Basic Details Chips
              Text('Basic Details', style: AppTypography.titleMedium),
              const SizedBox(height: 12),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  NmInfoChip.religion(label: 'Hindu, Iyer'),
                  NmInfoChip.language(label: 'Tamil'),
                  NmInfoChip(label: '5 ft 10 in'),
                  NmInfoChip(label: 'Never Married'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
