import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../theme/app_typography.dart';
import '../avatars/gender_placeholder.dart';
import '../badges/premium_badge.dart';
import '../badges/verification_badge.dart';
import '../images/sized_network_photo.dart';

/// Premium profile card — used in search, matches, and discovery.
class NmProfileCard extends StatelessWidget {
  final String name;
  final String age;
  final String location;
  final String? imageUrl;
  final String? profession;

  /// 'Male' / 'Female' / '' — picks the icon [NmGenderPlaceholder] shows
  /// when [imageUrl] is null/empty.
  final String gender;
  final bool isVerified;
  final bool isPremium;
  final bool isOnline;
  final VoidCallback? onTap;
  final VoidCallback? onLikeTap;
  final VoidCallback? onShortlistTap;

  /// True when [onShortlistTap] represents "remove" rather than "save" —
  /// swaps the footer icon to the filled bookmark so a card already known
  /// to be shortlisted (e.g. on the Shortlisted Profiles screen, where
  /// every card is by definition already saved) doesn't show the same
  /// "not yet saved" outline icon a fresh Discover/Search card would.
  final bool isShortlisted;

  /// When set, wraps the card photo in a [Hero] with this tag so tapping
  /// through to Profile Detail animates the same photo into its hero.
  /// Defaults to null (no [Hero]) so existing call sites are unaffected.
  final String? heroTag;

  const NmProfileCard({
    super.key,
    required this.name,
    required this.age,
    required this.location,
    this.imageUrl,
    this.profession,
    this.gender = '',
    this.isVerified = false,
    this.isPremium = false,
    this.isOnline = false,
    this.onTap,
    this.onLikeTap,
    this.onShortlistTap,
    this.isShortlisted = false,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: AppDecorations.card(isDark: isDark),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile image fills whatever height the parent leaves after
            // the footer below takes its natural size — an AspectRatio
            // here would instead force its own height regardless of what
            // the parent (grid cell, fixed-size shelf card, etc.) actually
            // gives the card, which is what caused the bottom overflow.
            // BoxFit.cover on the photo itself keeps the crop looking
            // intentional at whatever height results.
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Image placeholder
                  _wrapHero(
                    Container(
                      color: isDark
                          ? AppColors.surfaceVariantDark
                          : AppColors.surfaceVariantLight,
                      child: imageUrl != null
                          ? (imageUrl!.startsWith('assets/')
                                ? Image.asset(
                                    imageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _buildPlaceholder(isDark),
                                  )
                                : NmSizedNetworkPhoto(
                                    url: imageUrl!,
                                    errorBuilder: (_, __, ___) =>
                                        _buildPlaceholder(isDark),
                                  ))
                          : _buildPlaceholder(isDark),
                    ),
                  ),

                  // Gradient overlay
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: AppDecorations.imageOverlay,
                    ),
                  ),

                  // Online indicator
                  if (isOnline)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.online,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),

                  // Badges — Wrap rather than Row so a future third badge
                  // wraps onto a second line instead of overflowing the
                  // card width.
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (isPremium)
                          const NmPremiumBadge(size: NmBadgeSize.small),
                        if (isVerified)
                          const NmVerificationBadge(size: NmBadgeSize.small),
                      ],
                    ),
                  ),

                  // Bottom info overlay
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$name, $age',
                          style: AppTypography.titleMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          location,
                          style: AppTypography.bodySmall.copyWith(
                            color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Bottom section
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      profession ?? '',
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onShortlistTap != null)
                    _ActionIcon(
                      icon: isShortlisted
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      onTap: onShortlistTap!,
                      color: isShortlisted ? AppColors.secondary : null,
                      tooltip: l10n.profileCardShortlist,
                    ),
                  if (onLikeTap != null) ...[
                    const SizedBox(width: 4),
                    _ActionIcon(
                      icon: Icons.favorite_border_rounded,
                      onTap: onLikeTap!,
                      color: AppColors.liked,
                      tooltip: l10n.profileCardLike,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wrapHero(Widget child) =>
      heroTag == null ? child : Hero(tag: heroTag!, child: child);

  Widget _buildPlaceholder(bool isDark) => NmGenderPlaceholder(gender: gender);
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final String tooltip;

  const _ActionIcon({
    required this.icon,
    required this.onTap,
    this.color,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}
