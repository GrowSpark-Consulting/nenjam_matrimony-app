import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NenjamNavigationDrawer
// ─────────────────────────────────────────────────────────────────────────────
//
// True Instagram-style premium side navigation drawer.
//
// Width:    78% of screen, capped at 330px.
// Height:   full screen.
// Surface:  warm ivory (AppColors.backgroundLight).
//
// Layout (top → bottom):
//   1. Compact profile header  (72px avatar + name + subtitle + ID pill)
//   2. Profile Strength bar    (max 50px, gold progress)
//   3. Scrollable menu list    (section dividers, active gold accent, 52px height)
//   4. Premium upgrade strip   (compact, gold border)
//   5. Fixed bottom footer     (version + Rate Us)
// ─────────────────────────────────────────────────────────────────────────────

class NenjamNavigationDrawer extends StatelessWidget {
  /// URL of the user's profile photo.
  final String? profileImageUrl;

  /// Display name (e.g. "Dhatri Patel").
  final String userName;

  /// Age shown in the subtitle line.
  final int age;

  /// Location shown in the subtitle line (e.g. "Chennai").
  final String location;

  /// Community label (e.g. "Tamil Community").
  final String community;

  /// Profile ID string (e.g. "NM112345").
  final String profileId;

  /// Profile completion 0–100.
  final int profileCompletionPercent;

  /// Whether the profile has a verification badge.
  final bool isVerified;

  /// Whether the user is a premium subscriber.
  final bool isPremium;

  // ── Tap callbacks ──────────────────────────────────────────────────────────
  final VoidCallback? onMyProfileTap;
  final VoidCallback? onEditProfileTap;
  final VoidCallback? onProfileIntelligenceTap;
  final VoidCallback? onVerificationCenterTap;
  final VoidCallback? onTrustScoreTap;
  final VoidCallback? onVisitorsTap;
  final VoidCallback? onInterestSentTap;
  final VoidCallback? onInterestReceivedTap;
  final VoidCallback? onShortlistTap;
  final VoidCallback? onLanguageTap;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onPrivacyTap;
  final VoidCallback? onHelpTap;
  final VoidCallback? onLogoutTap;
  final VoidCallback? onUpgradeTap;
  final VoidCallback? onCompleteProfileTap;
  final VoidCallback? onRateUsTap;

