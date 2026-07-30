import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/sheets/app_sheets.dart';
import '../../../../l10n/app_localizations.dart';
import '../widgets/report_user_sheet.dart';

/// Opens the report sheet (reason -> optional detail -> submit -> loading ->
/// success, all owned by [ReportUserSheet] itself). Reporting never blocks
/// or hides the member — pair with `handleBlockUser` (handle_block_user.dart)
/// if the caller wants both.
Future<void> handleReportUser(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String userName,
}) {
  final l10n = AppLocalizations.of(context);
  return AppSheets.show<void>(
    context,
    title: l10n.profileDetailReportReasonTitle(userName),
    child: ReportUserSheet(userId: userId, userName: userName),
  );
}
