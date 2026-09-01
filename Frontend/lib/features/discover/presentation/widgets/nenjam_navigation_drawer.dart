import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/indicators/nm_gradient_progress_bar.dart';
import '../../../../core/widgets/avatars/app_avatars.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../../inbox/presentation/widgets/unread_badge.dart';
import '../../../interests/domain/repositories/interests_repository.dart';
import '../../../interests/presentation/providers/interests_provider.dart';
import '../../../profile/presentation/providers/profile_dashboard_providers.dart';
import '../../../profile/presentation/utils/profile_dashboard_mapper.dart';
import '../../../profile_photos/presentation/providers/photo_providers.dart';
import '../../../shortlist/presentation/providers/shortlist_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NenjamNavigationDrawer
// ─────────────────────────────────────────────────────────────────────────────
//
// True Instagram-style premium side navigation drawer.
//
// Width:    78% of screen, capped at 330px.
// Height:   full screen.
// Surface:  warm blush white (AppColors.backgroundLight).
//
// Layout (top → bottom):
//   1. Compact profile header  (72px avatar + name + subtitle + ID pill)
//   2. Profile Strength bar    (max 50px, plum→magenta progress)
//   3. Scrollable menu list    (section dividers, active plum accent, 52px height)
//   4. Premium upgrade strip   (compact, magenta border)
//   5. Fixed bottom footer     (version + Rate Us)
// ─────────────────────────────────────────────────────────────────────────────

class NenjamNavigationDrawer extends ConsumerStatefulWidget {
  /// Whether the user is a premium subscriber.
  final bool isPremium;

  /// Tapping the avatar or the "+" badge — both open the same photo
  /// management bottom sheet ([showPhotoManagerBottomSheet]).
  final VoidCallback? onAvatarTap;

  // ── Tap callbacks ──────────────────────────────────────────────────────────
  final VoidCallback? onMyProfileTap;
  final VoidCallback? onEditProfileTap;
  final VoidCallback? onPartnerPreferencesTap;
  final VoidCallback? onProfileIntelligenceTap;
  final VoidCallback? onVerificationCenterTap;
  final VoidCallback? onTrustScoreTap;
  final VoidCallback? onInterestSentTap;
  final VoidCallback? onInterestReceivedTap;
  final VoidCallback? onShortlistTap;
  final VoidCallback? onNearMeTap;
  final VoidCallback? onProfileViewersTap;
  final VoidCallback? onLanguageTap;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onPrivacyTap;
  final VoidCallback? onHelpTap;

  /// Future-returning so the drawer can show a loading state and guard
  /// against double-taps while the confirm dialog / sign-out call is
  /// in flight — see [_NenjamNavigationDrawerState._handleLogout].
  final Future<void> Function()? onLogoutTap;
  final VoidCallback? onUpgradeTap;
  final VoidCallback? onCompleteProfileTap;
  final VoidCallback? onRateUsTap;