  const NenjamNavigationDrawer({
    super.key,
    this.profileImageUrl,
    this.userName = 'Dhatri Patel',
    this.age = 23,
    this.location = 'Chennai',
    this.community = 'Tamil Community',
    this.profileId = 'NM112345',
    this.profileCompletionPercent = 85,
    this.isVerified = true,
    this.isPremium = false,
    this.onMyProfileTap,
    this.onEditProfileTap,
    this.onProfileIntelligenceTap,
    this.onVerificationCenterTap,
    this.onTrustScoreTap,
    this.onVisitorsTap,
    this.onInterestSentTap,
    this.onInterestReceivedTap,
    this.onShortlistTap,
    this.onLanguageTap,
    this.onSettingsTap,
    this.onPrivacyTap,
    this.onHelpTap,
    this.onLogoutTap,
    this.onUpgradeTap,
    this.onCompleteProfileTap,
    this.onRateUsTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenWidth = MediaQuery.of(context).size.width;

    // Drawer width: 78% of screen, max 330px
    final drawerWidth = (screenWidth * 0.78).clamp(0.0, 330.0);

    return Drawer(
      width: drawerWidth,
      backgroundColor: AppColors.backgroundLight,
      elevation: 16,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(AppSpacing.radiusMd),
          bottomRight: Radius.circular(AppSpacing.radiusMd),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // ── 1. Compact profile header ──────────────────────────────────
            _ProfileHeader(
              imageUrl: profileImageUrl,
              name: userName,
              age: age,
              location: location,
              community: community,
              profileId: profileId,
              isVerified: isVerified,
              isPremium: isPremium,
            ),

            // ── 2. Profile Strength bar ────────────────────────────────────
            _ProfileStrengthBar(
              percent: profileCompletionPercent,
              l10n: l10n,
              onTap: () {
                Navigator.pop(context);
                onCompleteProfileTap?.call();
              },
            ),

            // Thin divider
            const Divider(
              height: 1,
              thickness: 1,
              color: AppColors.dividerLight,
              indent: AppSpacing.base,
              endIndent: AppSpacing.base,
            ),

            // ── 3. Scrollable menu ─────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.xs),

                    // Profile group
                    _DrawerItem(
                      icon: Icons.person_outline_rounded,
                      label: l10n.drawerProfile,
                      isActive: true,
                      onTap: () {
                        Navigator.pop(context);
                        onMyProfileTap?.call();
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.edit_outlined,
                      label: l10n.drawerEditProfile,
                      onTap: () {
                        Navigator.pop(context);
                        onEditProfileTap?.call();
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.auto_awesome_rounded,
                      label: 'Profile Intelligence',
                      onTap: () {
                        Navigator.pop(context);
                        onProfileIntelligenceTap?.call();
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.shield_outlined,
                      label: 'Verification Center',
                      onTap: () {
                        Navigator.pop(context);
                        onVerificationCenterTap?.call();
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.star_outline_rounded,
                      label: 'Trust Score',
                      onTap: () {
                        Navigator.pop(context);
                        onTrustScoreTap?.call();
                      },
                    ),

                    _MenuDivider(),

                    // Match Activity group
                    _DrawerItem(
                      icon: Icons.visibility_outlined,
                      label: l10n.drawerVisitors,
                      onTap: () {
                        Navigator.pop(context);
                        onVisitorsTap?.call();
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.outbox_outlined,
                      label: l10n.drawerInterestSent,
                      onTap: () {
                        Navigator.pop(context);
                        onInterestSentTap?.call();
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.move_to_inbox_outlined,
                      label: l10n.drawerInterestReceived,
                      onTap: () {
                        Navigator.pop(context);
                        onInterestReceivedTap?.call();
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.favorite_border_rounded,
                      label: l10n.drawerShortlist,
                      onTap: () {
                        Navigator.pop(context);
                        onShortlistTap?.call();
                      },
                    ),

                    _MenuDivider(),

                    // Settings group
                    _DrawerItem(
                      icon: Icons.language_outlined,
                      label: l10n.drawerLanguage,
                      onTap: () {
                        Navigator.pop(context);
                        onLanguageTap?.call();
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.settings_outlined,
                      label: l10n.drawerSettings,
                      onTap: () {
                        Navigator.pop(context);
                        onSettingsTap?.call();
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.lock_outline_rounded,
                      label: l10n.drawerPrivacy,
                      onTap: () {
                        Navigator.pop(context);
                        onPrivacyTap?.call();
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.help_outline_rounded,
                      label: l10n.drawerHelp,
                      onTap: () {
                        Navigator.pop(context);
                        onHelpTap?.call();
                      },
                    ),

                    _MenuDivider(),

                    // Logout
                    _DrawerItem(
                      icon: Icons.logout_rounded,
                      label: l10n.drawerLogout,
                      labelColor: AppColors.error,
                      iconColor: AppColors.error,
                      showChevron: false,
                      onTap: () {
                        Navigator.pop(context);
                        onLogoutTap?.call();
                      },
                    ),

                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
            ),

            // ── 4. Premium upgrade strip ───────────────────────────────────
            if (!isPremium)
              _PremiumStrip(
                l10n: l10n,
                onTap: () {
                  Navigator.pop(context);
                  onUpgradeTap?.call();
                },
              ),

            // ── 5. Fixed footer ────────────────────────────────────────────
            _DrawerFooter(onRateUsTap: onRateUsTap, l10n: l10n),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Header — compact, 72px avatar
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final int age;
  final String location;
  final String community;
  final String profileId;
  final bool isVerified;
  final bool isPremium;

  const _ProfileHeader({
    required this.imageUrl,
    required this.name,
    required this.age,
    required this.location,
    required this.community,
    required this.profileId,
    required this.isVerified,
    required this.isPremium,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── 72px circular avatar with gold ring ────────────────────────
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.accentGold,
                    width: 1.5,
                  ),
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primarySurface,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _AvatarImage(imageUrl: imageUrl),
                ),
              ),
              // Verification badge overlay
              if (isVerified)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.verifiedBlue,
                      border: Border.all(
                        color: AppColors.backgroundLight,
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
              // Premium crown badge overlay
              if (isPremium)
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accentGold,
                      border: Border.all(
                        color: AppColors.backgroundLight,
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      size: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // ── Name ─────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              if (isVerified) ...[
                const SizedBox(width: AppSpacing.xs2),
                const Icon(
                  Icons.verified_rounded,
                  size: 16,
                  color: AppColors.verifiedBlue,
                ),
              ],
            ],
          ),

          // ── Subtitle: age • location ─────────────────────────────────────
          const SizedBox(height: AppSpacing.xs2),
          Text(
            '$age • $location',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondaryLight,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),

          // ── Community ────────────────────────────────────────────────────
          if (community.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs2),
            Text(
              community,
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.accentGoldDark,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],

          // ── Profile ID pill ──────────────────────────────────────────────
          if (profileId.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: AppColors.accentGoldSurface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                border: Border.all(
                  color: AppColors.accentGold.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                'ID: $profileId',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.accentGoldDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AvatarImage extends StatelessWidget {
  final String? imageUrl;

  const _AvatarImage({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _icon(),
      );
    }
    return _icon();
  }

  Widget _icon() => const Icon(
        Icons.person_rounded,
        size: 36,
        color: AppColors.primary,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Strength Bar — compact, max 50px
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileStrengthBar extends StatelessWidget {
  final int percent;
  final AppLocalizations l10n;
  final VoidCallback? onTap;

  const _ProfileStrengthBar({
    required this.percent,
    required this.l10n,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = percent.clamp(0, 100);

    return GestureDetector(
      onTap: clamped < 100 ? onTap : null,
      child: Container(
        height: 46,
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.xs,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.accentGoldSurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
            color: AppColors.accentGold.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.drawerProfileStrength,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textSecondaryLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '$clamped%',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.accentGoldDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Gold progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              child: SizedBox(
                height: 4,
                child: LinearProgressIndicator(
                  value: clamped / 100.0,
                  backgroundColor: AppColors.borderLight,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.accentGold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Menu Divider
// ─────────────────────────────────────────────────────────────────────────────

class _MenuDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 12,
      thickness: 1,
      color: AppColors.dividerLight,
      indent: AppSpacing.base,
      endIndent: AppSpacing.base,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drawer Menu Item — 52px height
// ─────────────────────────────────────────────────────────────────────────────

class _DrawerItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool showChevron;
  final Color? labelColor;
  final Color? iconColor;
  final VoidCallback? onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.showChevron = true,
    this.labelColor,
    this.iconColor,
    this.onTap,
  });

  @override
  State<_DrawerItem> createState() => _DrawerItemState();
}

class _DrawerItemState extends State<_DrawerItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.96,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = _ctrl;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _effectiveIconColor =>
      widget.iconColor ??
      (widget.isActive ? AppColors.accentGoldDark : AppColors.accentGold);

  Color get _effectiveLabelColor =>
      widget.labelColor ?? AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.reverse(),
        onTapUp: (_) {
          _ctrl.forward();
          widget.onTap?.call();
        },
        onTapCancel: () => _ctrl.forward(),
        child: Container(
          height: 52,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppColors.accentGoldSurface
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: widget.isActive
                ? const Border(
                    left: BorderSide(
                      color: AppColors.accentGold,
                      width: 3,
                    ),
                  )
                : null,
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: widget.isActive
                  ? AppSpacing.sm
                  : AppSpacing.sm + 3,
              right: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 20,
                  color: _effectiveIconColor,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    widget.label,
                    style: AppTypography.bodyMedium.copyWith(
                      color: _effectiveLabelColor,
                      fontWeight: widget.isActive
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.showChevron)
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.textTertiaryLight,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium Upgrade Strip — compact
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumStrip extends StatelessWidget {
  final AppLocalizations l10n;
  final VoidCallback? onTap;

  const _PremiumStrip({required this.l10n, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.xs,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.accentGold, width: 1),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.workspace_premium_rounded,
              size: 18,
              color: AppColors.accentGoldLight,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                l10n.drawerPremiumTitle,
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.accentGoldLight,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: AppColors.accentGold,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
              child: Text(
                l10n.drawerUpgrade,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textOnGold,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fixed Footer
// ─────────────────────────────────────────────────────────────────────────────

class _DrawerFooter extends StatelessWidget {
  final VoidCallback? onRateUsTap;
  final AppLocalizations l10n;

  const _DrawerFooter({required this.l10n, this.onRateUsTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.dividerLight),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              '${l10n.drawerVersionLabel} v2.4',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.textTertiaryLight,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onRateUsTap,
            child: Text(
              'Rate Us ⭐',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.accentGoldDark,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
