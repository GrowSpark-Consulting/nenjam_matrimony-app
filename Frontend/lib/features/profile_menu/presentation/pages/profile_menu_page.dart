import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../core/widgets/indicators/nm_gradient_progress_bar.dart';
import '../../../../core/widgets/avatars/app_avatars.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../../authentication/presentation/utils/logout_flow.dart';
import '../../../inbox/presentation/widgets/unread_badge.dart';
import '../../../interests/domain/repositories/interests_repository.dart';
import '../../../interests/presentation/providers/interests_provider.dart';
import '../../../partner_preferences/presentation/utils/open_partner_preferences.dart';
import '../../../profile/presentation/providers/profile_dashboard_providers.dart';
import '../../../profile/presentation/utils/profile_dashboard_mapper.dart';
import '../../../profile_photos/presentation/providers/photo_providers.dart';
import '../../../profile_photos/presentation/widgets/photo_manager_bottom_sheet.dart';
import '../../../registration/presentation/utils/open_edit_profile.dart';
import '../../../shortlist/presentation/providers/shortlist_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ProfileMenuPage
// ─────────────────────────────────────────────────────────────────────────────
//
// The profile / account menu, presented as a FULL-SCREEN page. Reached by
// tapping the avatar in the TOP-LEFT of the Discover app bar, which pushes
// RouteNames.profileMenu onto the ROOT navigator — above the
// StatefulShellRoute — as an OPAQUE page (see app_router.dart), so nothing of
// Discover, and none of the floating bottom-nav pill that belongs to the
// shell's own Scaffold, shows behind or beside it.
//
// Why a route and not a Drawer: a Drawer belongs to exactly one Scaffold, so
// it could only ever open from Discover, it is capped at part of the screen
// width with the page underneath still showing beside it, it sits *under* the
// shell's floating bottom-nav pill, and it gives the Android back button
// nothing to pop. As an opaque route the page covers everything, keeps the
// back button and the existing /profile-menu deep link, carries the iOS
// back-swipe for free, and can be opened from any screen later without
// re-parenting it.
//
// Surface:  warm blush white (AppColors.backgroundLight) edge to edge — the
//           same token the menu has always used, in every theme mode.
//
// Layout (top → bottom):
//   0. AppBar                  (back arrow only; owns the status-bar inset)
//   ┌ one scroll view ────────────────────────────────────────────────────┐
//   │ 1. Profile header  (responsive 76–104dp avatar, name, subtitle, ID) │
//   │ 2. Profile Strength bar   (backend %, plum→magenta fill)            │
//   │ 3. Menu list      (section dividers, active plum accent, 54px rows) │
//   └─────────────────────────────────────────────────────────────────────┘
//   4. Premium upgrade strip   (pinned; compact, cream hairline)
//   5. Fixed bottom footer     (pinned; real app version + Rate Us)
// ─────────────────────────────────────────────────────────────────────────────

class ProfileMenuPage extends ConsumerStatefulWidget {
  /// Whether the user is a premium subscriber.
  ///
  /// TODO(backend): no subscription/premium-status endpoint is wired yet —
  /// the same placeholder the Discover and Profile pages already use.
  final bool isPremium;

  const ProfileMenuPage({super.key, this.isPremium = false});

  @override
  ConsumerState<ProfileMenuPage> createState() => _ProfileMenuPageState();
}

class _ProfileMenuPageState extends ConsumerState<ProfileMenuPage> {
  bool _loggingOut = false;

  /// Re-fetches every provider this page (and its badge counts) already
  /// reads — no new data sources, just re-triggering existing ones.
  Future<void> _onRefresh() async {
    await Future.wait([
      ref.refresh(profileDraftResponseProvider.future),
      ref.refresh(myPhotosProvider.future),
      ref.refresh(interestsNotifierProvider.future),
      ref.refresh(shortlistNotifierProvider.future),
    ]);
  }

