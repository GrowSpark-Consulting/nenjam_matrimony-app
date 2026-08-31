import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/conversation_entity.dart';

/// Small colored chip surfacing *why* a conversation exists / what just
/// happened in it (new match, interest accepted/declined, message request,
/// AI-suggested match) — one color per [ConversationSmartIndicator] value,
/// all drawn from [AppColors].
class SmartIndicatorChip extends StatelessWidget {
  final ConversationSmartIndicator indicator;

  const SmartIndicatorChip({super.key, required this.indicator});

  static const _icons = {
    ConversationSmartIndicator.newMatch: Icons.auto_awesome_rounded,
    ConversationSmartIndicator.interestAccepted: Icons.check_circle_rounded,
    ConversationSmartIndicator.interestDeclined: Icons.cancel_rounded,
    ConversationSmartIndicator.messageRequest: Icons.mail_rounded,
    ConversationSmartIndicator.aiSuggestedMatch: Icons.psychology_alt_rounded,
  };

  static const _colors = {
    ConversationSmartIndicator.newMatch: AppColors.secondary,
    ConversationSmartIndicator.interestAccepted: AppColors.success,
    ConversationSmartIndicator.interestDeclined: AppColors.error,
    ConversationSmartIndicator.messageRequest: AppColors.warning,
    ConversationSmartIndicator.aiSuggestedMatch: AppColors.primary,
  };

  String _label(AppLocalizations l10n) => switch (indicator) {
    ConversationSmartIndicator.newMatch => l10n.inboxSmartNewMatch,
    ConversationSmartIndicator.interestAccepted =>
      l10n.inboxSmartInterestAccepted,
    ConversationSmartIndicator.interestDeclined =>
      l10n.inboxSmartInterestDeclined,
    ConversationSmartIndicator.messageRequest => l10n.inboxSmartMessageRequest,
    ConversationSmartIndicator.aiSuggestedMatch => l10n.inboxSmartAiSuggested,
    ConversationSmartIndicator.none => '',
  };

  @override
  Widget build(BuildContext context) {
    if (indicator == ConversationSmartIndicator.none) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final color = _colors[indicator]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icons[indicator], size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            _label(l10n),
            style: AppTypography.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
