import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';

/// Visual state for [NmVerificationStatusCard]. Deliberately generic (not
/// tied to any one verification's own status enum) so it can drive mobile
/// OTP, email reflection, and document-upload cards alike with one widget —
/// every state below only ever changes color/icon/trailing content, never
/// the card's layout, so switching states never reflows surrounding cards.
enum NmVerificationCardStatus {
  notVerified,
  uploading,
  pending,
  verified,
  rejected,
  failed,
}

/// Reusable "icon + title + subtitle + status" verification row — a richer
/// sibling of [NmChecklistItemCard] (core/widgets/cards/checklist_item_card.dart)
/// for verifications that have more than a plain done/not-done state
/// (uploading with progress, pending review, rejected with a reason).
/// Visually consistent with [NmChecklistItemCard] by design (same card
/// shell, border, icon-chip language) so the registration wizard's
/// Verification step still reads as one family of cards.
class NmVerificationStatusCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final NmVerificationCardStatus status;
  final String actionLabel;
  final VoidCallback? onAction;
  final String? statusLabel;
  final String? rejectionReason;

  /// 0.0-1.0 upload progress; null renders an indeterminate spinner while
  /// [status] is [NmVerificationCardStatus.uploading].
  final double? progress;

  const NmVerificationStatusCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.actionLabel,
    this.onAction,
    this.statusLabel,
    this.rejectionReason,
    this.progress,
  });

  Color _accentColor() => switch (status) {
    NmVerificationCardStatus.verified => AppColors.success,
    NmVerificationCardStatus.pending => AppColors.warning,
    NmVerificationCardStatus.rejected ||
    NmVerificationCardStatus.failed => AppColors.error,
    NmVerificationCardStatus.uploading ||
    NmVerificationCardStatus.notVerified => AppColors.primary,
  };

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor();
    final isDone = status == NmVerificationCardStatus.verified;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.card().copyWith(
        border: Border.all(
          color: isDone || status == NmVerificationCardStatus.pending
              ? accent
              : AppColors.borderLight,
          width: isDone ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: status == NmVerificationCardStatus.uploading
                    ? Padding(
                        padding: const EdgeInsets.all(14),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          value: progress,
                          valueColor: AlwaysStoppedAnimation(accent),
                        ),
                      )
                    : Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isDone)
                          const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.success,
                            size: 18,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textTertiaryLight,
                      ),
                    ),
                    if (statusLabel != null) ...[
                      const SizedBox(height: 6),
                      _StatusChip(label: statusLabel!, color: accent),
                    ],
                    if (status == NmVerificationCardStatus.rejected &&
                        rejectionReason != null &&
                        rejectionReason!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        rejectionReason!,
                        style: AppTypography.bodySmall.copyWith(color: accent),
                      ),
                    ],
                  ],
                ),
              ),
              if (onAction != null && !isDone) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  child: Text(
                    actionLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
