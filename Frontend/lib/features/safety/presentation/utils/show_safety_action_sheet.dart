import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/sheets/app_sheets.dart';
import '../../../../l10n/app_localizations.dart';
import 'handle_block_user.dart';
import 'handle_report_user.dart';
import 'handle_unblock_user.dart';

/// The "More" sheet — Report User / Block or Unblock User / Cancel — shared
/// by every screen with a member-safety entry point (Matches reel card,
/// Profile Detail's hero app bar) so all of them present and behave
/// identically rather than each wiring up its own copy of
/// `AppSheets.showActionSheet`.
///
/// [isBlocked] picks which of Block/Unblock is offered — see
/// `ProfileDetailArgs.isBlocked`'s doc comment for why a caller would ever
/// already know this (the Matches reel never does; a blocked member can't
/// appear there in the first place, so it always passes `false`).
/// [onBlocked]/[onUnblocked] run after their respective successful action
/// instead of the default "pop the current route" behaviour — pass them on
/// screens where the member's card should just be removed from (or synced
/// in) a live list rather than navigating away.
Future<void> showSafetyActionSheet(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String userName,
  bool isBlocked = false,
  VoidCallback? onBlocked,
  VoidCallback? onUnblocked,
}) {
  HapticFeedback.mediumImpact();
  final l10n = AppLocalizations.of(context);

  return AppSheets.showActionSheet(
    context,
    title: userName,
    actions: [
      AppSheetAction(
        icon: Icons.flag_outlined,
        label: l10n.profileDetailActionReport,
        onTap: () => handleReportUser(context, ref, userId: userId, userName: userName),
      ),
      if (isBlocked)
        AppSheetAction(
          icon: Icons.lock_open_rounded,
          label: l10n.profileDetailActionUnblock,
          onTap: () => handleUnblockUser(
            context,
            ref,
            userId: userId,
            userName: userName,
            onUnblocked: onUnblocked,
          ),
        )
      else
        AppSheetAction(
          icon: Icons.block_rounded,
          label: l10n.profileDetailActionBlock,
          isDestructive: true,
          onTap: () => handleBlockUser(
            context,
            ref,
            userId: userId,
            userName: userName,
            onBlocked: onBlocked,
          ),
        ),
      AppSheetAction(
        icon: Icons.close_rounded,
        label: l10n.commonCancel,
        onTap: () {},
      ),
    ],
  );
}
