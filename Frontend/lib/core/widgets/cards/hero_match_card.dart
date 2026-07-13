import 'package:flutter/material.dart';

import '../../../features/discover/domain/entities/discovery_profile_entity.dart';
import '../../../features/discover/presentation/widgets/compatibility_badge.dart';
import '../../../features/discover/presentation/widgets/discover_action_rail.dart';
import '../../constants/app_spacing.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// "Today's Best Match" hero card for the Nenjam Relationship Intelligence
/// hub. Composes existing Discover pieces (score badges, action rail)
/// around a single spotlighted profile instead of forking a second large
/// profile-card implementation.
class NmHeroMatchCard extends StatelessWidget {
  final DiscoveryProfileEntity profile;
  final String whyLabel;
  final List<String> reasons;
  final VoidCallback? onViewProfile;
  final VoidCallback? onInterested;
  final VoidCallback? onSave;

  const NmHeroMatchCard({
    super.key,
    required this.profile,
    required this.whyLabel,
    required this.reasons,
    this.onViewProfile,
    this.onInterested,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final cardHeight = MediaQuery.sizeOf(context).height * 0.62;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusXl3),
      child: SizedBox(
        height: cardHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _HeroImage(photoUrls: profile.photoUrls),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0x4D041635),
                    Color(0xF2041635),
                  ],
                  stops: [0.0, 0.4, 1.0],
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: CompatibilityBadgeRow(
                compatibility: profile.compatibility,
                isVerified: profile.isVerified,
                isPremium: profile.isPremium,
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${profile.name}, ${profile.age}',
                            style: AppTypography.headlineMedium.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (profile.isVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified_rounded,
                              size: 20, color: Color(0xFFFFE08F)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (profile.location.isNotEmpty ||
                        profile.profession.isNotEmpty)
                      Text(
                        [
                          if (profile.location.isNotEmpty) profile.location,
                          if (profile.profession.isNotEmpty)
                            profile.profession,
                        ].join(' • '),
                        style: AppTypography.bodyMedium
                            .copyWith(color: Colors.white.withValues(alpha: 0.8)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (reasons.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        whyLabel,
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.accentGoldLight,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...reasons.take(2).map(
                            (reason) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.auto_awesome_rounded,
                                      size: 14, color: Colors.white70),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      reason,
                                      style: AppTypography.bodySmall.copyWith(
                                        color: Colors.white
                                            .withValues(alpha: 0.85),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ],
                    const SizedBox(height: AppSpacing.base),
                    DiscoverActionRail(
                      onInterested: onInterested,
                      onShortlist: onSave,
                      onShare: onViewProfile,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroImage extends StatelessWidget {
  final List<String> photoUrls;

  const _HeroImage({required this.photoUrls});

  @override
  Widget build(BuildContext context) {
    if (photoUrls.isEmpty) return _placeholder();
    final url = photoUrls.first;
    if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return Image.asset(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surfaceVariantDark,
        child: const Center(
          child: Icon(Icons.person_rounded,
              size: 48, color: AppColors.textTertiaryDark),
        ),
      );
}
