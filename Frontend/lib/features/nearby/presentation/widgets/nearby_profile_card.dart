import 'package:flutter/material.dart';

import '../../../../core/router/profile_navigation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/avatars/app_avatars.dart';
// NmBadgeSize lives in premium_badge.dart; verification_badge.dart imports it
// rather than re-exporting it, and Dart imports are not transitive.
import '../../../../core/widgets/badges/premium_badge.dart';
import '../../../../core/widgets/badges/verification_badge.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';

/// One card on the Near Me screen.
///
/// Same shape and spacing family as `ShortlistedProfileCard` — avatar, identity
/// column, trailing badge — and built from the same shared pieces
/// ([NmCircleAvatar], [AppDecorations.card], [NmVerificationBadge]) so Near Me
/// looks like the rest of the app rather than a screen of its own invention.
/// It differs in exactly one way, which is the point of the screen: distance
/// leads the detail line.
class NearbyProfileCard extends StatelessWidget {
  const NearbyProfileCard({super.key, required this.profile});

  final DiscoveryProfileEntity profile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final details = [
      '${profile.age}',
      if (profile.location.isNotEmpty) profile.location,
      if (profile.profession.isNotEmpty) profile.profession,
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        // Same navigation helper every other card uses, so the shared
        // Hero(tag: 'profile-photo-$id') transition into Profile Detail works
        // here with no extra wiring.
        onTap: () => openProfileDetail(context, profile),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: AppDecorations.card(),
          child: Row(
            children: [
              NmCircleAvatar(
                imageUrl: profile.photoUrls.isNotEmpty
                    ? profile.photoUrls.first
                    : null,
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
                    const SizedBox(height: 2),
                    Text(
                      details,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondaryLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    _DistanceLabel(distanceKm: profile.distanceKm, l10n: l10n),
                  ],
                ),
              ),
              if (profile.isVerified) ...[
                const SizedBox(width: 8),
                const NmVerificationBadge(size: NmBadgeSize.small),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "5 km away" pill.
///
/// Renders nothing at all when the distance is missing rather than showing a
/// placeholder: this endpoint always sends one, so a null here means something
/// genuinely unexpected, and an empty space is a better answer than a
/// confident "0 km away".
class _DistanceLabel extends StatelessWidget {
  const _DistanceLabel({required this.distanceKm, required this.l10n});

  final double? distanceKm;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final distance = distanceKm;
    if (distance == null) return const SizedBox.shrink();

    // Below a kilometre, a rounded number reads as "0 km away". The server
    // rounds to 100m for privacy, so a genuinely precise figure is not
    // available to show instead — the honest label is the qualitative one.
    final label = distance < 1
        ? l10n.nearbyDistanceUnderOneKm
        : l10n.nearbyDistanceAway(_format(distance));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.near_me_rounded,
            size: 12,
            color: AppColors.primary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Whole numbers lose the ".0" ("45 km away", not "45.0 km away"); anything
  /// finer keeps its single decimal ("2.3 km away").
  static String _format(double km) {
    final rounded = (km * 10).roundToDouble() / 10;
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
  }
}
