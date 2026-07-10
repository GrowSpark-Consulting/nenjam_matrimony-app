import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../astro/presentation/providers/compatibility_provider.dart';
import '../../../profile_prompts/presentation/providers/profile_prompt_provider.dart';
import '../../../psychology/presentation/providers/personality_provider.dart';

/// Profile Intelligence hub — 3 cards (Profile Prompts / Personality
/// Insights / Horoscope Compatibility). Reached from the drawer's "Profile
/// Intelligence" item, and optionally once after first-time registration
/// (see DiscoverPage). Relationship Intelligence is profile enrichment
/// only — nothing here is required.
class ProfileIntelligencePage extends ConsumerWidget {
  const ProfileIntelligencePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promptsAsync = ref.watch(myPromptsProvider);
    final personalityAsync = ref.watch(myPersonalityResultProvider);
    final horoscopeAsync = ref.watch(myHoroscopeSummaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile Intelligence')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enrich your profile',
                style: AppTypography.headlineSmall
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'These are optional — add them anytime to help us find better matches for you.',
                style: AppTypography.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              _IntelligenceCard(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Profile Prompts',
                subtitle: promptsAsync.when(
                  data: (prompts) => prompts.isEmpty
                      ? 'Add up to 3 prompts'
                      : '${prompts.length} of 3 added',
                  loading: () => 'Loading…',
                  error: (_, __) => 'Add up to 3 prompts',
                ),
                onTap: () async {
                  final prompts = promptsAsync.value ?? [];
                  await context.push(RouteNames.choosePrompt, extra: prompts);
                  ref.invalidate(myPromptsProvider);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              _IntelligenceCard(
                icon: Icons.psychology_alt_rounded,
                title: 'Personality Insights',
                subtitle: personalityAsync.when(
                  data: (result) => (result?.completed ?? false)
                      ? 'Completed'
                      : 'Take the 3-minute quiz',
                  loading: () => 'Loading…',
                  error: (_, __) => 'Take the 3-minute quiz',
                ),
                onTap: () async {
                  await context.push(RouteNames.psychologyQuiz);
                  ref.invalidate(myPersonalityResultProvider);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              _IntelligenceCard(
                icon: Icons.auto_awesome_rounded,
                title: 'Horoscope Compatibility',
                subtitle: horoscopeAsync.when(
                  data: (summary) => summary.matchingEnabled
                      ? 'Matching enabled'
                      : 'Matching disabled',
                  loading: () => 'Loading…',
                  error: (_, __) => 'View your horoscope',
                ),
                onTap: () async {
                  await context.push(RouteNames.horoscopeMatching);
                  ref.invalidate(myHoroscopeSummaryProvider);
                },
              ),
              const SizedBox(height: AppSpacing.xl2),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntelligenceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _IntelligenceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      borderRadius: AppSpacing.borderRadiusXl,
      child: InkWell(
        borderRadius: AppSpacing.borderRadiusXl,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: AppSpacing.cardPaddingLarge,
          decoration: AppDecorations.card(isDark: isDark),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accentGold.withValues(alpha: 0.12),
                  borderRadius: AppSpacing.borderRadiusMd,
                ),
                child: Icon(icon, color: AppColors.accentGold),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppTypography.bodyLarge
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.labelSmall.copyWith(
                        color: isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiaryLight,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiaryLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