  /// Guards against double-taps while the confirm dialog / sign-out call is
  /// in flight, and drives the row's inline spinner.
  Future<void> _handleLogout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await confirmAndLogout(context, ref);
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Single fetch shared by the header + strength bar — the same provider the
    // Profile page and Profile Completion screen already read, so this menu
    // never disagrees with them about who the user is or how complete their
    // profile is.
    final draftAsync = ref.watch(myProfileDraftProvider);
    final completionAsync = ref.watch(backendProfileCompletionProvider);
    final authUser = ref.watch(currentAuthUserProvider);
    final draft = draftAsync.valueOrNull;

    final identityLoading = draftAsync.isLoading && !draftAsync.hasValue;
    final identityError = draftAsync.hasError && !draftAsync.hasValue;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      // Bare AppBar — no title, just the platform back button. It inherits the
      // app-wide AppBarTheme (this page's own background, elevation 0,
      // SystemUiOverlayStyle.dark/light), which is what keeps the status bar
      // behaving exactly as on every other pushed page: no hardcoded inset,
      // no immersive mode, no bespoke overlay style.
      appBar: AppBar(),
      // top: false — the AppBar already consumed the status-bar inset. This is
      // here so the pinned footer clears the gesture bar / home indicator.
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // ── 1–3. Header, Profile Strength bar and menu — one scroll ────
            //
            // The header scrolls WITH the menu rather than staying pinned the
            // way the drawer's did. Pinned, header + strength bar + premium
            // strip + footer are ~310dp of fixed chrome, which is more than a
            // landscape 320dp-tall viewport has to give: the Expanded menu
            // collapsed to zero and the Column overflowed by up to 80px. As
            // part of the scroll they simply scroll away instead, and the
            // portrait layout is unchanged — the menu is always taller than
            // the viewport, so it scrolled either way.
            //
            // Destinations, order and handlers are the drawer's exactly —
            // only the close-the-drawer-first step is gone, since there is no
            // drawer left to close. Each one pushes onto the root navigator,
            // so this menu stays underneath and Back returns here.
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                color: AppColors.secondary,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (identityLoading)
                        const _IdentitySkeleton()
                      else if (identityError)
                        _IdentityError(
                          onRetry: () =>
                              ref.invalidate(profileDraftResponseProvider),
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
                          onAvatarTap: () =>
                              showPhotoManagerBottomSheet(context),
                        ),
                        _ProfileStrengthBar(
                          // The backend's `completionPercentage`, straight
                          // off the same GET /profiles/draft response the
                          // header above reads — never a number this page
                          // derives. 0 while it is genuinely unknown, rather
                          // than a flattering placeholder.
                          percent: completionAsync.valueOrNull ?? 0,
                          l10n: l10n,
                          onTap: () =>
                              context.push(RouteNames.profileCompletion),
                        ),
                      ],

                      // Thin divider
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.dividerLight,
                        indent: AppSpacing.base,
                        endIndent: AppSpacing.base,
                      ),

                      const SizedBox(height: AppSpacing.xs),

                      // Profile group
                      _DrawerItem(
                        icon: Icons.person_outline_rounded,
                        label: l10n.drawerProfile,
                        isActive: true,
                        onTap: () => context.push(RouteNames.profile),
                      ),
                      _DrawerItem(
                        icon: Icons.edit_outlined,
                        label: l10n.drawerEditProfile,
                        onTap: () => openEditProfile(context, ref),
                      ),
                      _DrawerItem(
                        icon: Icons.favorite_border_rounded,
                        label: l10n.drawerPartnerPreferences,
                        onTap: () => openPartnerPreferences(context, ref),
                      ),
                      _DrawerItem(
                        icon: Icons.auto_awesome_rounded,
                        label: l10n.drawerProfileIntelligence,
                        onTap: () =>
                            context.push(RouteNames.profileIntelligence),
                      ),
                      _DrawerItem(
                        icon: Icons.shield_outlined,
                        label: l10n.drawerVerificationCenter,
                        onTap: () =>
                            openEditProfile(context, ref, wizardStep: 12),
                      ),

                      _MenuSectionHeader(
                        label: l10n.drawerSectionMatchActivity,
                      ),

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
                          onTap: () => context.push(RouteNames.interestsSent),
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
                          onTap: () =>
                              context.push(RouteNames.interestsReceived),
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
                          onTap: () => context.push(RouteNames.shortlisted),
                        ),
                      ),
                      _DrawerItem(
                        // Same near_me arrow the distance pill on each Near Me
                        // card uses, so the icon means one thing app-wide.
                        icon: Icons.near_me_outlined,
                        label: l10n.drawerNearMe,
                        onTap: () => context.push(RouteNames.nearby),
                      ),
                      _DrawerItem(
                        // Same eye used by the Profile Viewers empty state and
                        // by the PROFILE_VIEW notification icon.
                        icon: Icons.visibility_outlined,
                        label: l10n.profileViewersTitle,
                        // push (not go), and deliberately without
                        // `openedFromNotification` — that omission is what
                        // makes Back fall back here rather than to the
                        // Notification Center.
                        onTap: () => context.push(RouteNames.profileViewers),
                      ),

                      _MenuSectionHeader(label: l10n.drawerSectionSettings),

                      // Settings group
                      _DrawerItem(
                        icon: Icons.language_outlined,
                        label: l10n.drawerLanguage,
                        onTap: () => context.push(RouteNames.language),
                      ),
                      _DrawerItem(
                        icon: Icons.settings_outlined,
                        label: l10n.drawerSettings,
                        onTap: () => context.push(RouteNames.settings),
                      ),
                      _DrawerItem(
                        icon: Icons.lock_outline_rounded,
                        label: l10n.drawerPrivacy,
                        onTap: () => context.push(RouteNames.privacy),
                      ),
                      _DrawerItem(
                        icon: Icons.help_outline_rounded,
                        label: l10n.drawerHelp,
                        onTap: () => context.push(RouteNames.help),
                      ),

                      _MenuDivider(),

                      // Logout — confirmAndLogout shows its confirm dialog over
                      // this page, and its final context.go(RouteNames.login)
                      // replaces the whole stack (this page included) once
                      // confirmed, so there is nothing to pop first.
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
                // go (not push): Premium is a bottom-nav branch, so this
                // switches to that tab and drops this page off the stack.
                onTap: () => context.go(RouteNames.premium),
              ),

            // ── 5. Fixed footer ────────────────────────────────────────────
            _DrawerFooter(l10n: l10n),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header/strength-bar loading + error placeholders — shown only on a cold
