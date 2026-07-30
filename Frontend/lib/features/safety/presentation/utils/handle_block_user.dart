import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/dialogs/app_dialogs.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/safety_providers.dart';
import 'safety_error_message.dart';

/// Confirmation dialog -> (haptic) -> loading -> block -> SnackBar.
///
/// On success, either runs [onBlocked] (e.g. remove the card from a live
/// feed like the Matches reel — no navigation involved) or, if [onBlocked]
/// is omitted, pops the current route — the right default for a pushed page
/// like Profile Detail, where the blocked member is no longer reachable
/// (Discover, Search, and Matches all exclude blocked members, and neither
/// side can send interests or messages). Chat keeps its own separate
/// block/unblock affordance so an existing thread stays reachable and
/// reversible; this flow doesn't touch that.
///
/// IMPORTANT: the loading dialog's dismissal is fully awaited (via its own
/// `showDialog` Future, not a fire-and-forget) before anything else touches
/// the Navigator. Popping the dialog and then immediately popping the page
/// in the same synchronous turn — the previous shape of this function —
/// left the loading dialog's opaque, non-dismissible barrier orphaned on
/// top of whatever screen the pop landed on, appearing to freeze it (it was
/// still there, just invisible-if-transparent and eating every touch).
/// Popping via the explicit root navigator (matching `showDialog`'s own
/// `useRootNavigator: true` default, rather than `Navigator.of(context)`'s
/// differing default of the *nearest* one) removes any ambiguity about
/// which Navigator the dialog actually lives on.
Future<void> handleBlockUser(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String userName,
  VoidCallback? onBlocked,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await AppDialogs.showConfirmation(
    context,
    title: l10n.profileDetailBlockConfirmTitle,
    message: l10n.profileDetailBlockConfirmMessage,
    confirmLabel: l10n.profileDetailBlockConfirmButton,
  );
  if (!(confirmed ?? false)) return;
  if (!context.mounted) return;

  HapticFeedback.mediumImpact();

  final messenger = ScaffoldMessenger.of(context);
  // Non-dismissible progress dialog — also doubles as the "disable
  // everything while the request runs" guard: its modal barrier blocks
  // taps on the card/menu underneath, so a second block attempt can't fire
  // while the first is still in flight. Its Future is captured (not
  // discarded) so it can be awaited below once we pop it.
  final progressDialog =
      AppDialogs.showProgress(context, message: l10n.profileDetailBlockLoading);

  Object? error;
  try {
    await ref.read(safetyRepositoryProvider).blockUser(userId);
  } catch (e) {
    error = e;
  }

  if (context.mounted) {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (rootNavigator.canPop()) rootNavigator.pop();
  }
  // Block until the dialog route has actually finished closing — this is
  // the fix: nothing below touches the Navigator until this resolves.
  await progressDialog;
  if (!context.mounted) return;

  if (error != null) {
    messenger.showSnackBar(
      SnackBar(content: Text(safetyErrorMessage(l10n, error))),
    );
    return;
  }

  messenger.showSnackBar(
    SnackBar(content: Text(l10n.profileDetailBlockSuccess(userName))),
  );

  if (onBlocked != null) {
    onBlocked();
  } else if (context.mounted && context.canPop()) {
    context.pop();
  }
}
