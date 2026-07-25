import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../domain/repositories/interests_repository.dart';
import '../providers/interests_provider.dart';

/// Localized label for a "Send Interest"-style button, driven entirely by
/// the shared [InterestRelationshipStatus] — every Discover/Matches card
/// and Profile Detail's bottom bar call this instead of keeping their own
/// copy, so the same relationship always reads the same everywhere.
///
/// [noneLabel]/[sentLabel] let a call site substitute its own existing,
/// more specific copy for those two states (e.g. Profile Detail's
/// full-sentence "Send Interest"/"Interest Sent" CTA copy) without losing
/// the shared received/accepted/declined wording every surface gets for
/// free.
String interestButtonLabel(
  InterestRelationshipStatus status,
  AppLocalizations l10n, {
  String? noneLabel,
  String? sentLabel,
}) {
  switch (status) {
    case InterestRelationshipStatus.none:
    case InterestRelationshipStatus.cancelled:
      return noneLabel ?? l10n.actionInterested;
    case InterestRelationshipStatus.sent:
      return sentLabel ?? l10n.discoverInterestSentLabel;
    case InterestRelationshipStatus.received:
      return l10n.discoverRespondToInterest;
    case InterestRelationshipStatus.accepted:
      return l10n.actionMessage;
    case InterestRelationshipStatus.declined:
      return l10n.interestStatusDeclined;
  }
}

/// True once a relationship exists in some form — used to swap a button's
/// icon/color to its "settled" look (checkmark, muted, etc.) instead of the
/// raw "not yet interested" gold/outlined look.
bool interestButtonIsSettled(InterestRelationshipStatus status) =>
    status != InterestRelationshipStatus.none &&
    status != InterestRelationshipStatus.cancelled;

/// The one place that decides what tapping this button actually *does* for
/// a given relationship state — reused by every Discover card variant,
/// Matches, and Profile Detail so they can never diverge:
///  - [none]/[cancelled] -> send a new interest.
///  - [sent]/[declined] -> nothing (already settled, no re-send here).
///  - [received] -> go to Received Interests, where Accept/Decline live.
///  - [accepted] -> go to the Inbox (no per-user thread concept exists yet,
///    see `profile_detail_bottom_action_bar.dart`'s existing Chat button,
///    which already only pushes the single generic Messages route).
Future<void> handleInterestButtonTap(
  BuildContext context,
  WidgetRef ref, {
  required DiscoveryProfileEntity profile,
  required InterestRelationshipStatus status,
  required AppLocalizations l10n,
}) async {
  switch (status) {
    case InterestRelationshipStatus.none:
    case InterestRelationshipStatus.cancelled:
      try {
        await ref.read(interestsNotifierProvider.notifier).sendInterest(profile);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.interestsActionFailed)),
        );
      }
    case InterestRelationshipStatus.received:
      context.push(RouteNames.interestsReceived);
    case InterestRelationshipStatus.accepted:
      context.push(RouteNames.messages);
    case InterestRelationshipStatus.sent:
    case InterestRelationshipStatus.declined:
      break;
  }
}