  const NenjamNavigationDrawer({
    super.key,
    this.isPremium = false,
    this.onAvatarTap,
    this.onMyProfileTap,
    this.onEditProfileTap,
    this.onPartnerPreferencesTap,
    this.onProfileIntelligenceTap,
    this.onVerificationCenterTap,
    this.onTrustScoreTap,
    this.onInterestSentTap,
    this.onInterestReceivedTap,
    this.onShortlistTap,
    this.onNearMeTap,
    this.onProfileViewersTap,
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
  ConsumerState<NenjamNavigationDrawer> createState() =>
      _NenjamNavigationDrawerState();
}

class _NenjamNavigationDrawerState
    extends ConsumerState<NenjamNavigationDrawer> {
  bool _loggingOut = false;

  /// Re-fetches every provider this drawer (and its badge counts) already
  /// reads — no new data sources, just re-triggering existing ones.
  Future<void> _onRefresh() async {
    await Future.wait([
      ref.refresh(profileDraftResponseProvider.future),
      ref.refresh(myPhotosProvider.future),
      ref.refresh(interestsNotifierProvider.future),
      ref.refresh(shortlistNotifierProvider.future),
    ]);
  }

  Future<void> _handleLogout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await widget.onLogoutTap?.call();
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Drawer width: 78% of screen, max 330px
    final drawerWidth = (screenWidth * 0.78).clamp(0.0, 330.0);

    // Single fetch shared by the header + strength bar — same provider the
    // Profile page and Profile Completion screen already read, so this
    // drawer never disagrees with them about who the user is or how
    // complete their profile is.
    final draftAsync = ref.watch(myProfileDraftProvider);
    final completionAsync = ref.watch(backendProfileCompletionProvider);
    final authUser = ref.watch(currentAuthUserProvider);
    final draft = draftAsync.valueOrNull;

    final identityLoading = draftAsync.isLoading && !draftAsync.hasValue;
    final identityError = draftAsync.hasError && !draftAsync.hasValue;

    return Drawer(
      width: drawerWidth,
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
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
            // ── 1 & 2. Compact profile header + Profile Strength bar ───────
            if (identityLoading)
              const _IdentitySkeleton()
            else if (identityError)
              _IdentityError(
                onRetry: () => ref.invalidate(profileDraftResponseProvider),
              )
            else ...[
              _ProfileHeader(
                imageUrl: null,
                gender: draft?.basicDetails.gender ?? '',
                name: profileDisplayName(draft, authUser, l10n),
                age: profileDisplayAge(draft) ?? 0,
                location: profileDisplayLocation(draft, l10n),
                community: draft?.religionDetails.community ?? '',
                profileId: profileDisplayId(authUser),
                isVerified: authUser?.isFullyVerified ?? false,
                isPremium: widget.isPremium,
                onAvatarTap: widget.onAvatarTap,
              ),
              _ProfileStrengthBar(
                percent: completionAsync.valueOrNull ?? 85,
                l10n: l10n,
                onTap: () {
                  Navigator.pop(context);
                  widget.onCompleteProfileTap?.call();
                },
              ),
            ],

            // Thin divider
            Divider(
              height: 1,
              thickness: 1,
              color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
              indent: AppSpacing.base,
              endIndent: AppSpacing.base,
            ),

            // ── 3. Scrollable menu ─────────────────────────────────────────
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                color: AppColors.secondary,
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
                          widget.onMyProfileTap?.call();
                        },
                      ),
                      _DrawerItem(
                        icon: Icons.edit_outlined,
                        label: l10n.drawerEditProfile,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onEditProfileTap?.call();
                        },
                      ),
                      _DrawerItem(
                        icon: Icons.favorite_border_rounded,
                        label: l10n.drawerPartnerPreferences,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onPartnerPreferencesTap?.call();
                        },
                      ),
                      _DrawerItem(
                        icon: Icons.auto_awesome_rounded,
                        label: l10n.drawerProfileIntelligence,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onProfileIntelligenceTap?.call();
                        },
                      ),
                      _DrawerItem(
                        icon: Icons.shield_outlined,
                        label: l10n.drawerVerificationCenter,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onVerificationCenterTap?.call();
                        },
                      ),
                      _DrawerItem(
                        icon: Icons.star_outline_rounded,
                        label: l10n.drawerTrustScore,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onTrustScoreTap?.call();
                        },
                      ),

                      _MenuDivider(),

                      // Match Activity group
                      Consumer(
                        builder: (context, ref, _) => _DrawerItem(
                          icon: Icons.outbox_outlined,
                          label: l10n.drawerInterestSent,
                          count: ref
                              .watch(sentInterestsProvider)
                              .valueOrNull
                              ?.where((r) => r.status == InterestStatus.pending)
                              .length,
                          onTap: () {
                            Navigator.pop(context);
                            widget.onInterestSentTap?.call();
                          },
                        ),
                      ),
                      Consumer(
                        builder: (context, ref, _) => _DrawerItem(
                          icon: Icons.move_to_inbox_outlined,
                          label: l10n.drawerInterestReceived,
                          count: ref
                              .watch(receivedInterestsProvider)
                              .valueOrNull
                              ?.where((r) => r.status == InterestStatus.pending)
                              .length,
                          onTap: () {
                            Navigator.pop(context);
                            widget.onInterestReceivedTap?.call();
                          },
                        ),
                      ),
                      Consumer(
                        builder: (context, ref, _) => _DrawerItem(
                          // Bookmark (not the heart already used by Partner
                          // Preferences above) to match the icon used
                          // everywhere else for this exact concept — Discover,
                          // Matches, Search, Profile Detail.
                          icon: Icons.bookmark_border_rounded,
                          label: l10n.drawerShortlist,
                          count: ref.watch(shortlistCountProvider),
                          onTap: () {
                            Navigator.pop(context);
                            widget.onShortlistTap?.call();
                          },
                        ),
                      ),
                      _DrawerItem(
                        // Same near_me arrow the distance pill on each Near Me
                        // card uses, so the icon means one thing app-wide.
                        icon: Icons.near_me_outlined,
                        label: l10n.drawerNearMe,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onNearMeTap?.call();
                        },
                      ),
                      _DrawerItem(
                        // Same eye used by the Profile Viewers empty state and
                        // by the PROFILE_VIEW notification icon.
                        icon: Icons.visibility_outlined,
                        label: l10n.profileViewersTitle,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onProfileViewersTap?.call();
                        },
                      ),

                      _MenuDivider(),

                      // Settings group
                      _DrawerItem(
                        icon: Icons.language_outlined,
                        label: l10n.drawerLanguage,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onLanguageTap?.call();
                        },
                      ),
                      _DrawerItem(
                        icon: Icons.settings_outlined,
                        label: l10n.drawerSettings,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onSettingsTap?.call();
                        },
                      ),
                      _DrawerItem(
                        icon: Icons.lock_outline_rounded,
                        label: l10n.drawerPrivacy,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onPrivacyTap?.call();
                        },
                      ),
                      _DrawerItem(
                        icon: Icons.help_outline_rounded,
                        label: l10n.drawerHelp,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onHelpTap?.call();
                        },
                      ),

                      _MenuDivider(),

                      // Logout — no Navigator.pop before the call: confirmAndLogout
                      // shows its confirm dialog over the still-open drawer, and
                      // its final context.go(RouteNames.login) replaces the whole
                      // page (drawer included) once confirmed, so popping first
                      // would only hide the loading state below without helping.
                      _DrawerItem(
                        icon: Icons.logout_rounded,
                        label: l10n.drawerLogout,
                        labelColor: AppColors.error,
                        iconColor: AppColors.error,
                        showChevron: false,
                        isLoading: _loggingOut,
                        onTap: _handleLogout,
                      ),

                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
              ),
            ),

            // ── 4. Premium upgrade strip ───────────────────────────────────
            if (!widget.isPremium)
              _PremiumStrip(
                l10n: l10n,
                onTap: () {
                  Navigator.pop(context);
                  widget.onUpgradeTap?.call();
                },
              ),

            // ── 5. Fixed footer ────────────────────────────────────────────
            _DrawerFooter(onRateUsTap: widget.onRateUsTap, l10n: l10n),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header/strength-bar loading + error placeholders — shown only on a cold
