import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../features/psychology/domain/models/personality_result.dart';
import '../../constants/app_spacing.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';
import '../../../l10n/app_localizations.dart';

/// Displays the signed-in user's psychology (Marriage Compatibility) quiz
/// status. When [result] is null (not taken) and [onTakeQuizTap] is
/// provided, shows a "take the quiz" CTA. When completed, shows a
/// `Completed · Updated {date}` status — the backend has no single-user
/// score to display (compatibility is scored pairwise, server-side).
/// `onTakeQuizTap: null` hides the CTA/retake affordance.
class PsychologySection extends StatelessWidget {
  final PsychologyQuizResponse? result;
  final VoidCallback? onTakeQuizTap;

  const PsychologySection({
    super.key,
    required this.result,
    this.onTakeQuizTap,
  });

  /// `Updated {date}` for a saved response, or null when there's no date.
  static String? updatedLabel(AppLocalizations l10n, DateTime? at) {
    if (at == null) return null;
    return l10n.psychologyUpdatedOn(
      DateFormat.yMMMd(l10n.localeName).format(at.toLocal()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    if (result == null) {
      if (onTakeQuizTap == null) return const SizedBox.shrink();
      return GestureDetector(
        onTap: onTakeQuizTap,
        child: Container(
          width: double.infinity,
          padding: AppSpacing.cardPaddingLarge,
          decoration: AppDecorations.card(),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.scorePsychology.withValues(alpha: 0.10),
                  borderRadius: AppSpacing.borderRadiusMd,
                ),
                child: const Icon(
                  Icons.psychology_alt_rounded,
                  color: AppColors.scorePsychology,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context).riDiscoverPersonality,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context).riQuizTeaser,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.textTertiaryLight,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.secondary,
              ),
            ],
          ),
        ),
      );
    }

    final l10n = AppLocalizations.of(context);
    final updated = updatedLabel(l10n, result.lastUpdatedAt);
    final status = updated == null
        ? l10n.psychologyCompleted
        : '${l10n.psychologyCompleted} · $updated';

    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPaddingLarge,
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.psychology_alt_rounded,
                color: AppColors.scorePsychology,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).riPersonalityProfile,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall,
                ),
              ),
              if (onTakeQuizTap != null)
                TextButton(
                  onPressed: onTakeQuizTap,
                  child: Text(AppLocalizations.of(context).riRetake),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  status,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
