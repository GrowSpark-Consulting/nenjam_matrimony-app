import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../interests/domain/repositories/interests_repository.dart';
import '../../../interests/presentation/providers/interests_provider.dart';
import '../../../interests/presentation/utils/interest_button_copy.dart';
import '../../domain/entities/profile_detail_entity.dart';

/// Sticky bottom bar: gradient "Send Interest"/"Message" pill + chat icon
/// button, matching the design reference's bottom action bar.
///
/// Both buttons route through `handleInterestButtonTap`/
/// `handleMessageButtonTap` (`interest_button_copy.dart`) — the single
/// place that decides what tapping either one actually does, based on the
/// current [InterestRelationshipStatus], never on the button's own label.
/// Only an ACCEPTED interest opens Chat Detail directly; every other
/// status shows guidance instead (send an interest, wait for acceptance,
/// respond to theirs) — see that file's doc comments for the full mapping.
class ProfileDetailBottomActionBar extends ConsumerStatefulWidget {
  final ProfileDetailEntity detail;

  const ProfileDetailBottomActionBar({super.key, required this.detail});

  /// The bar's own height, excluding the device's bottom inset — the 52px
  /// buttons plus this widget's vertical padding. Declared here rather than
  /// measured so the page can reserve room for the bar at the end of its
  /// scroll content; see [reservedHeight].
  static const double contentHeight = 52 + AppSpacing.sm * 2;

  /// How much vertical space the bar covers on this device, inset included.
  ///
  /// The bar floats over the page rather than occupying a
  /// `Scaffold.bottomNavigationBar` slot (see [ProfileDetailPage] for why),
  /// so the scroll view has to reserve this much padding at its end to keep
  /// the last card clear of it.
  static double reservedHeight(BuildContext context) =>
      contentHeight + MediaQuery.paddingOf(context).bottom;

  @override
  ConsumerState<ProfileDetailBottomActionBar> createState() =>
      _ProfileDetailBottomActionBarState();
}

class _ProfileDetailBottomActionBarState
    extends ConsumerState<ProfileDetailBottomActionBar> {
  bool _isSending = false;
  bool _isResolvingChat = false;

  Future<void> _handleSendInterest(
    AppLocalizations l10n,
    InterestRelationshipStatus status,
  ) async {
    if (_isSending) return;
    setState(() => _isSending = true);
    await handleInterestButtonTap(
      context,
      ref,
      profile: widget.detail.base,
      status: status,
      l10n: l10n,
    );
    if (mounted) setState(() => _isSending = false);
  }

  Future<void> _handleMessageTap(
    AppLocalizations l10n,
    InterestRelationshipStatus status,
  ) async {
    if (_isResolvingChat) return; // guards rapid taps from opening >1 Chat Detail
    setState(() => _isResolvingChat = true);
    await handleMessageButtonTap(
      context,
      ref,
      profile: widget.detail.base,
      status: status,
      l10n: l10n,
    );
    if (mounted) setState(() => _isResolvingChat = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = ref.watch(
      interestRelationshipStatusProvider(widget.detail.base.id),
    );
    final settled = interestButtonIsSettled(status);

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.base,
        AppSpacing.sm + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        boxShadow: AppShadows.bottomNav,
      ),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              borderRadius: AppSpacing.borderRadiusXl,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _isSending
                    ? null
                    : () => _handleSendInterest(l10n, status),
                child: Ink(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: settled ? null : AppGradients.accent,
                    color: settled ? AppColors.faceVerificationGreen : null,
                    borderRadius: AppSpacing.borderRadiusXl,
                    boxShadow: settled ? null : AppShadows.accentGlow,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isSending)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      else
                        Icon(
                          settled
                              ? Icons.check_circle_rounded
                              : Icons.favorite_rounded,
                          size: 20,
                          color: settled
                              ? Colors.white
                              : AppColors.textOnSecondary,
                        ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          interestButtonLabel(
                            status,
                            l10n,
                            noneLabel: l10n.profileDetailSendInterest,
                            sentLabel: l10n.profileDetailInterestSent,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.button.copyWith(
                            color: settled
                                ? Colors.white
                                : AppColors.textOnSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _CircleActionButton(
            icon: Icons.chat_bubble_rounded,
            isLoading: _isResolvingChat,
            onTap: _isResolvingChat
                ? null
                : () => _handleMessageTap(l10n, status),
          ),
        ],
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isLoading;

  const _CircleActionButton({
    required this.icon,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 52,
          height: 52,
          child: isLoading
              ? const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
