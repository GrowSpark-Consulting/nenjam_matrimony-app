import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/intelligence_card.dart';
import '../../../astro/presentation/providers/compatibility_provider.dart';
import '../../../profile_prompts/domain/models/prompt_bank_item.dart';
import '../../../profile_prompts/presentation/providers/profile_prompt_provider.dart';
import '../../../psychology/presentation/providers/personality_provider.dart';
import '../../../../l10n/app_localizations.dart';

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
      appBar: AppBar(title: Text(AppLocalizations.of(context).drawerProfileIntelligence)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context).profileIntelEnrichTitle,
                style: AppTypography.headlineSmall
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(context).profileIntelEnrichSubtitle,
                style: AppTypography.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              NmIntelligenceCard(
                icon: Icons.chat_bubble_outline_rounded,
                title: AppLocalizations.of(context).profileCompletionGrowthPrompts,
                subtitle: promptsAsync.when(
                  data: (prompts) => prompts.isEmpty
                      ? 'Add up to 3 prompts'
                      : '${prompts.length} of 3 added',
                  loading: () => 'Loading…',
                  error: (_, __) => 'Add up to 3 prompts',
                ),
                onTap: () async {
                  final prompts = promptsAsync.value ?? [];
                  final result = await context.push<List<PromptAnswer>>(
                    RouteNames.choosePrompt,
                    extra: prompts,
                  );
                  if (result != null) {
                    await ref
                        .read(profilePromptRepositoryProvider)
                        .saveUserPrompts(result);
                  }
                  ref.invalidate(myPromptsProvider);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              NmIntelligenceCard(
                icon: Icons.psychology_alt_rounded,
                title: AppLocalizations.of(context).profileIntelPersonalityInsights,
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
              NmIntelligenceCard(
                icon: Icons.auto_awesome_rounded,
                title: AppLocalizations.of(context).profileCompletionGrowthHoroscope,
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
