import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../interests/domain/repositories/interests_repository.dart';
import '../../../interests/presentation/providers/interests_provider.dart';
import '../../../interests/presentation/utils/interest_button_copy.dart';
import '../../domain/entities/profile_detail_entity.dart';

/// Sticky bottom bar: gold "Send Interest" pill + chat + video icon
/// buttons, matching the design reference's bottom action bar.
///
/// "Start Conversation" pushes the single existing [RouteNames.messages]
/// route — there is no per-target-user chat thread concept anywhere in the
/// app yet. Video calling doesn't exist at all, so that button is a stub.
class ProfileDetailBottomActionBar extends ConsumerStatefulWidget {
  final ProfileDetailEntity detail;

  const ProfileDetailBottomActionBar({super.key, required this.detail});

  @override
  ConsumerState<ProfileDetailBottomActionBar> createState() =>
      _ProfileDetailBottomActionBarState();
}

class _ProfileDetailBottomActionBarState
    extends ConsumerState<ProfileDetailBottomActionBar> {
  bool _isSending = false;

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = ref.watch(interestRelationshipStatusProvider(widget.detail.base.id));
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
                onTap: _isSending ? null : () => _handleSendInterest(l10n, status),
                child: Ink(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: settled ? null : AppGradients.gold,
                    color: settled ? AppColors.faceVerificationGreen : null,
                    borderRadius: AppSpacing.borderRadiusXl,
                    boxShadow: settled ? null : AppShadows.goldGlow,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isSending)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      else
                        Icon(
                          settled ? Icons.check_circle_rounded : Icons.favorite_rounded,
                          size: 20,
                          color: settled ? Colors.white : AppColors.textOnGold,
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
                            color: settled ? Colors.white : AppColors.textOnGold,
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
            onTap: () => context.push(RouteNames.messages),
          ),
          const SizedBox(width: AppSpacing.sm),
          _CircleActionButton(
            icon: Icons.videocam_rounded,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.profileDetailVideoComingSoon)),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleActionButton({required this.icon, required this.onTap});

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
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
