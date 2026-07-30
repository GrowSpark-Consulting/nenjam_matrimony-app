import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/dialogs/app_dialogs.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../safety/presentation/utils/safety_error_message.dart';
import '../../domain/entities/conversation_entity.dart';
import '../providers/inbox_providers.dart';

/// Shared unblock flow for every place a blocked conversation is shown
/// (Chat Detail's blocked banner, Chat Detail's overflow menu, the Inbox
/// list's long-press options sheet) — confirmation -> haptic -> loading ->
/// unblock -> SnackBar. The banner/menu disappear immediately because
/// [ConversationsNotifier.unblock] flips `isBlocked` optimistically; a
/// failed request rolls that back and this shows an error instead.
Future<void> handleUnblockConversation(
  BuildContext context,
  WidgetRef ref,
  ConversationEntity conversation,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await AppDialogs.showConfirmation(
    context,
    title: l10n.inboxUnblockConfirmTitle(conversation.profile.name),
    message: l10n.inboxUnblockConfirmMessage,
    confirmLabel: l10n.inboxActionUnblock,
  );
  if (!(confirmed ?? false)) return;
  if (!context.mounted) return;

  HapticFeedback.mediumImpact();
  final messenger = ScaffoldMessenger.of(context);
  // Captured (not fire-and-forget) so it can be awaited below — see
  // `handleBlockUser`'s doc comment for why popping this and then touching
  // the Navigator again without waiting for it to actually close can leave
  // the calling screen stuck under an orphaned barrier.
  final progressDialog =
      AppDialogs.showProgress(context, message: l10n.inboxUnblockLoading);

  Object? error;
  try {
    await ref.read(conversationsNotifierProvider.notifier).unblock(conversation.id);
  } catch (e) {
    error = e;
  }

  if (context.mounted) {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (rootNavigator.canPop()) rootNavigator.pop();
  }
  await progressDialog;
  if (!context.mounted) return;

  if (error != null) {
    messenger.showSnackBar(
      SnackBar(content: Text(safetyErrorMessage(l10n, error))),
    );
    return;
  }

  messenger.showSnackBar(
    SnackBar(content: Text(l10n.inboxUnblockSuccess(conversation.profile.name))),
  );
}
