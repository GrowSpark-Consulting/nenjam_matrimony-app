import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/conversation_starter_card.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/conversation_starter_provider.dart';
import '../providers/todays_best_match_provider.dart';

/// Section 6 — Conversation Starter, 3 suggested openers for today's best
/// match. Placeholder-architecture: mock-backed today, Gemini-ready later.
class ConversationStarterSection extends ConsumerWidget {
  const ConversationStarterSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bestMatchAsync = ref.watch(todaysBestMatchProvider);

    return bestMatchAsync.when(
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        return _StartersList(targetUserId: profile.id, targetName: profile.name);
      },
      loading: () => const SizedBox.shrink(),
      error: (error, _) => const SizedBox.shrink(),
    );
  }
}

class _StartersList extends ConsumerWidget {
  final String targetUserId;
  final String targetName;

  const _StartersList({required this.targetUserId, required this.targetName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(conversationStarterProvider(targetUserId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.nenjamHubConversationStarterTitle,
            style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(l10n.nenjamHubConversationStarterSubtitle(targetName),
            style: AppTypography.bodyMedium),
        const SizedBox(height: 12),
        async.when(
          data: (starters) => Column(
            children: [
              for (final starter in starters)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: NmConversationStarterCard(
                    message: starter.message,
                    actionLabel: l10n.nenjamHubUseThis,
                    onUse: () {},
                  ),
                ),
            ],
          ),
          loading: () => const NmShimmer(height: 80, borderRadius: 16),
          error: (error, _) => NmErrorWidget(
            onRetry: () =>
                ref.invalidate(conversationStarterProvider(targetUserId)),
          ),
        ),
      ],
    );
  }
}
