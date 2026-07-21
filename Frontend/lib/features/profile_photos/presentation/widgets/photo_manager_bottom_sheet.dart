import 'package:flutter/material.dart';

import '../../../../core/widgets/sheets/app_sheets.dart';
import '../../../../l10n/app_localizations.dart';
import 'photo_manager_section.dart';

/// The single entry point for managing the signed-in user's photos from
/// anywhere in the app (drawer avatar, drawer "+" badge, …). Wraps the
/// existing [PhotoManagerSection] — upload, replace, delete, set-primary,
/// reorder are all already implemented there against [myPhotosProvider] —
/// in the app's shared [AppSheets] chrome so every caller gets the exact
/// same sheet instead of duplicating bottom-sheet/upload logic.
Future<void> showPhotoManagerBottomSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return AppSheets.show<void>(
    context,
    title: l10n.drawerManagePhotosTitle,
    child: const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: PhotoManagerSection(),
    ),
  );
}
