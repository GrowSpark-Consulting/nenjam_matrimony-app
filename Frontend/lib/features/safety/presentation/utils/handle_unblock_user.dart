import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/dialogs/app_dialogs.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../inbox/presentation/providers/inbox_providers.dart';
import '../providers/safety_providers.dart';
import 'safety_error_message.dart';

/// Confirmation dialog -> (haptic) -> loading -> unblock -> SnackBar. Mirrors
/// `handleBlockUser`'s shape exactly (same dialog/progress/SnackBar
/// language) but never navigates away — unblocking doesn't remove anything
/// from view, unlike a block.
///
/// The single unblock implementation for the whole app — reused by Profile
/// Detail's "More" menu, and by the Privacy page's Blocked Profiles list
/// (`features/privacy/presentation/pages/privacy_page.dart`). Callers pass
/// [onUnblocked] for whatever local removal/flip is theirs to do: Profile
/// Detail flips its own "is this member blocked" flag (there's no backend
/// read endpoint for a single member's block status, so that flag only ever
/// lives in the widget that already knew it — see `ProfileDetailArgs.
/// isBlocked`'s doc comment); the Blocked Profiles list drops the row from
/// its own loaded page. Also syncs `ConversationsNotifier` (best-effort, no
/// extra network call) so a Chat thread with this member doesn't keep
/// showing a stale "Blocked" banner until the next full Inbox refresh.
Future<void> handleUnblockUser(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String userName,
  VoidCallback? onUnblocked,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await AppDialogs.showConfirmation(
    context,
    title: l10n.profileDetailUnblockConfirmTitle,
    message: l10n.profileDetailUnblockConfirmMessage,
    confirmLabel: l10n.profileDetailUnblockConfirmButton,
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
      AppDialogs.showProgress(context, message: l10n.profileDetailUnblockLoading);

  Object? error;
  try {
    await ref.read(safetyRepositoryProvider).unblockUser(userId);
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

  ref.read(conversationsNotifierProvider.notifier).applyBlockedFlag(userId, false);

  messenger.showSnackBar(
    SnackBar(content: Text(l10n.profileDetailUnblockSuccess(userName))),
  );
  onUnblocked?.call();
}
