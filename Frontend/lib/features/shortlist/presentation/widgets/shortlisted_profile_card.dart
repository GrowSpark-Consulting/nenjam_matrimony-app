import 'package:flutter/material.dart';

import '../../../../core/router/profile_navigation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/avatars/app_avatars.dart';
import '../../../../core/widgets/badges/premium_badge.dart';
import '../../../../core/widgets/badges/verification_badge.dart';
import '../../../../core/widgets/buttons/outlined_button.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';

/// One card on the Shortlisted Profiles screen. Same shape/spacing family
/// as `NmInterestCard` (avatar + identity column + badge, action button
/// below) rather than the grid-oriented `NmProfileCard` — that one's photo
/// area relies on `Expanded`, which needs a bounded height from an
/// ancestor (fine inside Search's `GridView` with a fixed aspect ratio, not
/// fine in a plain scrolling list alongside a Remove button) — this shape
/// sizes naturally to its content instead, no fixed heights anywhere.
class ShortlistedProfileCard extends StatelessWidget {
  final DiscoveryProfileEntity profile;
  final VoidCallback onRemove;
  final bool isBusy;

  const ShortlistedProfileCard({
    super.key,
    required this.profile,
    required this.onRemove,
    this.isBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final details = [
      '${profile.age}',
      if (profile.location.isNotEmpty) profile.location,
      if (profile.profession.isNotEmpty) profile.profession,
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => openProfileDetail(context, profile),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: AppDecorations.card(isDark: isDark),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  NmCircleAvatar(
                    imageUrl: profile.photoUrls.isNotEmpty ? profile.photoUrls.first : null,
                    size: 52,
                    gender: profile.gender,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name,
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
                  if (profile.isVerified)
                    const NmVerificationBadge(size: NmBadgeSize.small)
                  else if (profile.compatibility.aiMatchPercent > 0)
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accentGold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${profile.compatibility.aiMatchPercent}%',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.accentGoldDark,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              NmOutlinedButton(
                label: l10n.shortlistRemoveButton,
                onPressed: onRemove,
                isLoading: isBusy,
                height: 52,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
