import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../../inbox/presentation/providers/inbox_providers.dart';
import '../../../inbox/presentation/utils/open_chat_detail.dart';
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
/// raw "not yet interested" outlined look.
bool interestButtonIsSettled(InterestRelationshipStatus status) =>
    status != InterestRelationshipStatus.none &&
    status != InterestRelationshipStatus.cancelled;

/// The one place that decides what tapping this button actually *does* for
/// a given relationship state — reused by every Discover card variant,
/// Matches, and Profile Detail so they can never diverge:
///  - [none]/[cancelled] -> send a new interest.
///  - [sent]/[declined] -> nothing (already settled, no re-send here).
///  - [received] -> go to Received Interests, where Accept/Decline live.
///  - [accepted] -> open THAT person's Chat Detail directly (see
///    [_openDirectChat]) — not the generic Inbox.
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
        await ref
            .read(interestsNotifierProvider.notifier)
            .sendInterest(profile);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.interestsActionFailed)));
      }
    case InterestRelationshipStatus.received:
      context.push(RouteNames.interestsReceived);
    case InterestRelationshipStatus.accepted:
      await _openDirectChat(context, ref, profile, l10n);
    case InterestRelationshipStatus.sent:
    case InterestRelationshipStatus.declined:
      break;
  }
}

/// Dedicated handler for a "Message" affordance that's visible *regardless*
/// of relationship state (e.g. Profile Detail's chat icon button) — unlike
/// [handleInterestButtonTap], which only ever reaches its `accepted` branch
/// because the button's own label/enabled-state already gated it there,
/// this one has to branch on every status itself, since tapping it doesn't
/// imply the relationship is chat-eligible. The relationship status is the
/// single source of truth for whether chat opens — never the button's own
/// label or a caller's assumption.
Future<void> handleMessageButtonTap(
  BuildContext context,
  WidgetRef ref, {
  required DiscoveryProfileEntity profile,
  required InterestRelationshipStatus status,
  required AppLocalizations l10n,
}) async {
  switch (status) {
    case InterestRelationshipStatus.accepted:
      await _openDirectChat(context, ref, profile, l10n);
    case InterestRelationshipStatus.none:
    case InterestRelationshipStatus.cancelled:
      _showMessageGate(
        context,
        l10n.messageGateNoInterest,
        actionLabel: l10n.actionInterested,
        onAction: () =>
            ref.read(interestsNotifierProvider.notifier).sendInterest(profile),
      );
    case InterestRelationshipStatus.sent:
      _showMessageGate(context, l10n.messageGatePending);
    case InterestRelationshipStatus.received:
      _showMessageGate(
        context,
        l10n.messageGateRespondFirst,
        actionLabel: l10n.discoverRespondToInterest,
        onAction: () => context.push(RouteNames.interestsReceived),
      );
    case InterestRelationshipStatus.declined:
      _showMessageGate(context, l10n.messageGateDeclined);
  }
}

/// Resolves the conversation for [profile] (via
/// `ConversationsNotifier.getOrCreateConversationFor`, which itself
/// prefers an already-loaded conversation over a repository round-trip)
/// and pushes Chat Detail for it — the direct-message counterpart to the
/// old "just go to the generic Inbox" behavior. Only ever called once
/// [status] is already [InterestRelationshipStatus.accepted]; the
/// repository/backend are what actually enforce that (see
/// `ConversationRepository.getOrCreateConversation`'s doc comment), this
/// is just the one call site both `handleInterestButtonTap` and
/// [handleMessageButtonTap] share so the resolve-then-navigate logic can't
/// drift between them.
///
/// `openChatDetail` (`inbox/presentation/utils/open_chat_detail.dart`)
/// does a plain `context.push(RouteNames.chatDetail, extra: conversation)`
/// — safe here because `chatDetail` is an ordinary root-level `GoRoute`,
/// not a `StatefulShellRoute` branch (unlike `RouteNames.messages`), so it
/// stacks normally on the root Navigator alongside Profile Detail without
/// re-triggering the shell duplicate-Page-key issue that route name was
/// wrapped in `.go()` to avoid.
Future<void> _openDirectChat(
  BuildContext context,
  WidgetRef ref,
  DiscoveryProfileEntity profile,
  AppLocalizations l10n,
) async {
  final conversation = await ref
      .read(conversationsNotifierProvider.notifier)
      .getOrCreateConversationFor(profile);
  if (!context.mounted) return;
  if (conversation == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.messageGateError)));
    return;
  }
  if (conversation.isBlocked) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.messageGateBlocked)));
    return;
  }
  openChatDetail(context, conversation);
}

void _showMessageGate(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      action: actionLabel != null && onAction != null
          ? SnackBarAction(label: actionLabel, onPressed: onAction)
          : null,
    ),
  );
}
