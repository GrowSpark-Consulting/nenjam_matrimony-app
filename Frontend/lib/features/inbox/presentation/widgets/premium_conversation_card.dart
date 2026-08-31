import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/avatars/gender_placeholder.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/conversation_entity.dart';

/// A conversation locked behind Premium — renders in place of
/// [ConversationCard] when `conversation.isLocked` is true. Uses the
/// design system's glass-accent surface (`AppDecorations.glass`) for a
/// luxury look distinct from an ordinary card, with a desaturated avatar,
/// a lock badge, and an Upgrade CTA.
class PremiumConversationCard extends StatelessWidget {
  final ConversationEntity conversation;

  const PremiumConversationCard({super.key, required this.conversation});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 6,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: AppDecorations.glass(),
        child: Row(
          children: [
            Stack(
              children: [
                const ColorFiltered(
                  colorFilter: ColorFilter.matrix(<double>[
                    0.2126,
                    0.7152,
                    0.0722,
                    0,
                    0,
                    0.2126,
                    0.7152,
                    0.0722,
                    0,
                    0,
                    0.2126,
                    0.7152,
                    0.0722,
                    0,
                    0,
                    0,
                    0,
                    0,
                    1,
                    0,
                  ]),
                  child: NmGenderPlaceholder(
                    gender: '',
                    iconSize: 32,
                    backgroundColor: AppColors.surfaceVariantLight,
                    iconColor: AppColors.textTertiaryLight,
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.35),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.inboxPremiumLockedName,
                    style: AppTypography.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.inboxPremiumLockedMessage,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondaryLight,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _UpgradePill(onTap: () => context.push(RouteNames.premium)),
          ],
        ),
      ),
    );
  }
}

class _UpgradePill extends StatelessWidget {
  final VoidCallback onTap;

  const _UpgradePill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.secondary, AppColors.secondaryDark],
            ),
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          ),
          child: Text(
            l10n.inboxUpgradeCta,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.textOnSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
