import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/avatars/gender_placeholder.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/profile_detail_entity.dart';

/// Collapsing parallax hero for the Profile Detail page — cover photo,
/// gradient scrim, a "Verified Profile" pill, and name/age/location
/// overlaid on the photo, shrinking into a plain app bar on scroll.
///
/// Bespoke rather than built on [NmSliverAppBar]: that widget has no
/// gradient scrim, badge, or name overlay, so reusing it would mean
/// immediately overriding most of its `flexibleSpace`.
class ProfileDetailHeroAppBar extends StatelessWidget {
  final ProfileDetailEntity detail;

  const ProfileDetailHeroAppBar({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final base = detail.base;
    final photoUrl = base.photoUrls.isNotEmpty ? base.photoUrls.first : null;
    final heroTag = 'profile-photo-${base.id}';

    // Half the viewport on tall/portrait screens, capped at 420 so it
    // never dominates a tablet or landscape viewport where half the
    // screen height would otherwise dwarf the content below it.
    final screenHeight = MediaQuery.sizeOf(context).height;
    final expandedHeight = (screenHeight * 0.5).clamp(280.0, 420.0);

    return SliverAppBar(
      expandedHeight: expandedHeight,
      pinned: true,
      stretch: true,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      leading: _CircleIconButton(
        icon: Icons.arrow_back_rounded,
        onTap: () => context.pop(),
      ),
      actions: [
        _CircleIconButton(
          icon: Icons.ios_share_rounded,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.profileDetailShareComingSoon)),
            );
          },
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: heroTag,
              child: photoUrl == null
                  ? NmGenderPlaceholder(gender: base.gender, iconSize: 72)
                  : (photoUrl.startsWith('assets/')
                        ? Image.asset(photoUrl, fit: BoxFit.cover)
                        : Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => NmGenderPlaceholder(
                              gender: base.gender,
                              iconSize: 72,
                            ),
                          )),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppGradients.imageOverlayStrong,
              ),
            ),
            Positioned(
              left: AppSpacing.base,
              right: AppSpacing.base,
              bottom: AppSpacing.lg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (base.isVerified)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.faceVerificationGreen,
                        borderRadius: AppSpacing.borderRadiusFull,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'VERIFIED PROFILE',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelSmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${base.name}, ${base.age}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.profileName.copyWith(
                      color: Colors.white,
                      fontSize: 26,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 16,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          base.caste.isNotEmpty
                              ? '${base.location} • ${base.caste}'
                              : base.location,
                          style: AppTypography.profileMetadata.copyWith(
                            color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Material(
        color: Colors.black.withValues(alpha: 0.25),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