// start with no cached draft yet; a failed pull-to-refresh keeps showing the
// last-known values instead (see NenjamNavigationDrawer.build).
// ─────────────────────────────────────────────────────────────────────────────

class _IdentitySkeleton extends StatelessWidget {
  const _IdentitySkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
          NmShimmer.circle(size: 72),
          SizedBox(height: AppSpacing.sm),
          NmShimmer(width: 140, height: 18, borderRadius: AppSpacing.radiusSm),
          SizedBox(height: AppSpacing.xs2),
          NmShimmer(width: 100, height: 13, borderRadius: AppSpacing.radiusSm),
          SizedBox(height: AppSpacing.sm),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: NmShimmer(height: 46, borderRadius: AppSpacing.radiusSm),
          ),
        ],
      ),
    );
  }
}

class _IdentityError extends StatelessWidget {
  final VoidCallback onRetry;

  const _IdentityError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              AppLocalizations.of(context).commonCouldNotLoadProfile,
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(
              AppLocalizations.of(context).commonRetry,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.secondaryDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Header — compact, 72px avatar
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final String? imageUrl;
  final String gender;
  final String name;
  final int age;
  final String location;
  final String community;
  final String profileId;
  final bool isVerified;
  final bool isPremium;
  final VoidCallback? onAvatarTap;

  const _ProfileHeader({
    required this.imageUrl,
    this.gender = '',
    required this.name,
    required this.age,
    required this.location,
    required this.community,
    required this.profileId,
    required this.isVerified,
    required this.isPremium,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final badgeRingColor = isDark
        ? AppColors.backgroundDark
        : AppColors.backgroundLight;

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
          // ── 72px circular avatar with plum ring ────────────────────────
          Stack(
            clipBehavior: Clip.none,
            children: [
              Semantics(
                button: onAvatarTap != null,
                label: AppLocalizations.of(
                  context,
                ).drawerChangePhotoSemanticLabel,
                child: GestureDetector(
                  onTap: onAvatarTap,
                  child: Container(
                    width: 72,
                    height: 72,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.secondary,
                        width: 1.5,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? AppColors.surfaceVariantDark
                            : AppColors.primarySurface,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _LiveAvatarImage(
                        imageUrl: imageUrl,
                        gender: gender,
                      ),
                    ),
                  ),
                ),
              ),
              // "+" badge — same tap target as the avatar itself, opens the
              // identical photo management bottom sheet.
              if (onAvatarTap != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: onAvatarTap,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.verifiedBlue,
                        border: Border.all(color: badgeRingColor, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
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
                      border: Border.all(color: badgeRingColor, width: 1.5),
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
                      color: AppColors.secondary,
                      border: Border.all(color: badgeRingColor, width: 1.5),
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
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.primary,
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
            [if (age > 0) '$age', location].join(' • '),
            style: AppTypography.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
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
                color: AppColors.secondaryDark,
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
                color: AppColors.accentSoft.withValues(
                  alpha: isDark ? 0.16 : 1.0,
                ),
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                border: Border.all(
                  color: AppColors.secondary.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                AppLocalizations.of(context).profileIdLabel(profileId),
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.secondaryDark,
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

/// Reads the live current-user photo directly from [myPrimaryPhotoUrlProvider]
/// — scoped to just this leaf widget (not the whole drawer) so uploading,
/// replacing, or deleting a photo only rebuilds this small avatar, not the
/// entire [NenjamNavigationDrawer] menu tree. Falls back to the [imageUrl]
/// prop (the caller's best-known value) until the provider has loaded, then
/// to the gender placeholder if the user has no photos at all.
class _LiveAvatarImage extends ConsumerWidget {
  final String? imageUrl;
  final String gender;

  const _LiveAvatarImage({this.imageUrl, this.gender = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveUrl = ref.watch(myPrimaryPhotoUrlProvider);
    return NmCircleAvatar(
      imageUrl: liveUrl ?? imageUrl,
      size: 68,
      gender: gender,
      // Bias the cover-crop upward so the face stays centered in the
      // circle without the head's top being cut off by a dead-center crop.
      alignment: const Alignment(0, -0.2),
    );
  }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          color: AppColors.softLavender.withValues(alpha: isDark ? 0.16 : 1.0),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
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
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '$clamped%',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Plum→magenta progress bar
            NmGradientProgressBar(value: clamped / 100.0, height: 4),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: 12,
      thickness: 1,
      color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
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

  /// Live count badge (e.g. pending received interests) — null/0 hides it.
  /// Never a hardcoded placeholder; callers derive this from real state.
  final int? count;

  /// Shows a small spinner in place of the trailing chevron and disables
  /// the tile — used by Logout while the confirm dialog / sign-out call is
  /// in flight, to prevent double-taps.
  final bool isLoading;

  const _DrawerItem({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.showChevron = true,
    this.labelColor,
    this.iconColor,
    this.onTap,
    this.count,
    this.isLoading = false,
  });

  @override
  State<_DrawerItem> createState() => _DrawerItemState();
}

class _DrawerItemState extends State<_DrawerItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  bool get _enabled => widget.onTap != null && !widget.isLoading;

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
      (widget.isActive ? AppColors.primary : AppColors.secondary);

  Color _effectiveLabelColor(bool isDark) =>
      widget.labelColor ??
      (isDark ? AppColors.textPrimaryDark : AppColors.primary);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = _effectiveIconColor;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      child: Opacity(
        opacity: _enabled ? 1.0 : 0.4,
        child: ScaleTransition(
          scale: _scale,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              onTapDown: _enabled ? (_) => _ctrl.reverse() : null,
              onTapCancel: _enabled ? () => _ctrl.forward() : null,
              onTap: _enabled
                  ? () {
                      _ctrl.forward();
                      widget.onTap?.call();
                    }
                  : null,
              child: Container(
                height: 52,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: widget.isActive
                      ? AppColors.softLavender.withValues(
                          alpha: isDark ? 0.16 : 1.0,
                        )
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: widget.isActive
                      ? const Border(
                          left: BorderSide(color: AppColors.primary, width: 3),
                        )
                      : null,
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: widget.isActive ? AppSpacing.sm : AppSpacing.sm + 3,
                    right: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(widget.icon, size: 20, color: iconColor),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          widget.label,
                          style: AppTypography.bodyMedium.copyWith(
                            color: _effectiveLabelColor(isDark),
                            fontWeight: widget.isActive
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.count != null && widget.count! > 0) ...[
                        UnreadBadge(count: widget.count!),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      if (widget.isLoading)
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              iconColor,
                            ),
                          ),
                        )
                      else if (widget.showChevron)
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: isDark
                              ? AppColors.textTertiaryDark
                              : AppColors.textTertiaryLight,
                        ),
                    ],
                  ),
                ),
              ),
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
        // Cream hairline rather than magenta: a magenta border on the plum
        // fill sits at ~1.7:1 and left the strip with no edge at all.
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: AppColors.premiumCream.withValues(alpha: 0.30),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.workspace_premium_rounded,
              size: 18,
              color: AppColors.accentSoft,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                l10n.drawerPremiumTitle,
                // Blush *surface* tone, not the mid-rose: this sits on a
                // solid plum fill where #F58CB4 lands under 4:1.
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.accentSoft,
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
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
              child: Text(
                l10n.drawerUpgrade,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textOnSecondary,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              '${l10n.drawerVersionLabel} v2.4',
              style: AppTypography.labelSmall.copyWith(
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiaryLight,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onRateUsTap,
            child: Text(
              AppLocalizations.of(context).drawerRateUs,
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.secondaryDark,
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
