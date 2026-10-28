import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/membership_models.dart';
import '../providers/membership_providers.dart';
import '../utils/membership_format.dart';

/// The membership refusal carried by [error], or null when it is anything
/// else — including the account-blocked 403, which has no `code`.
ApiException? membershipDenialOf(Object? error) =>
    error is ApiException && error.isMembershipDenial ? error : null;

/// Whether the refusal sheet may offer an upgrade, per the contract: only
/// with a non-null `upgradeTo`, while checkout is available, never for the
/// fair-use limit, and never for a `LEGACY`/`UNAVAILABLE` member.
bool mayOfferUpgrade(ApiException denial, MyMembership? me) =>
    denial.upgradeTo != null &&
    denial.code != 'MEMBERSHIP_FAIR_USE_LIMIT' &&
    me != null &&
    me.checkoutAvailable &&
    me.mayShowUpgradePrompts;

/// Shows the refusal sheet when [error] is a membership 403 and returns true;
/// returns false (and shows nothing) for any other error, so the caller keeps
/// its existing handling. The server's `message` is always a full sentence,
/// so it is shown as is. The 403 is the authority — nothing is pre-checked.
bool showMembershipDenialIfAny(
  BuildContext context,
  WidgetRef ref,
  Object? error,
) {
  final denial = membershipDenialOf(error);
  if (denial == null) return false;
  final me = ref.read(myMembershipProvider).valueOrNull;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => MembershipDenialSheet(
      denial: denial,
      offerUpgrade: mayOfferUpgrade(denial, me),
    ),
  );
  return true;
}

class MembershipDenialSheet extends StatelessWidget {
  const MembershipDenialSheet({
    super.key,
    required this.denial,
    required this.offerUpgrade,
  });

  final ApiException denial;
  final bool offerUpgrade;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final resetsAt = denial.resetsAt;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.membershipDenialTitle, style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(denial.message, style: AppTypography.bodyMedium),
            if (resetsAt != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.membershipDenialResetsOn(
                  formatMembershipDate(resetsAt, l10n),
                ),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            if (offerUpgrade) ...[
              NmGradientButton(
                label: l10n.membershipDenialSeePlans,
                useAccentGradient: true,
                onPressed: () {
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  router.go(RouteNames.premium);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(MaterialLocalizations.of(context).closeButtonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