// start with no cached draft yet; a failed pull-to-refresh keeps showing the
// last-known values instead (see ProfileMenuPage.build).
// ─────────────────────────────────────────────────────────────────────────────

class _IdentitySkeleton extends StatelessWidget {
  const _IdentitySkeleton();

  @override
  Widget build(BuildContext context) {
    // Mirrors the loaded header's metrics so nothing jumps when the draft
    // arrives.
    final hPad = _headerHorizontalPadding(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, AppSpacing.lg, hPad, AppSpacing.md),
      child: Column(
        children: [
          NmShimmer.circle(size: _avatarDiameter(context)),
          const SizedBox(height: AppSpacing.md),
          const NmShimmer(
            width: 150,
            height: 20,
            borderRadius: AppSpacing.radiusSm,
          ),
          const SizedBox(height: AppSpacing.xs2),
          const NmShimmer(
            width: 110,
            height: 14,
            borderRadius: AppSpacing.radiusSm,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: NmShimmer(height: 52, borderRadius: AppSpacing.radiusSm),
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
                color: AppColors.textSecondaryLight,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Flexible, with a compact minimum: inside the panel there is
          // roughly 280dp to share, and the Tamil "Retry" label at the
          // button's default 64dp minimum + 16dp side padding pushed the row
          // over. It now gives ground before the message does.
          Flexible(
            child: TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, AppConstants.minTouchTarget),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              child: Text(
                AppLocalizations.of(context).commonRetry,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.secondaryDark,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Header — responsive avatar (76–104dp)
// ─────────────────────────────────────────────────────────────────────────────

/// Avatar diameter as a bounded fraction of the device's SHORTEST side.
///
/// Shortest side rather than raw width so a rotated phone doesn't suddenly
/// hand the header a 700dp-wide screen and an avatar that eats the whole
/// landscape viewport — the same device gets the same avatar either way.
/// The clamp is what keeps it honest at both ends: never smaller than the
/// old fixed 72dp felt on a compact phone, never a portrait-filling disc on
/// a tablet.
///
///   320dp → 76.8 · 360dp → 86.4 · 393dp → 94.3 · 412dp → 98.9 · 480dp+ → 104
double _avatarDiameter(BuildContext context) =>
    (MediaQuery.sizeOf(context).shortestSide * 0.24).clamp(76.0, 104.0);

/// Overlay badge diameter ("+", verified tick, premium crown), tied to the
/// avatar so the badges keep their proportion as it grows.
double _avatarBadgeSize(double avatarDiameter) =>
    (avatarDiameter * 0.26).clamp(20.0, 26.0);

/// Horizontal padding for the header and the Profile Strength card. Phones
/// keep the existing 16dp; only tablets/desktop widen, via the project's
/// existing [ResponsiveUtils.adaptive] convention.
double _headerHorizontalPadding(BuildContext context) =>
    ResponsiveUtils.adaptive(
      context,
      phone: AppSpacing.base,
      tablet: AppSpacing.xl,
      desktop: AppSpacing.xl2,
    );

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
    const badgeRingColor = AppColors.backgroundLight;
    final avatar = _avatarDiameter(context);
    final badge = _avatarBadgeSize(avatar);
    final hPad = _headerHorizontalPadding(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, AppSpacing.lg, hPad, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Circular avatar with plum ring ─────────────────────────────
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
                    width: avatar,
                    height: avatar,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.secondary,
                        width: 1.5,
                      ),
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primarySurface,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _LiveAvatarImage(
                        imageUrl: imageUrl,
                        gender: gender,
                        // Inside the 2dp pad and the 1.5dp ring.
                        size: avatar - 7,
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
                      width: badge,
                      height: badge,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.verifiedBlue,
                        border: Border.all(color: badgeRingColor, width: 1.5),
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        size: badge * 0.68,
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
                    width: badge,
                    height: badge,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.verifiedBlue,
                      border: Border.all(color: badgeRingColor, width: 1.5),
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: badge * 0.55,
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
                    width: badge,
                    height: badge,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.secondary,
                      border: Border.all(color: badgeRingColor, width: 1.5),
                    ),
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      size: badge * 0.55,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // ── Name ─────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name,
                  // 16 → 18: the header's anchor, so it takes the largest
                  // share of this screen's ~10% type increase. Still a step
                  // below titleLarge, which keeps the hierarchy intact.
                  style: AppTypography.titleMedium.copyWith(
                    fontSize: 18,
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
                  size: 18,
                  color: AppColors.verifiedBlue,
                ),
              ],
            ],
          ),

          // ── Subtitle: age • location ─────────────────────────────────────
          const SizedBox(height: AppSpacing.xs2),
          Text(
            [if (age > 0) '$age', location].join(' • '),
            // 12 → 13
            style: AppTypography.bodySmall.copyWith(
              fontSize: 13,
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
              // 11 → 12
              style: AppTypography.labelSmall.copyWith(
                fontSize: 12,
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
          //
          // Tappable, because the ID is the one thing on this screen a
          // member has to give to somebody else — support, or a match
          // asking which profile is theirs. Reading a 10-character code off
          // the screen to retype it is the alternative, so the pill copies
          // itself and says so.
          if (profileId.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            _ProfileIdChip(profileId: profileId),
          ],
        ],
      ),
    );
  }
}

/// The profile ID, in a pill that copies it to the clipboard when tapped.
///
/// Stateful only to hold the "copied" acknowledgement: the icon swaps to a
/// tick for a moment so the tap has a visible result even when a snack bar
/// is covered by something else, then returns to the copy glyph. Nothing
/// about the ID itself changes.
class _ProfileIdChip extends StatefulWidget {
  final String profileId;

