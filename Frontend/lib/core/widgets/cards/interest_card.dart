import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';
import '../avatars/app_avatars.dart';
import '../buttons/outlined_button.dart';
import '../buttons/primary_button.dart';

/// Interest card for sent / received matrimonial express interest notifications.
class NmInterestCard extends StatelessWidget {
  final String name;
  final String details;
  final String message;
  final String? imageUrl;
  /// 'Male' / 'Female' / '' — picks the gender-aware placeholder icon
  /// when [imageUrl] is null.
  final String gender;
  final bool isReceived;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  /// Already-localized copy for the status badge and action buttons —
  /// defaults keep every existing call site's (currently English-only)
  /// behavior unchanged.
  final String receivedLabel;
  final String sentLabel;
  final String acceptLabel;
  final String declineLabel;
  /// When set, shown in the badge instead of [receivedLabel]/[sentLabel] —
  /// the actual interest status (Pending/Accepted/Declined) is more useful
  /// than direction once a screen already implies direction by which tab/
  /// section it's in (both interests tabs, the Sent/Received screens).
  final String? statusLabel;
  final Color? statusBackgroundColor;
  final Color? statusTextColor;
  final VoidCallback? onTap;
  /// Shown as a single outlined button (only when non-null, and only for a
  /// !isReceived/sent card) — withdrawing a still-pending sent interest.
  final VoidCallback? onWithdraw;
  final String withdrawLabel;
  /// True while an accept/decline/withdraw request for this exact record is
  /// in flight — disables and spins whichever action button is visible so a
  /// rapid second tap can't fire the same request twice.
  final bool isBusy;

  const NmInterestCard({
    super.key,
    required this.name,
    required this.details,
    required this.message,
    this.imageUrl,
    this.gender = '',
    this.isReceived = true,
    this.onAccept,
    this.onDecline,
    this.receivedLabel = 'Received',
    this.sentLabel = 'Sent',
    this.acceptLabel = 'Accept',
    this.declineLabel = 'Decline',
    this.statusLabel,
    this.statusBackgroundColor,
    this.statusTextColor,
    this.onTap,
    this.onWithdraw,
    this.isBusy = false,
    this.withdrawLabel = 'Withdraw',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final badgeBackground = statusBackgroundColor ??
        (isReceived ? AppColors.successLight : AppColors.infoLight);
    final badgeText =
        statusTextColor ?? (isReceived ? AppColors.success : AppColors.info);
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.card(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NmCircleAvatar(imageUrl: imageUrl, size: 52, gender: gender),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTypography.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      details,
                      style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondaryLight),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Flexible (not a bare Container) so an unusually long/scaled
              // status word shrinks-to-fit instead of forcing a RenderFlex
              // overflow next to the name column above.
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBackground,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel ?? (isReceived ? receivedLabel : sentLabel),
                    style: AppTypography.labelSmall.copyWith(
                      color: badgeText,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '"$message"',
                style: AppTypography.bodyMedium.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          ],
          if (isReceived && onAccept != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: NmOutlinedButton(
                    label: declineLabel,
                    onPressed: onDecline,
                    isLoading: isBusy,
                    height: 52,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: NmPrimaryButton(
                    label: acceptLabel,
                    onPressed: onAccept,
                    isLoading: isBusy,
                    height: 52,
                  ),
                ),
              ],
            ),
          ],
          if (!isReceived && onWithdraw != null) ...[
            const SizedBox(height: 16),
            NmOutlinedButton(
              label: withdrawLabel,
              onPressed: onWithdraw,
              isLoading: isBusy,
              height: 52,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: card,
      ),
    );
  }
}
