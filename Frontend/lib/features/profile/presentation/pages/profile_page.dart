import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/badges/premium_badge.dart';
import '../../../../core/widgets/badges/verification_badge.dart';
import '../../../../core/widgets/chips/info_chip.dart';
import '../../../../core/widgets/relationship_intelligence/horoscope_compatibility_section.dart';
import '../../../../core/widgets/relationship_intelligence/profile_prompt_section.dart';
import '../../../../core/widgets/relationship_intelligence/psychology_section.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../astro/presentation/providers/compatibility_provider.dart';
import '../../../profile_prompts/presentation/providers/profile_prompt_provider.dart';
import '../../../psychology/domain/models/personality_result.dart';
import '../../../psychology/presentation/providers/personality_provider.dart';

/// User Profile Page with horoscope match, bio, and preferences. The
/// Relationship Intelligence sections (Prompts / Personality / Horoscope
/// Compatibility) are sourced from their own independent providers —
/// entirely decoupled from registration state.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final promptsAsync = ref.watch(myPromptsProvider);
    final personalityAsync = ref.watch(myPersonalityResultProvider);
    final horoscopeAsync = ref.watch(myHoroscopeSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileTitle),
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

              // About Me
              Text(l10n.profileAboutMeTitle, style: AppTypography.titleMedium),
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
              Text(l10n.profileBasicDetailsTitle, style: AppTypography.titleMedium),
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
              const SizedBox(height: 24),

              // ─── Relationship Intelligence ─────────────────────
              // Each section is independently async — a slow/failed one
              // never blocks the others, unlike the old single aggregate
              // call this replaced.
              horoscopeAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (summary) => HoroscopeCompatibilitySection(
                  rasi: summary.rasi,
                  nakshatra: summary.nakshatra,
                  dosham: summary.dosham,
                  matchingEnabled: summary.matchingEnabled,
                ),
              ),
              const SizedBox(height: 24),
              personalityAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (result) =>
                    PsychologySection(result: result ?? const PersonalityResult()),
              ),
              const SizedBox(height: 24),
              promptsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (prompts) => ProfilePromptSection(prompts: prompts),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