  const _ProfileIdChip({required this.profileId});

  @override
  State<_ProfileIdChip> createState() => _ProfileIdChipState();
}

class _ProfileIdChipState extends State<_ProfileIdChip> {
  static const Duration _ackDuration = Duration(seconds: 2);

  bool _copied = false;
  Timer? _ackTimer;

  @override
  void dispose() {
    _ackTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // The bare ID, not the "ID: x" label around it - what a member pastes
    // into a support chat should be the identifier alone.
    await Clipboard.setData(ClipboardData(text: widget.profileId));
    if (!mounted) return;

    setState(() => _copied = true);
    _ackTimer?.cancel();
    _ackTimer = Timer(_ackDuration, () {
      if (mounted) setState(() => _copied = false);
    });

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.drawerIdCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Semantics(
      button: true,
      label: l10n.drawerCopyIdSemanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _copy,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              border: Border.all(
                color: AppColors.secondary.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    l10n.profileIdLabel(widget.profileId),
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.secondaryDark,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs2),
                Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 13,
                  color: AppColors.secondaryDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reads the live current-user photo directly from [myPrimaryPhotoUrlProvider]
/// — scoped to just this leaf widget (not the whole page) so uploading,
/// replacing, or deleting a photo only rebuilds this small avatar, not the
/// entire [ProfileMenuPage] menu tree. Falls back to the [imageUrl]
/// prop (the caller's best-known value) until the provider has loaded, then
/// to the gender placeholder if the user has no photos at all.
class _LiveAvatarImage extends ConsumerWidget {
  final String? imageUrl;
  final String gender;

  /// Inner diameter, derived from the responsive ring around it.
  final double size;

  const _LiveAvatarImage({this.imageUrl, this.gender = '', this.size = 65});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveUrl = ref.watch(myPrimaryPhotoUrlProvider);
    return NmCircleAvatar(
      imageUrl: liveUrl ?? imageUrl,
      size: size,
      gender: gender,
      // Bias the cover-crop upward so the face stays centered in the
      // circle without the head's top being cut off by a dead-center crop.
      alignment: const Alignment(0, -0.2),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Strength Bar
//
// [percent] is the backend's completionPercentage, passed straight through:
// this widget renders it, it never computes a score of its own, and there is
// no second metric on this card.
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
        // No fixed height: the card now sizes to its own content, so a
        // larger system text scale grows it instead of clipping the label.
        margin: EdgeInsets.symmetric(
          horizontal: _headerHorizontalPadding(context),
          vertical: AppSpacing.xs,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.softLavender.withValues(alpha: 1.0),
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
                // 11 → 12
                Flexible(
                  child: Text(
                    l10n.drawerProfileStrength,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textSecondaryLight,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // 11 → 14: the figure is the point of the card.
                Text(
                  '$clamped%',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Plum→magenta fill over the soft lavender track, filled to
            // exactly [clamped]% — 8dp so the ramp reads as a deliberate
            // measure rather than a hairline. The fill animates itself in
            // (NmGradientProgressBar already did), matching the completion
            // hero on the Profile Strength screen.
            NmGradientProgressBar(value: clamped / 100.0, height: 8),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Menu Section Header
// ─────────────────────────────────────────────────────────────────────────────

/// The title that opens a group of menu rows.
///
/// Replaces the bare rule that used to separate the groups: the rows are
/// grouped by what they are *for* (match activity, then options), and a
/// hairline alone left the reader to infer that from adjacency. The first
/// group has no header on purpose — it sits directly under the identity
/// block, which is its heading.
class _MenuSectionHeader extends StatelessWidget {
  final String label;

  const _MenuSectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Generous above, tight below: the space belongs to the boundary with
      // the group that ended, not between this title and the rows it heads.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.xs,
      ),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: AppTypography.titleSmall.copyWith(
            color: AppColors.textPrimaryLight,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
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
// Drawer Menu Item — 54px height
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

  Color _effectiveLabelColor() => widget.labelColor ?? AppColors.primary;

  @override
  Widget build(BuildContext context) {
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
                height: 54,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: widget.isActive
                      ? AppColors.softLavender.withValues(alpha: 1.0)
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
                      Icon(widget.icon, size: 22, color: iconColor),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          widget.label,
                          // 14 → 15
                          style: AppTypography.bodyMedium.copyWith(
                            fontSize: 15,
                            color: _effectiveLabelColor(),
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
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: AppColors.textTertiaryLight,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.xs,
        AppSpacing.base,
        AppSpacing.xs,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            // Full-width and gradient-filled, where this used to be a
            // compact bordered strip. It is the one commercial action on
            // the panel and the only thing here that is not navigation, so
            // it reads as a button rather than as another menu row - and
            // sitting directly above the footer, a hairline box was easy to
            // mistake for one.
            decoration: BoxDecoration(
              gradient: AppGradients.match,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: AppSpacing.sm,
              ),
              // Two parts, the way the reference lays this out: what the
              // offer IS on the left, the action on the right. Centring a
              // lone "Upgrade Now" dropped the product name entirely, so
              // the row read as a button with no subject.
              child: Row(
                children: [
                  const Icon(
                    Icons.workspace_premium_rounded,
                    size: 18,
                    // White on the magenta gradient, not the blush tone the
                    // bordered version used: that was chosen against a
                    // solid plum fill and drops under 4:1 on this one.
                    color: Colors.white,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      l10n.drawerPremiumTitle,
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // The action itself, as a pill on the gradient. White
                  // ground rather than another tint of magenta, so it reads
                  // as the one tappable thing in a row that is already
                  // entirely tappable.
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusFull,
                        ),
                      ),
                      child: Text(
                        l10n.drawerUpgrade,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.secondaryDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Fixed Footer
// ─────────────────────────────────────────────────────────────────────────────

class _DrawerFooter extends StatelessWidget {
  final AppLocalizations l10n;

  const _DrawerFooter({required this.l10n});

  /// Opens the app's store listing. `externalApplication` is what hands the
  /// https link to the Play Store app on Android (rather than an in-app web
  /// view); everywhere else it opens in the browser.
  Future<void> _rateUs(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final label = l10n.safetyErrorGeneric;
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(AppConstants.storeListingUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (!launched) {
      messenger.showSnackBar(SnackBar(content: Text(label)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rendered fresh each build rather than baked into a constant: a range
    // ending in a year that has already passed is the classic dead-footer
    // tell, and there is nothing here worth caching to avoid it.
    final year = DateTime.now().year.toString();

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.base,
        AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.dividerLight)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Legal + Rate Us ──────────────────────────────────────────
          //
          // One row, because both are actions; the two lines under it are
          // facts about the build and are never tappable.
          Row(
            children: [
              Flexible(
                child: _FooterLink(
                  label: l10n.drawerTerms,
                  underline: true,
                  // The screen the app already has for this. Not a new
                  // page, and not an external URL - the content lives in
                  // the app.
                  onTap: () => context.push(RouteNames.privacy),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // The label used to be inert - the old drawer's `onRateUsTap`
              // hook was never wired by any caller. There is no in-app
              // review flow in the project to reuse, so this opens the
              // store listing with the url_launcher the Help screen already
              // uses, rather than pulling in a review SDK.
              Flexible(
                child: _FooterLink(
                  label: l10n.drawerRateUs,
                  onTap: () => _rateUs(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            l10n.drawerCopyright(year),
            style: _footerTextStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            // The build's real version, from the single constant the rest
            // of the app already reads - never a number typed in here.
            l10n.drawerVersion(AppConstants.appVersion),
            style: _footerTextStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Shared by both footer text lines so they cannot drift apart. Off the
/// project's type scale rather than a bare TextStyle, so it inherits the
/// family and tracking every other label on this screen uses.
final TextStyle _footerTextStyle = AppTypography.labelSmall.copyWith(
  fontSize: 11,
  height: 1.4,
  color: AppColors.textTertiaryLight,
);

/// A tappable footer label. Flexible by design: the Tamil strings are
/// roughly twice the width of the English ones, so both halves of the row
/// shrink rather than overflow — on a 320dp phone there is no slack.
class _FooterLink extends StatelessWidget {
  final String label;
  final bool underline;
  final VoidCallback onTap;

  const _FooterLink({
    required this.label,
    required this.onTap,
    this.underline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs2),
          child: Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.secondaryDark,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              decoration: underline ? TextDecoration.underline : null,
              decorationColor: AppColors.secondaryDark,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
