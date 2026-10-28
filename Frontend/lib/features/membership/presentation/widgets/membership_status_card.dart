import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../profile/presentation/widgets/premium_membership_card.dart';
import '../../domain/models/membership_models.dart';
import '../providers/membership_providers.dart';
import '../utils/membership_format.dart';

/// My Profile's membership card, driven by `GET /membership/me`.
///
/// Says only what the server reports: the member's plan and its end date, a
/// queued plan's start date, or the Free plan. While `/me` is loading or has
/// failed it claims nothing about the member's plan.
class MembershipStatusCard extends ConsumerWidget {
  const MembershipStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final me = ref.watch(myMembershipProvider).valueOrNull;
    final (title, subtitle) = me == null
        ? (l10n.premiumTitle, l10n.membershipCardFreeSubtitle)
        : _copy(me, l10n);
    return NmPremiumMembershipCard(
      title: title,
      subtitle: subtitle,
      ctaLabel: l10n.membershipCardViewMembership,
      // Premium is a bottom-nav tab — switch via the shell's go navigation,
      // not a stacked push.
      onCtaTap: () => context.go(RouteNames.premium),
    );
  }

  static (String, String) _copy(MyMembership me, AppLocalizations l10n) {
    if (me.hasPaidPlan) {
      final lines = <String>[
        if (me.subscription?.endDate != null)
          l10n.membershipCardActiveUntil(
            formatMembershipDate(me.subscription!.endDate!, l10n),
          ),
        for (final s in me.scheduled)
          if (s.startDate != null)
            l10n.membershipCardQueued(
              s.planName,
              formatMembershipDate(s.startDate!, l10n),
            ),
      ];
      return (l10n.membershipCardPlanTitle(me.plan.name), lines.join('\n'));
    }
    final subtitle = me.checkoutAvailable
        ? l10n.membershipCardFreeSubtitle
        : l10n.membershipCardFreeSubtitleSoon;
    return switch (me.source) {
      MembershipSource.free => (l10n.membershipCardFreeTitle, subtitle),
      // Catalogue unreadable, or a source this version doesn't know: claim
      // no plan either way.
      _ => (l10n.premiumTitle, subtitle),
    };
  }
}
