import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/indicators/nm_gradient_progress_bar.dart';
import '../../../../core/widgets/badges/premium_badge.dart' show NmBadgeSize;
import '../../../../core/widgets/badges/verification_badge.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/widgets/images/sized_network_photo.dart';

/// Identity Hero Card — the profile header for the Personal Matchmaking HQ.
///
/// Recreates the approved reference design: a 3:2 cover photo with rounded
/// top corners, name + Matrimony ID, a 2×2 stat grid (Age / Height /
/// Religion / Occupation), a location row, and an animated
/// profile-completion bar.
class NmIdentityHeroCard extends StatelessWidget {
  final String name;
  final int? age;
  final String nmId;
  final String location;
  final int profileCompletion;
  final bool isPremium;
  final bool isVerified;
  final String? imageUrl;

  // Stat grid fields
  final String? faith;
  final String? height;
  final String? maritalStatus;
  final String? profession;

  final VoidCallback? onEditTap;

  const NmIdentityHeroCard({
    super.key,
    required this.name,
    required this.age,
    required this.nmId,
    required this.location,
    this.profileCompletion = 82,
    this.isPremium = true,
    this.isVerified = true,
    this.imageUrl,
    this.faith,
    this.height,
    this.maritalStatus,
    this.profession,
    this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        // Keeps the card at a premium, phone-card proportion on tablets and
        // in landscape instead of stretching it edge-to-edge.
        constraints: const BoxConstraints(maxWidth: 560),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl2),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onEditTap,
            child: Ink(
              decoration: BoxDecoration(
                color: AppColors.cardLight,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(
                      alpha: 0.08,
                    ),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cover photo — fixed 3:2 ratio so it scales cleanly
                  // across every breakpoint without ever cropping oddly.
                  AspectRatio(
                    aspectRatio: 3 / 2,
                    child: _CoverImage(imageUrl: imageUrl),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: _HeroDetailsBlock(
                      name: name,
                      nmId: nmId,
                      age: age,
                      height: height,
                      faith: faith,
                      profession: profession,
                      location: location,
                      profileCompletion: profileCompletion,
                      isVerified: isVerified,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-bleed 3:2 cover photo with a soft bottom gradient for readability.
class _CoverImage extends StatelessWidget {
  final String? imageUrl;

  const _CoverImage({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: AppColors.surfaceVariantLight,
          child: imageUrl != null && imageUrl!.isNotEmpty
              ? (imageUrl!.startsWith('assets/')
                    ? Image.asset(imageUrl!, fit: BoxFit.cover)
                    : NmSizedNetworkPhoto(url: imageUrl!))
              : const Center(
                  child: Icon(
                    Icons.image_rounded,
                    size: 48,
                    color: AppColors.textTertiaryLight,
                  ),
                ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AppGradients.imageOverlay),
        ),
      ],
    );
  }
}

/// Name + ID, stat grid, location, and completion bar.
class _HeroDetailsBlock extends StatelessWidget {
  final String name;
  final String nmId;
  final int? age;
  final String? height;
  final String? faith;
  final String? profession;
  final String location;
  final int profileCompletion;
  final bool isVerified;

  const _HeroDetailsBlock({
    required this.name,
    required this.nmId,
    required this.age,
    required this.height,
    required this.faith,
    required this.profession,
    required this.location,
    required this.profileCompletion,
    required this.isVerified,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                name,
                style: AppTypography.profileName.copyWith(
                  fontSize: 22,
                  color: AppColors.primary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isVerified) ...[
              const SizedBox(width: AppSpacing.xs),
              const NmVerificationBadge(size: NmBadgeSize.small),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs2),
        Text(
          AppLocalizations.of(context).profileIdLabel(nmId),
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textTertiaryLight,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: AppSpacing.xl2),

        // 2×2 stats grid
        _StatGrid(
          age: age,
          height: height,
          faith: faith,
          profession: profession,
        ),

        const SizedBox(height: AppSpacing.lg),

        // Location row
        Row(
          children: [
            const Icon(
              Icons.location_on_rounded,
              size: 16,
              color: AppColors.liked,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                location,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.liked,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.lg),

        // Profile completion bar
        _ProfileCompletionBar(percentage: profileCompletion),
      ],
    );
  }
}

/// 2×2 stat grid — Age, Height, Religion, Occupation. Each row stretches
/// its two tiles to equal height; each tile fills equal width via Expanded.
class _StatGrid extends StatelessWidget {
  final int? age;
  final String? height;
  final String? faith;
  final String? profession;

  const _StatGrid({
    required this.age,
    required this.height,
    required this.faith,
    required this.profession,
  });

  @override
  Widget build(BuildContext context) {
    final identityValueColor = Theme.of(context).colorScheme.tertiary;

    // IntrinsicHeight gives each Row a concrete height to stretch its two
    // tiles into. Without it, crossAxisAlignment.stretch would need an
    // already-bounded height — but this card lives inside a
    // vertically-scrolling page, which gives it unbounded height, so a
    // plain Row here would crash (same fix as the tablet hero layout).
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatTile(
                  label: AppLocalizations.of(context).fieldAge,
                  value: age != null ? '$age Years' : '—',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatTile(
                  label: AppLocalizations.of(context).fieldHeight,
                  value: (height != null && height!.isNotEmpty) ? height! : '—',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatTile(
                  label: AppLocalizations.of(context).fieldReligion,
                  value: (faith != null && faith!.isNotEmpty) ? faith! : '—',
                  valueColor: identityValueColor,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatTile(
                  label: AppLocalizations.of(context).fieldOccupation,
                  value: (profession != null && profession!.isNotEmpty)
                      ? profession!
                      : '—',
                  valueColor: identityValueColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatTile({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariantLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textTertiaryLight,
              fontSize: 10,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs2),
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
              color:
                  valueColor ??
                  AppColors.textPrimaryLight,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Animated profile-completion bar — plum→magenta fill on a soft lavender track.
class _ProfileCompletionBar extends StatelessWidget {
  final int percentage;

  const _ProfileCompletionBar({required this.percentage});

  @override
  Widget build(BuildContext context) {
    final pct = percentage.clamp(0, 100);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                AppLocalizations.of(context).profileCompletionLabel,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textSecondaryLight,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '$pct%',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textSecondaryLight,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        NmGradientProgressBar(value: pct / 100),
      ],
    );
  }
}
